# MICA Authorization Risk Register (WP-A3.1)

> **Document Status**: DISCOVERY COMPLETE & FROZEN  
> **Baseline Commit**: `7aae65c9029822d120339670b962b596bae94cd7`  
> **Scope**: Comprehensive risk classification covering Security Definer functions, RLS performance, storage, client inputs, and frontend stale UI state.

---

## 1. Security Definer Function Risk Audit

All 32 SECURITY DEFINER functions in the repository have been audited against security best practices:

| Function Name | Owner | `search_path` Set | Auth Check Present | Org Resolution Rule | Dynamic SQL | Audit Logged | Risk Level | Mitigation Required in Cutover |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `private.current_profile_id` | `postgres` | `''` (Empty) | `auth.uid()` | `eco_user_profiles.auth_user_id` | `FALSE` | `NO` (Read-only helper) | `LOW` | Read-only security helper |
| `private.active_org_id` | `postgres` | `''` (Empty) | `auth.uid()` | `eco_user_active_context` | `FALSE` | `NO` (Read-only helper) | `LOW` | Read-only security helper |
| `private.can_platform` | `postgres` | `''` (Empty) | `auth.uid()` | N/A (Platform Scope) | `FALSE` | `NO` (Read-only helper) | `MEDIUM` | Verify template & override lookup efficiency |
| `private.can_org` | `postgres` | `''` (Empty) | `auth.uid()` | Explicit `p_org_id` + Membership | `FALSE` | `NO` (Read-only helper) | `MEDIUM` | Core evaluation engine; benchmark concurrency |
| `public.change_user_role` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `ROLE_CHANGE`) | `CRITICAL` | Replace `func_role` with `can_org(..., 'ORG_MEMBER_PERMISSION_MANAGE')` |
| `public.set_user_active` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `STATUS_CHANGE`) | `HIGH` | Replace `func_role` with `can_org(..., 'ORG_MEMBER_MANAGE')` |
| `public.create_import` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `IMPORT_CREATED`) | `HIGH` | Replace `func_role` with `can_org(..., 'IMPORT_CREATE')` |
| `public.persist_import_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `BATCH_PERSISTED`) | `CRITICAL` | Validate import org ownership via `can_org` |
| `public.persist_perceptions_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `PERCEPTIONS_PERSISTED`)| `CRITICAL` | Validate import org ownership via `can_org` with `PERCEPTION_IMPORT` |
| `public.persist_financial_movements_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `FINANCIAL_PERSISTED`) | `CRITICAL` | Validate import org ownership via `can_org` with `BANK_IMPORT`/`PAYROLL_IMPORT` |
| `public.request_failed_import_retry` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `RETRY_REQUESTED`) | `HIGH` | Validate import org via `can_org(..., 'IMPORT_RETRY')` |
| `public.resolve_issue` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `NO` (`eco_review_actions` only — Functional History) | `HIGH` | Validate issue org via `can_org(..., 'ISSUE_RESOLVE')` |
| `public.soft_delete_normalized_record` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `RECORD_DELETED`) | `HIGH` | Validate record org via `can_org(..., 'RECORD_SOFT_DELETE')` |
| `public.restore_normalized_record` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `RECORD_RESTORED`) | `HIGH` | Validate record org via `can_org(..., 'RECORD_RESTORE')` |
| `public.soft_delete_financial_movement` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `MOVEMENT_DELETED`) | `HIGH` | Validate movement org via `can_org(..., 'RECORD_SOFT_DELETE')` |
| `public.restore_financial_movement` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `MOVEMENT_RESTORED`) | `HIGH` | Validate movement org via `can_org(..., 'RECORD_RESTORE')` |
| `public.update_record_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `CLASSIFICATION_UPDATED`)| `HIGH` | Validate record org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.update_movement_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`eco_audit_events`: `MOVEMENT_CLASSIFIED`)| `HIGH` | Validate movement org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.bulk_update_record_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `BULK_CLASSIFICATION`)| `HIGH` | Validate caller org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.create_global_tax_category` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`eco_audit_events`: `CATEGORY_CREATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.update_global_tax_category` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`eco_audit_events`: `CATEGORY_UPDATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.create_global_economic_activity` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`eco_audit_events`: `ACTIVITY_CREATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.update_global_economic_activity` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`eco_audit_events`: `ACTIVITY_UPDATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.upsert_arca_activity_catalog` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`eco_audit_events`: `CATALOG_UPSERTED`)| `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.create_org_activity_iibb_rate` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_org_id` / `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `RATE_CREATED`) | `CRITICAL` | Validate `p_org_id` via `can_org` or `can_platform` |
| `public.update_org_activity_iibb_rate` | `postgres` | `''` (Empty) | `auth.jwt()` | Row `organization_id` | `FALSE` | `YES` (`eco_audit_events`: `RATE_UPDATED`) | `CRITICAL` | Validate rate org via `can_org` or `can_platform` |
| `public.switch_superadmin_org_context` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` | `FALSE` | `YES` (`eco_audit_events`: `CONTEXT_SWITCHED`) | `CRITICAL` | Deprecate in favor of active context + capability |
| `public.assign_tax_category_to_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `CATEGORY_ASSIGNED`) | `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.unassign_tax_category_from_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `CATEGORY_UNASSIGNED`)| `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.assign_economic_activity_to_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `ACTIVITY_ASSIGNED`) | `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.unassign_economic_activity_from_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`eco_audit_events`: `ACTIVITY_UNASSIGNED`)| `CRITICAL` | Validate target org via `can_org` / `can_platform` |

### Security Audit Notes & Dynamic SQL Verification
- `REPOSITORY_SECURITY_DEFINER_DYNAMIC_SQL_EVIDENCE: NONE_FOUND`: Repository-wide inspection of SECURITY DEFINER functions for `EXECUTE`, `EXECUTE format(`, and `format(...)` confirmed zero dynamic SQL within repository visibility.
- `FAILED_PRIVILEGED_ATTEMPTS_AUDITED: NO`: Unauthorized RPC calls currently trigger PostgreSQL exceptions without generating audit log rows. This target-design gap will be addressed in future capability cutover WPs.

---

## 2. RLS Performance Risk Classification

When cutting over RLS policies from `organization_id = private.org_id()` to `private.can_org(organization_id, 'CAPABILITY_CODE')`, function execution occurs per candidate row during table scans.

| Table Name | Volume Classification | Current Policy Pattern | Target Cutover Pattern | Performance Risk Level | Required Performance Mitigation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `eco_normalized_records` | `FUTURE_SCALE_SCENARIO` (>100k rows/tenant)<br>`OBSERVED_CURRENT_VOLUME`: <500 rows | `organization_id = private.org_id()` | `private.can_org(organization_id, 'RECORD_VIEW')` | **CRITICAL** | Composite index `(organization_id, is_active)` mandatory. `STABLE` function optimization for `can_org` required. |
| `eco_financial_movements` | `FUTURE_SCALE_SCENARIO` (>50k rows/tenant)<br>`OBSERVED_CURRENT_VOLUME`: <500 rows | `organization_id = private.org_id()` | `private.can_org(organization_id, 'RECORD_VIEW')` | **CRITICAL** | Composite index `(organization_id, is_active)` mandatory. Benchmark EXPLAIN ANALYZE. |
| `eco_import_issues` | `FUTURE_SCALE_SCENARIO` (~5k rows/tenant)<br>`OBSERVED_CURRENT_VOLUME`: <100 rows | `organization_id = private.org_id()` | `private.can_org(organization_id, 'IMPORT_REVIEW')` | **MEDIUM** | Index `(organization_id, status)`. |
| `eco_source_files` | `FUTURE_SCALE_SCENARIO` (~1k rows/tenant)<br>`OBSERVED_CURRENT_VOLUME`: <100 rows | Subquery on `eco_source_imports` | `private.can_org(import.organization_id, 'IMPORT_VIEW')` | **HIGH** | Replace nested subquery with direct `organization_id` column or join. |
| `eco_source_imports` | `OBSERVED_CURRENT_VOLUME` (<500 rows) | `organization_id = private.org_id()` | `private.can_org(organization_id, 'IMPORT_VIEW')` | **LOW** | Direct index scan. |
| `eco_audit_events` | `FUTURE_SCALE_SCENARIO` (>500k rows)<br>`OBSERVED_CURRENT_VOLUME`: <500 rows | `organization_id = private.org_id() AND admin` | `private.can_org(organization_id, 'AUDIT_VIEW_ORG')` | **HIGH** | Index `(organization_id, created_at)`. |

### Performance Acceptance Criteria Protocol
Numeric pass/fail thresholds (such as `<1ms`) are not frozen in WP-A3.1 without active staging benchmarks. Instead, every domain WP must fulfill:
`PERFORMANCE_BASELINE_REQUIRED_BEFORE_CUTOVER` requiring:
1. `EXPLAIN` query plans on key tenant-scoped filters.
2. `EXPLAIN ANALYZE` execution profiles on representative datasets where safe.
3. Index verification to ensure zero unintended sequential scans on tenant-scoped tables.
4. Quantitative before/after comparison between legacy policy and capability policy execution.

---

## 3. Storage, Trigger, Edge Function & Realtime Evidence

- **Storage Policies**: 3 policies on bucket `eco-imports-private-staging` in `sql/005_storage_policies.sql`.
  - Risk: `CRITICAL`. Path prefix `(storage.foldername(name))[1]` currently compares against `private.org_id()::text`.
  - Cutover Plan: Ensure folder prefix matches target organization ID validated via `private.can_org(org_id, 'IMPORT_CREATE')`.
- **Database Triggers**: 1 trigger `enforce_append_only_audit` on `public.eco_audit_events` in `sql/004_audit.sql`.
  - Risk: `LOW`. Preserved without change to guarantee audit trail append-only immutability.
- **Edge Functions Evidence**: `REPOSITORY_EDGE_FUNCTIONS_EVIDENCE: NONE_FOUND`
- **Webhooks Evidence**: `REPOSITORY_WEBHOOKS_EVIDENCE: NONE_FOUND`
- **Scheduled Jobs Evidence**: `REPOSITORY_SCHEDULED_JOBS_EVIDENCE: NONE_FOUND`
- **Realtime Evidence**: `REPOSITORY_REALTIME_EVIDENCE: NONE_FOUND`

---

## 4. Critical UI Data Isolation Risk (Stale State Analysis)

Phase 0 discovery identified that switching `activeOrganizationId` in the frontend UI (`src/store.js`) reloads the active catalog, but **DOES NOT CLEAR** previously loaded in-memory tenant arrays.

### Vulnerable In-Memory Stores (`src/store.js`)
1. `appStore.items` (Normalized Accounting Records)
2. `appStore.perceptions` (ARBA/AGIP Perceptions)
3. `appStore.banks` (Bank Statement Movements)
4. `appStore.salaries` (Payroll Movements)
5. `appStore.manualMovements` (Manual Adjustments)

```
[UI Organization Switcher]
        |
        +---> Updates activeOrganizationId
        +---> Fetches new organization categories/activities
        X---> FAILS TO CLEAR appStore.items / perceptions / banks / salaries / manualMovements
        |
        +---> CRITICAL UI DATA ISOLATION RISK: User sees previous tenant's records!
```

### Required Mitigation in WP-A3.3
- Implement explicit store reset handler: `appStore.clearTenantState()` whenever `activeOrganizationId` changes.
- Invalidate and purge all client-side cached capability arrays during organization switch.
