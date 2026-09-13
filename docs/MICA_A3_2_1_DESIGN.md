# MICA Authorization Design Specification: Identity, Profiles & Org Admin (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: DESIGN FROZEN & UPDATED (PLATFORM AUDIT SEPARATION & MULTI-ORG RESOLUTION)  
> **Baseline Commit**: `6208d9db21359a2eb54e84021a176f163b53faf9`  
> **Target Schema Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  

---

## 1. Executive Summary & Core Architectural Principles

WP-A3.2.1 executes the **first vertical authorization cutover** in MICA, transitioning Identity, User Profiles, Member Administration, and Organization-Scoped Audit Visibility from legacy role-string authorization (`private.func_role() = 'ADMIN'` / `private.org_id()`) to the frozen M019/M021 capability foundation.

### Four Fundamental Invariants:
1. **ACTIVE CONTEXT != AUTHORIZATION**:
   - `private.active_org_id()` is an operation selector for tenant actions when `p_org_id` is omitted. It is **never** an authorization grant or blocker for global platform capabilities.
2. **GLOBAL PROFILE STATE vs TENANT MEMBERSHIP STATE SEPARATION**:
   - Platform account activation (`eco_user_profiles.is_active`) and Tenant membership activation (`eco_organization_members.is_active`) are distinct scopes governed by separate explicit RPCs.
3. **EXPLICIT AUDIT PARTITIONING (TENANT vs PLATFORM AUDIT)**:
   - Tenant audit remains strictly in `public.eco_audit_events` with `organization_id NOT NULL`.
   - Global/platform operations (such as `set_global_user_active` and `switch_superadmin_org_context`) emit exclusively to `public.eco_platform_audit_events`.
   - No fake organization UUIDs are ever used for platform events.
4. **`eco_user_profiles.organization_id` & `eco_user_profiles.role` ARE NON-AUTHORITATIVE**:
   - Canonical tenant authority, membership roles, and organization-scoped active states reside **exclusively in `public.eco_organization_members`**.
   - `eco_user_profiles.role` is synchronized purely as a lossy compatibility artifact for frontend session display (`src/js/ui.js`); **zero** backend authorization paths evaluate it.

---

## 2. Platform Audit Table Design (`public.eco_platform_audit_events`)

```sql
CREATE TABLE public.eco_platform_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_profile_id UUID NULL REFERENCES public.eco_user_profiles(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  target_user_profile_id UUID NULL REFERENCES public.eco_user_profiles(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Governance & Security:
- **Append-Only**: Trigger `enforce_append_only_platform_audit` executes `private.prevent_audit_mutation()` before `UPDATE` or `DELETE`.
- **Row Level Security**: Enabled.
  - `SELECT`: Restricted to callers holding `AUDIT_PLATFORM_VIEW` or `PLATFORM_MANAGE` via `private.can_platform(...)`.
  - `INSERT / UPDATE / DELETE`: Zero authenticated direct mutation policies. Mutations are strictly internal to trusted `SECURITY DEFINER` platform RPCs.

---

## 3. Operation Scopes & RPC Design

### 3.1 Operation Scope Table

| RPC Function | Operation Scope | Required Capability | Primary Target Entity | Audit Destination & Event |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | **ORGANIZATION_MEMBERSHIP** | `ORG_MEMBER_PERMISSION_MANAGE` (Org) | `eco_organization_members` | `eco_audit_events` &rarr; `USER_ROLE_CHANGED` (Scoped to `v_target_org_id`) |
| `public.set_user_active` | **ORGANIZATION_MEMBERSHIP** | `ORG_MEMBER_MANAGE` (Org) | `eco_organization_members` | `eco_audit_events` &rarr; `USER_ACTIVE_CHANGED` (Scoped to `v_target_org_id`) |
| `public.set_global_user_active` | **GLOBAL_PROFILE** | `GLOBAL_USER_MANAGE` or `PLATFORM_MANAGE` (Platform) | `eco_user_profiles` | `eco_platform_audit_events` &rarr; `GLOBAL_USER_ACTIVE_CHANGED` |
| `public.switch_superadmin_org_context` | **PLATFORM_CONTEXT_SWITCH** | `SUPPORT_IMPERSONATE` or `ACCESS_ANY_ORG` (Platform) | `eco_user_active_context` & `eco_user_profiles` | `eco_platform_audit_events` &rarr; `SUPERADMIN_ORG_CONTEXT_SWITCHED` |

---

## 4. Detailed Component Specifications

### 4.1 RPC: `public.change_user_role`
- **Signature**: `public.change_user_role(target_user_id UUID, new_role TEXT, p_org_id UUID DEFAULT NULL) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_PERMISSION_MANAGE` (Scope: `ORGANIZATION`)
- **Inactive Membership Policy**: ALLOWED. Authorized admin can configure `role_template_id` on an inactive membership before reactivation; `is_active` remains `FALSE`.

### 4.2 RPC: `public.set_user_active` (Tenant Membership Only)
- **Signature**: `public.set_user_active(target_user_id UUID, new_active BOOLEAN, p_org_id UUID DEFAULT NULL) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_MANAGE` (Scope: `ORGANIZATION`)
- **Action**: Mutates only `eco_organization_members.is_active`. Never mutates `eco_user_profiles.is_active`. Emits tenant audit to `eco_audit_events`.

### 4.3 RPC: `public.set_global_user_active` (Global Profile Only)
- **Signature**: `public.set_global_user_active(target_user_id UUID, new_active BOOLEAN) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `GLOBAL_USER_MANAGE` or `PLATFORM_MANAGE` (Scope: `PLATFORM`)
- **Action**: Mutates only `eco_user_profiles.is_active`. Emits platform audit to `eco_platform_audit_events` with metadata `{"new_active": ..., "previous_active": ...}`. Zero dependence on active tenant context.

### 4.4 RPC: `public.switch_superadmin_org_context`
- **Signature**: `public.switch_superadmin_org_context(p_org_id UUID) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `SUPPORT_IMPERSONATE` or `ACCESS_ANY_ORG` (Scope: `PLATFORM`)
- **Action**: Updates `eco_user_profiles.organization_id` and `eco_user_active_context`. Emits platform audit to `eco_platform_audit_events` with metadata `{"target_organization_id": ...}`.

---

## 5. RLS Policy Specifications

- **`eco_organizations`**: Set-based `USING (id IN (SELECT private.authorized_orgs_for_capability('ORG_VIEW')))`.
- **`eco_user_profiles`**: Self-access (`auth_user_id = auth.uid() AND is_active = TRUE`) + canonical member visibility via `EXISTS (SELECT 1 FROM eco_organization_members m WHERE m.user_profile_id = eco_user_profiles.id AND m.is_active = TRUE AND m.organization_id IN (SELECT private.authorized_orgs_for_capability('ORG_MEMBER_VIEW')))`.
- **`eco_audit_events`**: Set-based `USING (organization_id IN (SELECT private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')))`.
- **`eco_platform_audit_events`**: Platform-based `USING (private.can_platform('AUDIT_PLATFORM_VIEW') OR private.can_platform('PLATFORM_MANAGE'))`.

---

## 6. Rollback Boundary

Migration `022_identity_and_org_admin_down.sql` drops `eco_platform_audit_events`, drops `set_global_user_active`, and cleanly restores pre-M022 definitions and legacy RLS policies without touching M019, M020, or M021.
