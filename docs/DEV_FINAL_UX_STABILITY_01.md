# DEV-FINAL-UX-STABILITY-01

Status: IMPLEMENTED / LOCAL_BROWSER_VERIFIED / READY_FOR_MANUAL_CHECK.
Base and remote dev observed: `59b40a557e4e719c559b32dd2c4e204f6c69d4bf`.
Final SHA: the local commit containing this document. No push or deployment.

## Navigation

Categorization is a logical route (`tab-categorizacion`) rendered in the
configuration section (`tab-configuracion`). Previously, access reconciliation
inferred the route from the visible section while hash restoration inferred it
from the categorization hash. Both could activate the administration shell again
on store notifications, causing repeated rendering and competing route changes.

The guard now distinguishes logical route, visible host and requested hash.
Platform fallback order is categorization, configuration, then access, filtered
by existing capabilities. A permitted manual route remains selected. Organization
fallback order and authorization contracts remain unchanged. Reconciliation does
not navigate when route, hash and host already agree. An unavailable hash is
replaced once even when its fallback host is already visible. Hash links recognize
the categorization alias and unknown/unavailable routes use the same access guard.
No timers, counters or permission grants were added.

## Executive presentation

Gerencia emphasizes sales, purchases, result and bank flow ahead of secondary
indicators. Larger values and status labels distinguish executive KPIs from
charts, operational interpretation and calculation details. Alerts group critical,
review and positive evidence; missing aggregate inputs appear as incomplete
documentary evidence. Next steps reuse existing missing-input and alert messages,
retain source trace buttons and contain at most three items.

Metrics adds a health diagnostic with why, available dimensions and next action;
six status-accented pillars with scores, trends and confidence; ranked priorities;
a compact positive-evidence section; a connected monthly strip; and diagnosis
quality counts and limitations. Unknown scores explicitly remain undeterminable.
No percentages, scores, positive claims or recommendations are invented.

Semantic palette: green/teal for supported positive signals, amber for review or
incompleteness, red for critical evidence, blue for information and gray for
unavailable evidence. Text accompanies color. Surfaces remain mostly white.
The current font stack and lightweight SVG rendering are retained.

## Operational toolbars

Desktop uses two grid rows: filters and Columnas on the left, Importar/Descargar
on the right; period controls below left and search below right. Existing nodes
are moved rather than cloned, preserving IDs, event handlers and file inputs.
Comprobantes, Percepciones and Bancos share this structure. Sueldos uses the same
grid with its consolidated payroll label and existing source/period badge; it
has no preexisting search or period selector, so none is fabricated.

Below 850px controls stack in functional order. Tables retain their independent
horizontal scroll. At small widths finance sections collapse into smaller grids
or a single column. Compact company/user headers are preserved.

## Files in this delivery

- `src/js/core/moduleAccess.js`
- `src/js/ui.js`
- `src/js/components/operationalWorkspace.js`
- `src/js/components/financeUi.js`
- `src/js/components/managementReporting.js`
- `src/js/components/metricOverview.js`
- `src/css/financeWorkspace.css`
- `tests/ui/finalUxNavigation.test.js`
- `tests/browser/module-exports.mjs`
- `tests/browser/management-reporting.mjs`
- `tests/browser/business-metrics.mjs`
- This document.

The seven implementation files already contained partial changes on arrival;
this delivery reviews and completes them. Unrelated local SQL/test and untracked
files are excluded. Reporting and metrics engines, 045–048, auth and edge code
were not changed. Access reconciliation changed; authorization policy did not.

## Validation

Focused Jest: **8 suites / 141 tests passed**, zero failures. Covers navigation,
render immutability, module permissions, sorting, category identity, exports,
reporting formulas, foreign currency and numeric contracts.

Three real local Edge runs passed using fixtures and stubbed services:

- Operational modules: desktop/mobile, measured toolbar alignment, payroll second
  row, CSV/XLSX/PDF, existing import pickers, table scrolling, page overflow,
  two browser tabs/context invalidation, stable platform routes and denied hash.
- Gerencia: five views, executive KPI hierarchy, bounded actions, three semantic
  alert groups using controlled evidence, incomplete status, fiscal preview,
  immutable snapshots, forms, currency detail and mobile overflow.
- Metrics: five views, no-score hero, six pillars, confidence, positive-evidence
  container, timeline states, complete score fixture, mobile overflow, stale
  requests, organization change and permission revocation.

Screenshots: `scratch/operational-workspace-{desktop,mobile}.png`,
`scratch/metrics-{desktop,mobile}.png`, and existing finance browser artifacts.
Desktop screenshots were visually inspected. These are local browser results,
not proof of hosted DEV login/session behavior.

General suite (`--roots tests`): **959 passed / 15 failed / 974 total**,
68 passing suites and 12 failing suites. All 15 failures are outside changed code:
nine historical SQL byte fingerprints, one obsolete Supabase mock, and five
header assertions expecting duplicated organization text. A clean HEAD archive
reproduced the mock and all five header failures plus a representative fingerprint
failure (7 failed, 24 passed). No historical SQL was edited to satisfy tests.
The focused run includes the final new hash-repair regression (141 tests).

Initial unrestricted Jest discovery included scratch/archive copies; authoritative
general counts above use `--roots tests`. An initial sandbox process restriction
required an approved retry. `git diff --check` passed.

## Manual acceptance after a separately authorized DEV deployment

1. Sign in as platform admin without a company. Confirm Categorization is the
   landing page; leave it open and switch to Configuration and back. Neither
   route should alternate automatically.
2. Open `#tab-bancos` without a company and refresh both platform-safe routes.
   Confirm one canonical fallback and stable manual selection.
3. Select a company, open an operational module, then return to Platform.
   Repeat with two tabs; confirm no redirect loop or cross-company data leakage.
4. Check Gerencia and Metrics with incomplete data and a complete period.
   Confirm explicit missing inputs, confidence, traceable actions and no false
   healthy status.
5. At desktop and mobile widths inspect all four toolbars, import/export menus
   and the rightmost table columns. Columnas stays on desktop row one.

## Return flags

SUPERADMIN_LOOP_FIXED: YES (local fixtures; hosted acceptance pending)
PLATFORM_DEFAULT_ROUTE: tab-categorizacion
CONFIG_ROUTE_STABLE: YES
CATEGORIZATION_ROUTE_STABLE: YES
GERENCIA_EXECUTIVE_HIERARCHY: YES
GERENCIA_SEMAPHORE: YES
GERENCIA_NEXT_ACTIONS: YES
METRICS_HEALTH_HERO: YES
METRICS_PILLAR_STATUS: YES
METRICS_PRIORITY_HIERARCHY: YES
METRICS_TIMELINE_REWORK: YES
TOOLBAR_TWO_ROWS: YES
COLUMN_SELECTOR_ROW1: YES
IMPORT_DOWNLOAD_ROW1_RIGHT: YES
PERIOD_ROW2_LEFT: YES
SEARCH_ROW2_RIGHT: YES (modules with search)
GERENCIA_LOGIC_CHANGED: NO
METRICS_LOGIC_CHANGED: NO
SQL_CHANGED: NO (unrelated preexisting worktree SQL remains excluded)
AUTH_CHANGED: NO
EDGE_CHANGED: NO
SQL_EXECUTED: NO
PROD_TOUCHED: NO
DEPLOYED: NO
READY_FOR_DEV_DEPLOY: YES, with the preexisting suite failures disclosed above.
BLOCKERS: no local package blocker; hosted DEV acceptance remains pending.
