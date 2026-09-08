# MICA Authorization Risk Register (WP-A3.1)

> **Document Status**: DISCOVERY COMPLETE & FROZEN  
> **Baseline Commit**: `7aae65c9029822d120339670b962b596bae94cd7`  
> **Scope**: Comprehensive risk classification covering Security Definer functions, RLS performance, storage, client inputs, and frontend stale UI state.

---

## 1. Security Definer Function Risk Audit

All 32 SECURITY DEFINER functions in the repository have been audited against security best practices:

| Function Name | Owner | `search_path` Set | Auth Check Present | Org Resolution Rule | Dynamic SQL | Audit Logged | Risk Level | Mitigation Required in Cutover |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `private.current_profile_id` | `postgres` | `''` (Empty) | `auth.uid()` | `eco_user_profiles.auth_user_id` | `FALSE` | `NO` | `LOW` | Read-only security helper |
| `private.active_org_id` | `postgres` | `''` (Empty) | `auth.uid()` | `eco_user_active_context` | `FALSE` | `NO` | `LOW` | Read-only security helper |
| `private.can_platform` | `postgres` | `''` (Empty) | `auth.uid()` | N/A (Platform Scope) | `FALSE` | `NO` | `MEDIUM` | Verify template & override lookup efficiency |
| `private.can_org` | `postgres` | `''` (Empty) | `auth.uid()` | Explicit `p_org_id` + Membership | `FALSE` | `NO` | `MEDIUM` | Core evaluation engine; benchmark concurrency |
| `public.change_user_role` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`ROLE_CHANGE`) | `CRITICAL` | Replace `func_role` with `can_org(..., 'ORG_MEMBER_PERMISSION_MANAGE')` |
| `public.set_user_active` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`STATUS_CHANGE`) | `HIGH` | Replace `func_role` with `can_org(..., 'ORG_MEMBER_MANAGE')` |
| `public.create_import` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`IMPORT_CREATED`) | `HIGH` | Replace `func_role` with `can_org(..., 'IMPORT_CREATE')` |
| `public.persist_import_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`BATCH_PERSISTED`) | `CRITICAL` | Validate import org ownership via `can_org` |
| `public.persist_perceptions_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`PERCEPTIONS_PERSISTED`)| `CRITICAL` | Validate import org ownership via `can_org` with `PERCEPTION_IMPORT` |
| `public.persist_financial_movements_batch` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`FINANCIAL_PERSISTED`) | `CRITICAL` | Validate import org ownership via `can_org` with `BANK_IMPORT`/`PAYROLL_IMPORT` |
| `public.request_failed_import_retry` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`RETRY_REQUESTED`) | `HIGH` | Validate import org via `can_org(..., 'IMPORT_RETRY')` |
| `public.resolve_issue` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`ISSUE_RESOLVED`) | `HIGH` | Validate issue org via `can_org(..., 'ISSUE_RESOLVE')` |
| `public.soft_delete_normalized_record` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`RECORD_DELETED`) | `HIGH` | Validate record org via `can_org(..., 'RECORD_SOFT_DELETE')` |
| `public.restore_normalized_record` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`RECORD_RESTORED`) | `HIGH` | Validate record org via `can_org(..., 'RECORD_RESTORE')` |
| `public.soft_delete_financial_movement` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`MOVEMENT_DELETED`) | `HIGH` | Validate movement org via `can_org(..., 'RECORD_SOFT_DELETE')` |
| `public.restore_financial_movement` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`MOVEMENT_RESTORED`) | `HIGH` | Validate movement org via `can_org(..., 'RECORD_RESTORE')` |
| `public.update_record_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`CLASSIFICATION_UPDATED`)| `HIGH` | Validate record org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.update_movement_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `eco_source_imports.organization_id` | `FALSE` | `YES` (`MOVEMENT_CLASSIFIED`)| `HIGH` | Validate movement org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.bulk_update_record_classification` | `postgres` | `''` (Empty) | `auth.jwt()` | `private.org_id()` | `FALSE` | `YES` (`BULK_CLASSIFICATION`)| `HIGH` | Validate caller org via `can_org(..., 'RECORD_CLASSIFY')` |
| `public.create_global_tax_category` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`CATEGORY_CREATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.update_global_tax_category` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`CATEGORY_UPDATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.create_global_economic_activity` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`ACTIVITY_CREATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.update_global_economic_activity` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`ACTIVITY_UPDATED`) | `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.upsert_arca_activity_catalog` | `postgres` | `''` (Empty) | `auth.jwt()` | N/A (Platform Scope) | `FALSE` | `YES` (`CATALOG_UPSERTED`)| `HIGH` | Replace `func_role` with `can_platform('GLOBAL_CATALOG_MANAGE')` |
| `public.create_org_activity_iibb_rate` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_org_id` / `private.org_id()` | `FALSE` | `YES` (`RATE_CREATED`) | `CRITICAL` | Validate `p_org_id` via `can_org` or `can_platform` |
| `public.update_org_activity_iibb_rate` | `postgres` | `''` (Empty) | `auth.jwt()` | Row `organization_id` | `FALSE` | `YES` (`RATE_UPDATED`) | `CRITICAL` | Validate rate org via `can_org` or `can_platform` |
| `public.switch_superadmin_org_context` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` | `FALSE` | `YES` (`CONTEXT_SWITCHED`) | `CRITICAL` | Deprecate in favor of active context + capability |
| `public.assign_tax_category_to_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`CATEGORY_ASSIGNED`) | `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.unassign_tax_category_from_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`CATEGORY_UNASSIGNED`)| `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.assign_economic_activity_to_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`ACTIVITY_ASSIGNED`) | `CRITICAL` | Validate target org via `can_org` / `can_platform` |
| `public.unassign_economic_activity_from_org` | `postgres` | `''` (Empty) | `auth.jwt()` | `p_target_org_id` / `private.org_id()` | `FALSE` | `YES` (`ACTIVITY_UNASSIGNED`)| `CRITICAL` | Validate target org via `can_org` / `can_platform` |

---

## 2. RLS Performance Risk Classification

When cutting over RLS policies from `organization_id = private.org_id()` to `private.can_org(organization_id, 'CAPABILITY_CODE')`, function execution occurs per candidate row during table scans.

| Table Name | Estimated Row Volume | Current Policy Pattern | Target Cutover Pattern | Performance Risk Level | Required Performance Mitigation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `eco_normalized_records` | **HIGH** (>100k rows per tenant) | `organization_id = private.org_id()` | `private.can_org(organization_id, 'RECORD_VIEW')` | **CRITICAL** | Composite index `(organization_id, is_active)` mandatory. `STABLE` function optimization for `can_org` required. |
| `eco_financial_movements` | **HIGH** (>50k rows per tenant) | `organization_id = private.org_id()` | `private.can_org(organization_id, 'RECORD_VIEW')` | **CRITICAL** | Composite index `(organization_id, is_active)` mandatory. Benchmark EXPLAIN ANALYZE. |
| `eco_import_issues` | **MEDIUM** (~5k rows per tenant) | `organization_id = private.org_id()` | `private.can_org(organization_id, 'IMPORT_REVIEW')` | **MEDIUM** | Index `(organization_id, status)`. |
| `eco_source_files` | **MEDIUM** (~1k rows per tenant) | Subquery on `eco_source_imports` | `private.can_org(import.organization_id, 'IMPORT_VIEW')` | **HIGH** | Replace nested subquery with direct `organization_id` column or join. |
| `eco_source_imports` | **LOW** (<500 rows) | `organization_id = private.org_id()` | `private.can_org(organization_id, 'IMPORT_VIEW')` | **LOW** | Direct index scan. |
| `eco_audit_events` | **HIGH** (>500k rows) | `organization_id = private.org_id() AND admin` | `private.can_org(organization_id, 'AUDIT_VIEW_ORG')` | **HIGH** | Index `(organization_id, created_at)`. |

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
