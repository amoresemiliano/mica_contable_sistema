# DEV-BUSINESS-HEALTH-METRICS-01 — Delivery

BASE_SHA: 6f81b4004ca35af2b0a089f71bb23fc59d407128

STATUS: IMPLEMENTED / READY_FOR_MANUAL_CHECK. Local browser verified with
canonical fixtures; DEV hosted runtime has not been changed or verified.

Independent Métricas navigation, five internal views, 44 metric contract entries,
six fixed-weight pillars, conservative health score, 22 signal rules, 66 review
templates, maximum-five priorities, positive signals, six-month recomputed
timeline, diagnostic limitations and canonical transaction drilldown are included.
Unavailable contract entries are explicitly described in the design document.

GERENCIA_CHANGED: NO. Existing report calculations remain unchanged.
AUTHORIZATION_CHANGED: YES, module route registration only; reuses REPORT_VIEW
without new capabilities, grants or server authorization rules.
SQL_CHANGED: NO. MIGRATION_REQUIRED: NO. MIGRATION_FILE: none.
EDGE_CHANGED: YES, existing mica-reporting handler gains read-only health action.
SQL_EXECUTED: NO. PROD_TOUCHED: NO. DEPLOYED: NO.
READY_FOR_DEV_MIGRATION: NO migration needed.
READY_FOR_DEV_DEPLOY: YES for this work package; hosted acceptance requires a
future authorized deployment of BOTH application and mica-reporting.

## Validation evidence

- Final focused metrics/server/canonical reporting/currency/numeric tests:
  **131 passed across five suites**, zero failures.
- Real local Edge fixture browser: desktop 1440×1000 and mobile 390×844, all five
  views, no horizontal overflow, canonical detail, org reset, stale-response
  rejection, cross-org response rejection, permission revocation passed.
- Final full suite scoped to tests/: **910 passed, 9 pre-existing failures across
  75 suites (919 tests)**. All nine failures are historical SQL fingerprint checks.
- The first mismatch `sql/009_supabase_native_auth.sql` has the SAME SHA-256 in
  the starting commit and working copy:
  `56a5716b8b8ae6676a7d50f53a88681b004b656e4c896c98c444fb9f462bd06f`.
  The stale fixture expects
  `74da6cead124530f0f2e38891119d2ee44c5bc43b025125e9905944016e3e708`.
  No historical SQL was edited to bypass these failures.
- Failing suites: administration038, moduleImport039, operational039b,
  sql039c, sql039e, sql039g, sql039i, sql039j, sql039k (tests/services).
- An initial unscoped Jest run also discovered duplicate tests under untracked
  .local-data; it was stopped and replaced with the tests/-scoped run.
- Screenshots and test JSON are local scratch evidence, excluded from commit.
- Pre-existing modified tests/db/042_multiorg_and_rate_assignments.sql and all
  unrelated untracked files are excluded from this work package.

## Manual acceptance after an authorized DEV deployment

1. With REPORT_VIEW, open Métricas from desktop navigation and mobile More.
   Confirm five views and that Gerencia remains a separate module.
2. Select a known imported month, prior month, 3/6 months, YTD and custom dates.
   Open a metric detail; verify formula, limits, previous references and source
   transactions correspond to the selected company and period.
3. Use an organization with foreign purchases and missing employer charges.
   Result/global index must be unavailable; bank flow and sales remain visible;
   currency exclusions and required charges are disclosed.
4. Switch company while a request is pending; prior metrics/transactions must
   disappear and must not reappear from the stale response. Repeat with revoked
   REPORT_VIEW.
5. For complete six-month history, inspect pillar weights/contributions and
   timeline. Repeat the same request: values and priorities must match; at most
   five priorities appear, with positive signals in their own section.

## Files

index.html; src/js/ui.js; src/js/core/micaPermissionContract.js;
src/js/core/reporting/server.js; src/js/core/metrics/{engine,scoring,confidence,signals}.js;
src/js/components/{businessMetrics,metricDetail}.js; src/css/businessMetrics.css;
tests/businessMetrics.test.js; tests/browser/business-metrics.mjs;
docs/DEV_BUSINESS_HEALTH_METRICS_01_{DESIGN,DELIVERY}.md.
