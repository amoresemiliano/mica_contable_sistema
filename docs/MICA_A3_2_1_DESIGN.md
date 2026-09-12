# MICA Authorization Design Specification: Identity, Profiles & Org Admin (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: DESIGN FROZEN & UPDATED (MULTI-ORG TARGET RESOLUTION)  
> **Baseline Commit**: `e2f9c5baed420d0d1b1e98f2fc260f36505dc6f8`  
> **Target Schema Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  

---

## 1. Executive Summary & Core Architectural Principle

WP-A3.2.1 executes the **first vertical authorization cutover** in MICA, transitioning Identity, User Profiles, Member Administration, and Organization-Scoped Audit Visibility from legacy role-string authorization (`private.func_role() = 'ADMIN'` / `private.org_id()`) to the frozen M019/M021 capability foundation.

### Fundamental Tenancy Invariant:
> **`eco_user_profiles.organization_id` IS LEGACY AND NON-AUTHORITATIVE.**  
> Canonical tenant authority, membership roles, and organization-scoped active states reside **exclusively in `public.eco_organization_members`**.  
> Under no circumstances does `eco_user_profiles.organization_id` confer authorization, select target permissions, or restrict administrative actions.

---

## 2. Operation Scope & Multi-Org Target Resolution

### 2.1 Operation Scope Analysis

| RPC Function | Operation Scope | Primary Target Entity | Mutation Target |
| :--- | :--- | :--- | :--- |
| `public.change_user_role` | **ORGANIZATION_MEMBERSHIP** (with legacy profile wrapper sync) | `eco_organization_members` | Mutates `role_template_id` on the target user's membership in the authorized organization. Syncs `eco_user_profiles.role` for legacy session readers. |
| `public.set_user_active` | **ORGANIZATION_MEMBERSHIP** (Tenant Admin) / **GLOBAL_PROFILE** (Platform Admin) | `eco_organization_members` / `eco_user_profiles` | For tenant admins holding `ORG_MEMBER_MANAGE`, mutates `eco_organization_members.is_active` in that organization. For platform superadmins holding `GLOBAL_USER_MANAGE`, mutates `eco_user_profiles.is_active`. |
| `public.switch_superadmin_org_context` | **PLATFORM_CONTEXT_SWITCH** | `eco_user_active_context` & `eco_user_profiles` | Upserts `eco_user_active_context` and updates `eco_user_profiles.organization_id` to maintain UI session compatibility until WP-A3.3. |

### 2.2 Deterministic Target Organization Resolution Algorithm

When `change_user_role` or `set_user_active` is called without an explicit organization parameter:

```
[START: Target Org Resolution]
  |
  +--> 1. Was `p_org_id` explicitly supplied by the caller?
  |      YES: Target Org = `p_org_id`.
  |
  +--> 2. Is `private.active_org_id()` set AND does the target user have a membership in that org?
  |      YES: Target Org = `active_org_id()`.
  |
  +--> 3. Query `eco_organization_members` for target user where caller holds required capability:
  |      - If COUNT = 1: Target Org = that unique organization.
  |      - If COUNT > 1: RAISE EXCEPTION 'AMBIGUOUS_ORGANIZATION_CONTEXT' (Fail-Closed).
  |      - If COUNT = 0: Target Org = NULL -> RAISE EXCEPTION 'TARGET_NOT_FOUND'.
  |
  +--> 4. Enforce `private.can_org(Target Org, Capability)`. If FALSE -> RAISE EXCEPTION 'FORBIDDEN'.
```

This ensures:
1. Stale `profile.organization_id` has **zero** effect on authorization.
2. A multi-org user can be managed in Org A by Admin A without Admin A needing authority in Org B.
3. Ambiguity in multi-tenant contexts is never guessed; it fails closed unless explicitly scoped.

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
  4. Resolve target organization via Deterministic Resolution Algorithm.
  5. Enforce capability: `IF NOT private.can_org(v_target_org_id, 'ORG_MEMBER_PERMISSION_MANAGE') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`.
  6. Update `public.eco_organization_members SET role_template_id = v_new_tpl_id WHERE organization_id = v_target_org_id AND user_profile_id = target_user_id;`.
  7. Maintain legacy `eco_user_profiles.role = new_role` for session compatibility.
  8. Write audit event to `public.eco_audit_events`.

### 3.2 RPC: `public.set_user_active`
- **Signature**: `public.set_user_active(target_user_id UUID, new_active BOOLEAN, p_org_id UUID DEFAULT NULL) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_MANAGE` (Tenant level) / `GLOBAL_USER_MANAGE` (Platform level)
- **Execution Flow**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `UNAUTHORIZED`.
  2. Self-protection: `IF target_user_id = v_caller_id AND new_active = FALSE THEN RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED'; END IF;`.
  3. Resolve target organization via Deterministic Resolution Algorithm.
  4. If target organization resolved:
     - Enforce `private.can_org(v_target_org_id, 'ORG_MEMBER_MANAGE')`. If FALSE &rarr; `FORBIDDEN`.
     - Update `public.eco_organization_members SET is_active = new_active WHERE organization_id = v_target_org_id AND user_profile_id = target_user_id;`.
     - Write audit event.
  5. If no tenant organization matched, check if caller is Platform Superadmin (`GLOBAL_USER_MANAGE` / `PLATFORM_MANAGE`):
     - Update `public.eco_user_profiles SET is_active = new_active WHERE id = target_user_id;`.
     - Return cleanly.

### 3.3 RPC: `public.switch_superadmin_org_context`
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

Migration `022_identity_and_org_admin_down.sql` drops the 3-argument/default parameter functions and cleanly restores pre-M022 2-parameter definitions and legacy RLS policies without touching M019, M020, or M021.
