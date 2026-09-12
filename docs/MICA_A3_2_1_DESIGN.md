# MICA Authorization Design Specification: Identity, Profiles & Org Admin (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: DESIGN FROZEN & UPDATED (GLOBAL VS TENANT STATE SEPARATION & MULTI-ORG RESOLUTION)  
> **Baseline Commit**: `fab6e49633228d10b86e0439db879f32c57e6b97`  
> **Target Schema Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  

---

## 1. Executive Summary & Core Architectural Principles

WP-A3.2.1 executes the **first vertical authorization cutover** in MICA, transitioning Identity, User Profiles, Member Administration, and Organization-Scoped Audit Visibility from legacy role-string authorization (`private.func_role() = 'ADMIN'` / `private.org_id()`) to the frozen M019/M021 capability foundation.

### Three Fundamental Invariants:
1. **ACTIVE CONTEXT != AUTHORIZATION**:
   - `private.active_org_id()` is an operation selector for tenant actions when `p_org_id` is omitted. It is **never** an authorization grant or blocker for global platform capabilities.
2. **GLOBAL PROFILE STATE vs TENANT MEMBERSHIP STATE SEPARATION**:
   - Platform account activation (`eco_user_profiles.is_active`) and Tenant membership activation (`eco_organization_members.is_active`) are distinct scopes governed by separate explicit RPCs.
3. **`eco_user_profiles.organization_id` & `eco_user_profiles.role` ARE NON-AUTHORITATIVE**:
   - Canonical tenant authority, membership roles, and organization-scoped active states reside **exclusively in `public.eco_organization_members`**.
   - `eco_user_profiles.role` is synchronized purely as a lossy compatibility artifact for frontend session display (`src/js/ui.js`); **zero** backend authorization paths evaluate it.

---

## 2. Operation Scopes & RPC Design

### 2.1 Operation Scope Table

| RPC Function | Operation Scope | Required Capability | Primary Target Entity | State Mutated |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | **ORGANIZATION_MEMBERSHIP** (with legacy profile wrapper sync) | `ORG_MEMBER_PERMISSION_MANAGE` (Org) | `eco_organization_members` | Mutates `role_template_id` on the target user's membership in the authorized org. Syncs `eco_user_profiles.role` for legacy UI compatibility only. |
| `public.set_user_active` | **ORGANIZATION_MEMBERSHIP** | `ORG_MEMBER_MANAGE` (Org) | `eco_organization_members` | Mutates `eco_organization_members.is_active` in the resolved target organization. **Never** mutates `eco_user_profiles.is_active`. |
| `public.set_global_user_active` | **GLOBAL_PROFILE** | `GLOBAL_USER_MANAGE` or `PLATFORM_MANAGE` (Platform) | `eco_user_profiles` | Mutates `eco_user_profiles.is_active`. Has zero dependence on `active_org_id()` and **never** mutates tenant memberships. |
| `public.switch_superadmin_org_context` | **PLATFORM_CONTEXT_SWITCH** | `SUPPORT_IMPERSONATE` or `ACCESS_ANY_ORG` (Platform) | `eco_user_active_context` & `eco_user_profiles` | Upserts `eco_user_active_context` and updates `eco_user_profiles.organization_id` to maintain UI session compatibility until WP-A3.3. |

---

## 3. Detailed Component Specifications

### 3.1 RPC: `public.change_user_role`
- **Signature**: `public.change_user_role(target_user_id UUID, new_role TEXT, p_org_id UUID DEFAULT NULL) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_PERMISSION_MANAGE` (Scope: `ORGANIZATION`)
- **Execution Flow**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `UNAUTHORIZED`.
  2. Self-protection: `IF target_user_id = v_caller_id THEN RAISE EXCEPTION 'SELF_ROLE_CHANGE_NOT_ALLOWED'; END IF;`.
  3. Validate role string and map to `eco_role_templates.code`:
     - `'ADMIN'` &rarr; `TENANT_ADMIN`
     - `'ACCOUNTANT'` &rarr; `ACCOUNTANT`
     - `'UPLOADER'` &rarr; `UPLOADER`
     - `'REVIEWER'` &rarr; `REVIEWER`
     - `'USER'` / `'READ_ONLY'` &rarr; `READ_ONLY`
  4. Deterministic target org resolution:
     - If `p_org_id` provided &rarr; target org = `p_org_id`.
     - Else if `private.active_org_id()` matches a target membership &rarr; target org = `active_org_id()`.
     - Else query target's memberships where caller has `ORG_MEMBER_PERMISSION_MANAGE`: if 1 &rarr; unique org; if > 1 &rarr; `AMBIGUOUS_ORGANIZATION_CONTEXT`; if 0 &rarr; `TARGET_NOT_FOUND`.
  5. Enforce capability: `IF NOT private.can_org(v_target_org_id, 'ORG_MEMBER_PERMISSION_MANAGE') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`.
  6. Update `public.eco_organization_members SET role_template_id = v_new_tpl_id WHERE organization_id = v_target_org_id AND user_profile_id = target_user_id;`.
  7. Update legacy `eco_user_profiles.role = new_role` for display compatibility only.
  8. Write audit event to `public.eco_audit_events`.

### 3.2 RPC: `public.set_user_active` (Tenant Membership Only)
- **Signature**: `public.set_user_active(target_user_id UUID, new_active BOOLEAN, p_org_id UUID DEFAULT NULL) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_MANAGE` (Scope: `ORGANIZATION`)
- **Execution Flow**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `UNAUTHORIZED`.
  2. Self-protection: `IF target_user_id = v_caller_id AND new_active = FALSE THEN RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED'; END IF;`.
  3. Deterministic target org resolution (explicit `p_org_id`, `active_org_id()`, or unique authorized membership).
  4. Enforce `private.can_org(v_target_org_id, 'ORG_MEMBER_MANAGE')`. If FALSE &rarr; `FORBIDDEN`.
  5. Update `public.eco_organization_members SET is_active = new_active WHERE organization_id = v_target_org_id AND user_profile_id = target_user_id;`.
  6. Write tenant-scoped audit event.

### 3.3 RPC: `public.set_global_user_active` (Global Profile Only)
- **Signature**: `public.set_global_user_active(target_user_id UUID, new_active BOOLEAN) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `GLOBAL_USER_MANAGE` or `PLATFORM_MANAGE` (Scope: `PLATFORM`)
- **Execution Flow**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `UNAUTHORIZED`.
  2. Verify platform capability: `IF NOT (private.can_platform('GLOBAL_USER_MANAGE') OR private.can_platform('PLATFORM_MANAGE')) THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`.
  3. Self-protection: `IF target_user_id = v_caller_id AND new_active = FALSE THEN RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED'; END IF;`.
  4. Verify target exists in `eco_user_profiles`. If not &rarr; `TARGET_NOT_FOUND`.
  5. Update `public.eco_user_profiles SET is_active = new_active WHERE id = target_user_id;`.
  6. Write audit event (`organization_id = NULL`).

### 3.4 RPC: `public.switch_superadmin_org_context`
- **Signature**: `public.switch_superadmin_org_context(p_org_id UUID) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `SUPPORT_IMPERSONATE` or `ACCESS_ANY_ORG` (Scope: `PLATFORM`)
- **Execution Flow**:
  1. Enforce `private.can_platform('SUPPORT_IMPERSONATE') OR private.can_platform('ACCESS_ANY_ORG')`.
  2. If `p_org_id IS NOT NULL`, verify existence in `eco_organizations`.
  3. Update `eco_user_profiles.organization_id = p_org_id` and upsert `eco_user_active_context`.
  4. Write audit event if `p_org_id IS NOT NULL`.

---

## 4. RLS Policy Specifications

- **`eco_organizations`**: Set-based `USING (id IN (SELECT private.authorized_orgs_for_capability('ORG_VIEW')))`.
- **`eco_user_profiles`**: Self-access (`auth_user_id = auth.uid() AND is_active = TRUE`) + canonical member visibility via `EXISTS (SELECT 1 FROM eco_organization_members m WHERE m.user_profile_id = eco_user_profiles.id AND m.is_active = TRUE AND m.organization_id IN (SELECT private.authorized_orgs_for_capability('ORG_MEMBER_VIEW')))`.
- **`eco_audit_events`**: Set-based `USING (organization_id IN (SELECT private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')))`.

---

## 5. Rollback Boundary

Migration `022_identity_and_org_admin_down.sql` drops `set_global_user_active` and the 3-argument/default parameter functions, cleanly restoring pre-M022 2-parameter definitions and legacy RLS policies without touching M019, M020, or M021.
