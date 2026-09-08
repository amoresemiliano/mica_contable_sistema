# MICA Authorization Compatibility Contract (WP-A3.1)

> **Document Status**: DISCOVERY COMPLETE & FROZEN  
> **Baseline Commit**: `7aae65c9029822d120339670b962b596bae94cd7`  
> **Purpose**: Governance rules, invariants, and authorization freeze contract for WP-A3 phase.

---

## 1. Frozen Authorization Invariants

### Invariant I: ACTIVE CONTEXT IS NOT AUTHORIZATION
- Active context (`private.active_org_id()` / `eco_user_active_context.organization_id` / frontend `activeOrganizationId`) represents the user's currently selected UI context ONLY.
- Active context **NEVER** grants authority to read, write, update, delete, or perform actions on any organization resource.
- Authorization MUST ALWAYS follow the explicit evaluation path:
  $$\text{Target Resource / Org ID} \longrightarrow \text{Active Org Membership} \longrightarrow \text{Capability Evaluation} \longrightarrow \text{Scoped Execution}$$
- `PLATFORM_SUPERADMIN` role or active context selection DOES NOT bypass the requirement for active organization membership during `private.can_org(...)` evaluation.

### Invariant II: ZERO AMBIGUOUS MIXED AUTHORITY
- During phased vertical cutovers in WP-A3.2, any given database function, RPC, or RLS policy is strictly operating under either `LEGACY_AUTH` or `CAPABILITY_AUTH`.
- Permanent dual-evaluation (`legacy_check OR capability_check`) is **EXPLICITLY FORBIDDEN**.
- Temporary fallback logic, if required for a controlled migration step, MUST be:
  1. Explicitly documented in the WP specification.
  2. Time-bounded to that single WP iteration.
  3. Reversible and purged before closing the WP.

### Invariant III: ROLES ARE TEMPLATES, NOT RUNTIME AUTHORITY
- Role codes (`PLATFORM_SUPERADMIN`, `ACCOUNTING_SUPERADMIN`, `TENANT_ADMIN`, `ACCOUNTANT`, `UPLOADER`, `REVIEWER`, `READ_ONLY`) serve purely as administrative presets/groupings of capabilities.
- Runtime enforcement routines (`private.can_platform` and `private.can_org`) evaluate individual fine-grained capability codes (`IMPORT_CREATE`, `RECORD_CLASSIFY`, etc.), NOT role string literals.

---

## 2. Authorization Change Freeze Contract

To prevent legacy state (`eco_user_profiles.role`, `eco_user_profiles.organization_id`) and M019 capability shadow state (`eco_user_platform_role`, `eco_organization_members`, `eco_role_template_capabilities`) from diverging during phased vertical cutovers, the following **AUTHORIZATION CHANGE FREEZE** is enacted:

```
+-----------------------------------------------------------------------------------+
|                        AUTHORIZATION CHANGE FREEZE CONTRACT                       |
+-----------------------------------------------------------------------------------+
| FREEZE START CONDITION: Execution of WP-A3.2.0 in DEV/Staging database.           |
| FREEZE END CONDITION: Complete closing of WP-A3.2.x (Legacy Deprecation).         |
+-----------------------------------------------------------------------------------+
```

### Prohibited Actions During Freeze
Except through controlled WP migration scripts, no user or script may perform:
1. Manual SQL updates to `public.eco_user_profiles.role` or `organization_id`.
2. Manual RPC calls to `public.change_user_role` or `public.set_user_active`.
3. Manual insertion/deletion of `public.eco_organization_members` or `public.eco_user_platform_role` rows.
4. Direct mutation of `public.eco_role_template_capabilities` or `public.eco_capabilities`.

### Permitted Controlled Exceptions
- Automated WP-A3.2 migration scripts executing via version-controlled SQL files.
- Re-running deterministic preflight and postcheck validation scripts.

### Unauthorized State Mutation Recovery Procedure
If unauthorized state mutation or divergence between legacy fields and capability assignments is detected:
1. **STOP**: Immediately freeze all WP-A3.2 migration steps.
2. **AUDIT**: Execute `sql/020_postcheck.sql` and `tests/db/020_real_user_authorization.sql` to identify broken invariants.
3. **REVERT**: Run targeted rollback scripts (`sql/020_real_user_authorization_down.sql`) to restore known baseline state.
4. **RE-VERIFY**: Execute full test suite (`npm test`) before resuming execution.

---

## 3. Target Organization Resolution Matrix

For all target authorization checks in WP-A3.2, the target organization ID must be derived deterministically according to resource ownership:

| Resource Type | Target Organization Resolution Rule | Prohibited Pattern |
| :--- | :--- | :--- |
| **Existing Resource** (Record, Issue, File, Movement) | `resource.organization_id` derived directly from database row | Passing client-supplied org ID or using `private.org_id()` without checking row ownership |
| **New Resource** (New Import Batch, New Record) | Server-validated target tenant ID passed to RPC, verified against caller membership | Accepting unverified client tenant ID or assuming `private.active_org_id()` |
| **Client-Supplied Org Input** | `p_target_org_id` passed to RPC MUST be explicitly checked via `private.can_org(p_target_org_id, cap)` | Unchecked usage of `p_target_org_id` in SQL statements |
| **Multi-Organization Query / Report** | Explicit array of requested org IDs $\cap$ Explicit array of authorized org IDs from active memberships | Implicit `SELECT *` without scoping to caller's authorized tenant set |
