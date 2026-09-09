# MICA Authorization Primitives Safety & Design Audit (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: COMPLETED & VERIFIED  
> **Baseline Commit**: `a96cc5a0a07190f1c1f61b4c9255b56dfb4f2dfc`  
> **Scope**: Structural, security, volatility, and non-recursion analysis of core authorization helpers.

---

## 1. Helper Primitives Detailed Inspection

### 1. `private.current_profile_id()`
- **Signature**: `private.current_profile_id() RETURNS UUID`
- **Owner**: `postgres`
- **Security Mode**: `SECURITY DEFINER`
- **Search Path**: `SET search_path = ''` (Immutable empty search path prevents hijack)
- **Volatility**: `STABLE` (Cached across identical calls within a statement)
- **Parallel Safety**: `PARALLEL SAFE`
- **Session Dependency**: Derives caller identity from `auth.uid()` / `auth.jwt()->>'sub'`.
- **Tables Queried**: `public.eco_user_profiles` (`auth_user_id = v_auth_id AND is_active = TRUE`)
- **RLS Behavior**: Bypasses RLS on `eco_user_profiles` to safely locate caller profile across tenants.
- **Fail-Closed Outcome**: Returns `NULL` if profile is inactive, absent, or unauthenticated.

### 2. `private.active_org_id()`
- **Signature**: `private.active_org_id() RETURNS UUID`
- **Owner**: `postgres`
- **Security Mode**: `SECURITY DEFINER`
- **Search Path**: `SET search_path = ''`
- **Volatility**: `STABLE`
- **Parallel Safety**: `PARALLEL SAFE`
- **Session Dependency**: `private.current_profile_id()`
- **Tables Queried**: `public.eco_user_active_context`
- **RLS Behavior**: Bypasses RLS on active context table.
- **Fail-Closed Outcome**: Returns `NULL` if no active context is selected or caller profile is missing.

### 3. `private.can_platform(p_capability_code TEXT)`
- **Signature**: `private.can_platform(p_capability_code TEXT) RETURNS BOOLEAN`
- **Owner**: `postgres`
- **Security Mode**: `SECURITY DEFINER`
- **Search Path**: `SET search_path = ''`
- **Volatility**: `STABLE`
- **Parallel Safety**: `PARALLEL SAFE`
- **Tables Queried**: `public.eco_capabilities`, `public.eco_user_platform_role`, `public.eco_role_templates`, `public.eco_role_template_capabilities`, `public.eco_user_platform_capability_overrides`.
- **Evaluation Order**:
  1. Validate active caller profile.
  2. Validate capability exists (`scope = 'PLATFORM'`, `is_active = TRUE`).
  3. Validate active `eco_user_platform_role` & active `PLATFORM` template.
  4. Evaluate base template grant in `eco_role_template_capabilities`.
  5. Check user-specific override in `eco_user_platform_capability_overrides`.
  6. Explicit `DENY` override returns `FALSE`.
  7. Explicit `ALLOW` override returns `TRUE`.
  8. Otherwise return base template grant result.
- **Fail-Closed Outcome**: Returns `FALSE` on null inputs, inactive profile, inactive capability, missing platform role, or explicit DENY.

### 4. `private.can_org(p_org_id UUID, p_capability_code TEXT)`
- **Signature**: `private.can_org(p_org_id UUID, p_capability_code TEXT) RETURNS BOOLEAN`
- **Owner**: `postgres`
- **Security Mode**: `SECURITY DEFINER`
- **Search Path**: `SET search_path = ''`
- **Volatility**: `STABLE`
- **Parallel Safety**: `PARALLEL SAFE`
- **Tables Queried**: `public.eco_organizations`, `public.eco_organization_members`, `public.eco_capabilities`, `public.eco_role_template_capabilities`, `public.eco_role_templates`, `public.eco_user_platform_role`, `public.eco_platform_role_org_capabilities`, `public.eco_membership_capability_overrides`.
- **Evaluation Order**:
  1. Validate active caller profile.
  2. Validate target organization exists in `public.eco_organizations`.
  3. Validate active membership exists in `public.eco_organization_members` for caller + target org.
  4. Validate capability exists (`scope = 'ORGANIZATION'`, `is_active = TRUE`).
  5. Evaluate membership base template grant (if `role_template_id` present).
  6. Evaluate platform-role organization bridge grant (via `eco_platform_role_org_capabilities` if user has active platform role).
  7. Combine base grants: `v_has_base := (v_has_base_template OR v_has_base_platform_bridge)`.
  8. Evaluate membership-specific override in `eco_membership_capability_overrides`.
  9. Explicit `DENY` override returns `FALSE`.
  10. Explicit `ALLOW` override returns `TRUE`.
  11. Otherwise return `v_has_base`.
- **Fail-Closed Outcome**: Returns `FALSE` on null parameters, inactive profile, non-existent organization, missing membership, inactive capability, missing base grant, or explicit DENY.

---

## 2. RLS Non-Recursion & Security Definer Safety

- **Recursion Assessment**: `RLS_RECURSION_DETECTED: NO`.
  None of the authorization schema tables (`eco_capabilities`, `eco_role_templates`, `eco_organization_members`, etc.) utilize RLS policies that invoke `can_org` or `can_platform`. Since the functions execute with `SECURITY DEFINER` privileges, internal lookups bypass table-level RLS safely without recursion.
- **Security Definer Data Leak Risk**: Primitives return strictly `BOOLEAN` (or UUID identifier). They expose zero table rows or client-accessible entity payloads, mitigating general data bypass risks.

---

## 3. Covering Indexes in Migration 021

To eliminate sequential scans and enable Index-Only Scans during repeated evaluations:
1. `idx_eco_org_members_covering` on `public.eco_organization_members (organization_id, user_profile_id, is_active, role_template_id)`
2. `idx_eco_user_platform_role_covering` on `public.eco_user_platform_role (user_profile_id, is_active, role_template_id)`
