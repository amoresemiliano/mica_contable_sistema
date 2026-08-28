# Consolidation Adversarial Review

## Overview
Reviewing the Consolidation phase (Migration 014 frontend integration) diff from `a31dcdf` to the new `dev` HEAD (`e9ab011`).

## Findings

### 1. `persistenceService.js: createIibbRate` RPC Call Parameter Mismatch
**Severity: HIGH**
**Location:** `src/js/core/services/persistenceService.js:462`
**Issue:** The frontend calls `create_org_activity_iibb_rate` with the parameter `p_rate: payload.rate_percent`. However, in the backend migration `sql/014_consolidation_crud_categorization.sql:632`, the RPC signature is `CREATE OR REPLACE FUNCTION public.create_org_activity_iibb_rate(p_activity_id UUID, p_jurisdiction TEXT, p_rate_percent NUMERIC, p_valid_from DATE, p_valid_to DATE)`. The backend expects `p_rate_percent`, not `p_rate`. This will cause IIBB rate creation to fail with a Postgres parameter mismatch error.
**Impact:** Users cannot save new IIBB rates.

### 2. `persistenceService.js: loadImportIssues` RLS Violation Risk
**Severity: HIGH**
**Location:** `src/js/core/services/persistenceService.js:485`
**Issue:** The method `loadImportIssues` performs a direct Supabase table select: `await supabase.from('eco_import_issues').select('*').order('created_at', { ascending: false });`. In the architecture rules (and `docs/ARCHITECTURE.md`), all tenant data should be accessed strictly via `SECURITY DEFINER` RPCs to bypass the anon role limitations and correctly enforce multitenancy in the standard MICA way, or there must be a valid RLS policy on the table. The `eco_import_issues` table does not currently have a "Select active import issues by org" RLS policy for the `authenticated` role (in `014` or prior migrations, the RLS policies are mainly on `eco_financial_movements`, `eco_normalized_records`, etc.). Accessing it directly could either fail (if RLS is enabled without a policy) or expose cross-tenant data (if RLS is disabled).
**Impact:** Import issues will either fail to load or, worse, leak data. It should be accessed via an RPC or a properly RLS-secured query relying on `private.org_id()`.

### 3. Missing Error Handling in `store.js`
**Severity: MEDIUM**
**Location:** `src/js/store.js`
**Issue:** Assuming the new `load*` functions added to `persistenceService.js` are called from `store.js` (e.g. `appStore.loadImportIssues()`), if these network calls fail, the error handling isn't explicitly shown in the `ui.js` diff. The UI might hang or silently fail to populate the categories.
**Impact:** Degraded user experience during network failures.

## Conclusion

E2E_READY = NO
