# Gerencia, Reportes and Métricas — UI refinement

BASE_SHA: 32aca8a8da9a4e193a7432169881a85d06a41c2d

## Scope

Presentation refinement across the three existing financial modules. Shared
scoped tokens and primitives live in financeWorkspace.css and financeUi.js.
The application shell, calculation engines, contracts and source data are unchanged.

Gerencia now uses a clear page hierarchy, filter toolbar, executive KPI grid,
documented/partial/unavailable chips, emphasized values, deliberate chart surfaces,
severity-grouped alerts and an action to review pending configuration in Reportes.
Existing KPI and drilldown controls retain their event selectors.

Reportes groups preparation, exports and version actions separately. The report
identity has a formal header and status chip; tables distinguish concepts,
amounts, provenance and calculation controls. Version history, manual forms,
source dialog and incomplete banners share the workspace visual language.
Print rules remove workspace controls and preserve report identity, warnings
and repeatable table headers. PDF export implementation remains unchanged.

Métricas delegates presentation to metricOverview.js. Its hero separates the
business score from diagnostic confidence. Pillars show available scores,
native meters, status and trend. The highest priority has stronger desktop
emphasis; actions and evidence are separated. The landing page renders the
ranked priorities once instead of repeating them in two sections. Positive
signals, monthly evolution and diagnosis quality have distinct visual sections.
Uncertified coverage and unavailable scores remain explicitly unavailable.
Rule metadata and detailed missing-data lists are accessible in disclosures.

## Patterns

- Shared page header, section heading, semantic chip and empty state.
- Neutral white/slate structure, blue/teal informative emphasis, restrained
  green/amber/red semantic states; text accompanies every color.
- Hierarchical title, value, supporting note and provenance typography.
- Primary refresh/preview controls; separate export and version action groups.
- Evidence disclosures, action panels, structured warning banners and forms.
- Responsive KPI/pillar/insight/timeline grids, visible keyboard focus and
  reduced-motion support. Native meters/disclosures use their built-in semantics.

SQL_CHANGED: NO
AUTH_CHANGED: NO
EDGE_CHANGED: NO
CALCULATION_OR_CONTRACT_CHANGED: NO
BEHAVIOR_CHANGED: presentation/composition only; duplicate landing priorities
removed, evidence progressively disclosed, controls visually grouped.
DEPLOYED: NO
SQL_EXECUTED: NO
PROD_TOUCHED: NO

## Verification and limits

Local Edge browser fixtures cover Gerencia's five views/eight KPIs, report
preview, immutable snapshots and source detail, six manual configuration forms,
native USD detail and exclusions, Métricas' five views, company-switch stale
response rejection, permission revocation, and desktop/mobile overflow checks.
Focused rendering tests ensure the canonical health object is not mutated and
that source/organization strings remain escaped. Existing reporting/metrics
tests verify the preserved calculation and service flows.

Final focused tests: **135 passed in seven suites, zero failures**. Local browser
checks also cover print-media visibility, report preview on mobile, priorities
rendered once, unavailable global scores and a complete eight-month canonical
fixture with six pillar meters and score 85. No full-suite green claim is made.

Screenshots are generated in scratch/ for local inspection and excluded from
the commit. Hosted DEV acceptance remains pending: this work does not deploy.
The repository's previously documented historical SQL fingerprint failures
are outside this presentation-only package.

## Manual visual acceptance

1. Open Gerencia at desktop width and inspect the eight KPIs, their states,
   charts and severity-grouped alerts. Open a KPI and verify source detail.
2. Open Reportes, generate a preview and inspect identity, warnings, provenance
   and action groups. Open a saved version and a manual input form.
3. Open Métricas with complete and incomplete data. Verify that score and
   confidence are distinct and unavailable scores never appear as zero.
4. At 390 px, visit each internal view and open a detail. Confirm readable
   cards and no horizontal page overflow; wide report tables scroll locally.
5. Use keyboard navigation through tabs, disclosures and dialogs. Print a
   report and confirm report content remains formal and controls are hidden.

## Files

index.html; src/css/financeWorkspace.css;
src/js/components/{financeUi,metricOverview,businessMetrics,managementReporting,reportingCharts}.js;
tests/financePresentation.test.js;
tests/browser/{business-metrics,management-reporting}.mjs;
docs/DEV_FINANCE_UI_REFINEMENT_01_DELIVERY.md.
