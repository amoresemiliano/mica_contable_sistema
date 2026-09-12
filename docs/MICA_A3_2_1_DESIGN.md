# MICA Authorization Design Specification: Identity, Profiles & Org Admin (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: DESIGN FROZEN / READY FOR IMPLEMENTATION  
> **Baseline Commit**: `e2f9c5baed420d0d1b1e98f2fc260f36505dc6f8`  
> **Target Schema Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  

---

## 1. Executive Summary & Scope Boundary

WP-A3.2.1 executes the **first vertical authorization cutover** in MICA, transitioning Identity, User Profiles, Member Administration, and Organization-Scoped Audit Visibility from legacy role-string authorization (`private.func_role() = 'ADMIN'` / `private.org_id()`) to the frozen M019/M021 capability foundation.

### Surfaces Cut Over in WP-A3.2.1:
1. **RPC Functions**:
   - `public.change_user_role(target_user_id UUID, new_role TEXT)` &rarr; Governed by `ORG_MEMBER_PERMISSION_MANAGE`.
   - `public.set_user_active(target_user_id UUID, new_active BOOLEAN)` &rarr; Governed by `ORG_MEMBER_MANAGE`.
   - `public.switch_superadmin_org_context(p_org_id UUID)` &rarr; Governed by `SUPPORT_IMPERSONATE` / `ACCESS_ANY_ORG`.
2. **RLS Policies**:
   - `public.eco_organizations` ("Organizations viewable by own users") &rarr; Governed by `ORG_VIEW` via set-based `private.authorized_orgs_for_capability('ORG_VIEW')`.
   - `public.eco_user_profiles` ("Profiles viewable by user and admin") &rarr; Governed by canonical self-identity (`auth_user_id = auth.uid() AND is_active = TRUE`) and member admin visibility via canonical active memberships in `eco_organization_members` for orgs with `ORG_MEMBER_VIEW`.
   - `public.eco_audit_events` ("Audit events viewable by admin") &rarr; Governed by `AUDIT_VIEW_ORG` via set-based `private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')`.
3. **Trigger Invariant**:
   - `enforce_append_only_audit` on `public.eco_audit_events` is strictly preserved unchanged.

---

## 2. Canonical Identity & Multi-Org Profile Resolution

### 2.1 Canonical Self-Identity Source
- **Supabase Native Identity**: The canonical identity anchor is `auth.users.id` matched to `public.eco_user_profiles.auth_user_id`.
- **Legacy `firebase_uid`**: Removed in Migration 009. The codebase uses `auth_user_id = auth.uid()` exclusively. No legacy Firebase UID references are reintroduced.
- **Fail-Closed State**: Self-profile queries strictly require `is_active = TRUE`. Inactive profiles cannot self-authorize.

### 2.2 Canonical Multi-Org Membership vs Legacy `profile.organization_id`
- **Legacy Artifact**: `eco_user_profiles.organization_id` was a single-tenant scalar reference.
- **Canonical Multi-Org Model**: Tenant authorization authority resides exclusively in `public.eco_organization_members` (linking `user_profile_id` to `organization_id`, `role_template_id`, and `is_active = TRUE`).
- **Resolution**:
  - In `eco_user_profiles` RLS, admin visibility is evaluated by joining `eco_organization_members` against the set of organizations where the caller possesses `ORG_MEMBER_VIEW`.
  - A stale or modified `profile.organization_id` column never confers authority, never leaks visibility across tenant boundaries, and is never used as the sole source of membership authority.

---

## 3. Detailed Component Specifications

### 3.1 RPC: `public.change_user_role`
- **Signature**: `public.change_user_role(target_user_id UUID, new_role TEXT) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_PERMISSION_MANAGE` (Scope: `ORGANIZATION`)
- **Execution Logic**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `RAISE EXCEPTION 'UNAUTHORIZED'`.
  2. Prevent self-role modification: `IF target_user_id = v_caller_id THEN RAISE EXCEPTION 'SELF_ROLE_CHANGE_NOT_ALLOWED'; END IF;`.
  3. Validate role string parameter: `IF new_role NOT IN ('USER', 'UPLOADER', 'REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'INVALID_ROLE'; END IF;`.
  4. Lookup target profile: `SELECT organization_id INTO v_target_org_id FROM public.eco_user_profiles WHERE id = target_user_id AND is_active = TRUE;`. If NOT FOUND &rarr; `RAISE EXCEPTION 'TARGET_NOT_FOUND'`.
  5. Enforce Capability: `IF NOT private.can_org(v_target_org_id, 'ORG_MEMBER_PERMISSION_MANAGE') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`.
  6. Execute atomic update: `UPDATE public.eco_user_profiles SET role = new_role WHERE id = target_user_id AND organization_id = v_target_org_id AND is_active = TRUE;`.
  7. Audit event: `INSERT INTO public.eco_audit_events (organization_id, event_type) VALUES (v_target_org_id, 'USER_ROLE_CHANGED');`.

### 3.2 RPC: `public.set_user_active`
- **Signature**: `public.set_user_active(target_user_id UUID, new_active BOOLEAN) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability**: `ORG_MEMBER_MANAGE` (Scope: `ORGANIZATION`)
- **Execution Logic**:
  1. Resolve caller profile ID via `private.current_profile_id()`. If NULL &rarr; `RAISE EXCEPTION 'UNAUTHORIZED'`.
  2. Prevent self-deactivation: `IF target_user_id = v_caller_id AND new_active = FALSE THEN RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED'; END IF;`.
  3. Lookup target profile: `SELECT is_active, organization_id INTO v_current_state, v_target_org_id FROM public.eco_user_profiles WHERE id = target_user_id;`. If NOT FOUND &rarr; `RAISE EXCEPTION 'TARGET_NOT_FOUND'`.
  4. Enforce Capability: `IF v_target_org_id IS NULL OR NOT private.can_org(v_target_org_id, 'ORG_MEMBER_MANAGE') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;`.
  5. Idempotent short-circuit: `IF v_current_state = new_active THEN RETURN; END IF;`.
  6. Execute atomic update: `UPDATE public.eco_user_profiles SET is_active = new_active WHERE id = target_user_id;`.
  7. Audit event: `INSERT INTO public.eco_audit_events (organization_id, event_type) VALUES (v_target_org_id, 'USER_ACTIVE_CHANGED');`.

### 3.3 RPC: `public.switch_superadmin_org_context`
- **Signature**: `public.switch_superadmin_org_context(p_org_id UUID) RETURNS VOID`
- **Security**: `SECURITY DEFINER`, `SET search_path = ''`
- **Capability Semantic Analysis**:
  - This operation allows an administrative actor to switch operational UI context across arbitrary tenant organizations.
  - Governing Capabilities: `SUPPORT_IMPERSONATE` or `ACCESS_ANY_ORG` (Scope: `PLATFORM`).
  - Standard tenant administrators, accountants, uploaders, and unauthorized users evaluate to `FALSE` for platform capabilities.
- **Execution Logic**:
  1. Enforce Platform Capability: `IF NOT (private.can_platform('SUPPORT_IMPERSONATE') OR private.can_platform('ACCESS_ANY_ORG')) THEN RAISE EXCEPTION 'Unauthorized: Only SUPERADMIN can switch organization context'; END IF;`.
  2. If `p_org_id IS NOT NULL`, verify organization existence: `IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id) THEN RAISE EXCEPTION 'Invalid organization ID'; END IF;`.
  3. Resolve caller profile ID: `SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;`. If NULL &rarr; `RAISE EXCEPTION 'User profile not found or inactive';`.
  4. Update legacy profile column for frontend compatibility: `UPDATE public.eco_user_profiles SET organization_id = p_org_id WHERE id = v_caller_id;`.
  5. Upsert active context:
     ```sql
     INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
     VALUES (v_caller_id, p_org_id, now())
     ON CONFLICT (user_profile_id)
     DO UPDATE SET organization_id = EXCLUDED.organization_id, updated_at = now();
     ```
  6. Audit event: If `p_org_id IS NOT NULL`, write audit entry `(p_org_id, 'SUPERADMIN_ORG_CONTEXT_SWITCHED')`.

---

## 4. RLS Policy Specifications

### 4.1 Table: `public.eco_organizations`
- **Policy Name**: `"Organizations viewable by own users"`
- **Command**: `FOR SELECT TO authenticated`
- **Predicate**:
  ```sql
  USING (
    id IN (
      SELECT private.authorized_orgs_for_capability('ORG_VIEW')
    )
  )
  ```
- **Rationale**: Uses set-based resolution. Allows planner to filter organizations efficiently while guaranteeing that users only see organizations where they have active membership and `ORG_VIEW` (or accounting bridge).

### 4.2 Table: `public.eco_user_profiles`
- **Policy Name**: `"Profiles viewable by user and admin"`
- **Command**: `FOR SELECT TO authenticated`
- **Predicate**:
  ```sql
  USING (
    (
      auth_user_id = auth.uid()
      AND is_active = TRUE
    )
    OR
    EXISTS (
      SELECT 1
      FROM public.eco_organization_members m
      WHERE m.user_profile_id = eco_user_profiles.id
        AND m.is_active = TRUE
        AND m.organization_id IN (
          SELECT private.authorized_orgs_for_capability('ORG_MEMBER_VIEW')
        )
    )
  )
  ```
- **Rationale**:
  - Self-read is guaranteed for active users via `auth.uid()`.
  - Administrative member visibility is strictly resolved through canonical active memberships in `eco_organization_members` for organizations where caller holds `ORG_MEMBER_VIEW`.
  - Prevents cross-tenant profile exposure even if legacy `organization_id` is mismatched.

### 4.3 Table: `public.eco_audit_events`
- **Policy Name**: `"Audit events viewable by admin"`
- **Command**: `FOR SELECT TO authenticated`
- **Predicate**:
  ```sql
  USING (
    organization_id IN (
      SELECT private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')
    )
  )
  ```
- **Rationale**: High-volume append-only audit table. Enforces set-based capability join pattern (Pattern B/C), completely avoiding per-row function evaluation overhead.

---

## 5. Rollback Boundary & Downgrade Path

Migration `022_identity_and_org_admin_down.sql` reverts all modified RPCs and RLS policies to their exact pre-M022 state (from M009 and M017):
- `public.change_user_role` &rarr; Reverts to `private.func_role() <> 'ADMIN'` check.
- `public.set_user_active` &rarr; Reverts to `private.func_role() <> 'ADMIN'` check.
- `public.switch_superadmin_org_context` &rarr; Reverts to `private.func_role() != 'SUPERADMIN'` check.
- `eco_organizations` RLS &rarr; Reverts to `USING (id = private.org_id())`.
- `eco_user_profiles` RLS &rarr; Reverts to `USING ((auth_user_id = auth.uid() AND is_active = TRUE) OR (private.func_role() = 'ADMIN' AND organization_id = private.org_id()))`.
- `eco_audit_events` RLS &rarr; Reverts to `USING (organization_id = private.org_id() AND private.func_role() = 'ADMIN')`.
- All M019, M020, and M021 foundation structures remain completely intact during rollback.
