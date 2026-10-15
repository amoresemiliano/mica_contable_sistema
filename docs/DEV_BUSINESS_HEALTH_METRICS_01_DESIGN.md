# DEV-BUSINESS-HEALTH-METRICS-01 — Design

## Architecture and authorization

`Métricas` is an independent application module after Gerencia, with Salud,
Rentabilidad, Liquidez, Operación and Riesgos y prioridades views. Gerencia and
Reportes retain their existing behavior. Desktop navigation and the mobile More
sheet expose the new module. Its capability is the existing `REPORT_VIEW`.

`mica-reporting` action `health` verifies JWT, allowed origin, operational tenant,
and the existing `mica_reporting_data` RPC authorization. It reads selected and
previous equivalent periods plus six months of historical facts. IVA opening
carry-forward expands the history to the latest applicable opening when within
the existing 36-month bound. No service-role reads, new permissions, raw-table
widget queries, writes, persistence, or migrations are introduced.

The shared pure engine consumes the canonical reporting model on the trusted
server. Client-supplied scores, amounts and recommendations are ignored. The
browser only presents results and uses the existing organization-checked detail
RPC. Historical and comparison references carry their source date ranges.
There is no result cache. Organization generation changes, permission revocation
and newer requests invalidate prior responses and clear the rendered diagnosis.

Files are separated into engine (canonical adapters/metrics), scoring, confidence,
signals/recommendations/priorities, controller/presentation and metric detail.
The catalog is versioned `business-health-v1`; thresholds are deliberately not
tenant-configurable in this release. Currency amounts are canonical ARS cents.

## Contract and metric matrix

Every entry exposes code, name, pillar, value, unit, status, score, trend,
comparison/baseline, confidence, explanation, why_it_matters, recommended_actions,
formula, period, source_count, exclusions, missing and drilldown. Drilldown
contains current, previous and historical canonical filters, manual adjustments
and breakdown rows. Source counts count references and may repeat for compound
formulas; they are explicitly labelled that way, not unique transaction counts.

There are **44 contract entries**, including explicit unavailable entries. The
count is not a claim that all 44 are calculable for every organization.

| Pillar | Codes | Meaning |
| --- | --- | --- |
| Ventas | sales, sales_change | Net sales and previous equivalent change |
| Ventas | sales_trend_3, sales_trend_6 | Current full month versus preceding 3/6-month average |
| Ventas | best_sales, worst_sales | Highest/lowest observed month in selected range |
| Ventas | declining_months | Consecutive observed monthly declines |
| Ventas | sales_activities | Canonical activity breakdown |
| Ventas | customer_concentration | Explicitly unavailable: reliable customer identity absent |
| Costos | purchases, purchase_change | Net purchases and equivalent change |
| Costos | purchase_share, purchase_share_change | Purchases/sales and change in percentage points |
| Costos | expense_vs_sales | Purchase growth minus sales growth, percentage points |
| Costos | purchase_categories, category_concentration | Category totals and largest category share |
| Costos | supplier_top1, supplier_top3, supplier_top5 | Supplier dependency shares, only with identified nonnegative purchase groups |
| Costos | unclassified_share | Unclassified ARS purchase record count / ARS purchase record count |
| Rentabilidad | result, margin | Complete documentary result before tax and result/sales |
| Rentabilidad | result_change, margin_change | Result growth and margin percentage point change |
| Rentabilidad | positive_months, negative_months | Sign counts only when all selected months have valid results |
| Liquidez | bank_flow, bank_income, bank_outflow | Net flow, receipts and payments |
| Liquidez | flow_change, negative_flow_months | Flow change and consecutive negative observed months |
| Liquidez | balance_change | Unavailable: canonical accounts lack observation dates and tie ordering |
| Personal | payroll, employer_contributions, sac | Gross payroll, explicit employer charges, imported SAC |
| Personal | payroll_change, payroll_share, employer_share | Payroll growth, payroll/sales, charges/sales |
| Personal | payroll_vs_sales | Payroll growth minus sales growth |
| Fiscal | iva_share, iibb_share | Canonical estimated payable / sales; full months only |
| Fiscal | iva_credits | Documented VAT purchase credit |
| Fiscal | tax_configuration | Canonical fiscal limitations; no invented completeness score |
| Fiscal | tax_anomalies | Unavailable until an exclusively fiscal anomaly contract exists |

## Health methodology

Weights: Rentabilidad 25%, Liquidez 20%, Ventas 15%, Costos 15%, Fiscal 15%,
Personal 10%. An eligible metric contributes a discrete score: HEALTHY=85,
WATCH=65, CRITICAL=35, POSITIVE_SIGNAL=90. Other statuses have no score. LOW
confidence metrics cannot contribute. Descriptive breakdowns, data quality,
concentrations and redundant derivatives are excluded from scoring.

Pillar score is the rounded arithmetic mean of its explicitly eligible metrics;
the response lists included/excluded metric codes. Global contribution is
pillar score × fixed weight / 100; global score rounds the sum to an integer.
No weights are redistributed. **All six pillars must be evaluable for a global
score**; otherwise score=null and status=INSUFFICIENT_DATA. Missing is never 0.
Status bands: GREEN >=80, YELLOW >=50, RED <50. Details expose scores, weights,
contributions, excluded pillars and confidence limitations. Trends use the same
method on the comparable prior period; unavailable comparisons remain null.

Eligibility: result is scored only when canonical result is complete; bank flow
uses its sign; sales/sales change require a valid prior equivalent; purchase
growth requires sales growth; purchase share and payroll share require a company
baseline; fiscal ratios require six valid historical full months. The global
index is consequently unavailable for many newly imported companies. This is
intentional and separate from useful available metrics and signals.

## Default thresholds and evaluation rules

These are conservative investigation defaults, not sector norms or measures of
staffing efficiency. No external benchmarks or inflation adjustment are used.

| Rule | Default |
| --- | --- |
| Sales deterioration/improvement | Change below -15% / above +15% versus equivalent prior period |
| Purchase growth pressure | Growth exceeds sales growth by >10 percentage points |
| Purchase share pressure | >10 points above six-month company median, falling back to prior share |
| Payroll share pressure | >8 points above six-month company median, falling back to prior share |
| Documentary loss | Complete result <0; zero is not a loss |
| Bank flow watch | Net flow <0, without describing observed balance as cash available |
| Bank outflow spike | Full current month >130% of preceding six-month median |
| Fiscal pressure spike | Full month ratio >130% of six-month median AND >3 points above it |
| Flat sales / payroll up | ABS(sales change) <=5%, payroll change >10% |
| Supplier dependency | Top 3 >70%; WATCH signal only, no health penalty |
| Classification | >20% of ARS purchase records lack category; no health penalty |
| Margin improvement | >=5 percentage points above prior period |
| Cost control improvement | Purchase share <= prior share -5 points |
| Record sales | Full month exceeds all preceding six valid comparable months |
| Persistence | Two negative result/flow months; three successive declines require four months |

Zero or negative sales denominators yield null ratios. Change from zero yields
null. Three/six-month trends require every preceding month, not just a count of
sporadic observations. Partial fiscal periods are withheld. A custom partial
range uses separately filtered canonical selected/comparison facts. Prior-year
comparison clamps leap dates and requires actual prior evidence. YTD is an
explicit selectable range; it is not silently annualized. Ranges must fit the
canonical 36-month source limit including history/comparison.

## Confidence and missing-data semantics

Confidence and business health are separate. Imported records alone cannot
certify full business coverage, so conclusions are capped at MEDIUM. HIGH is
reserved for a future certified coverage source. Value absent => UNAVAILABLE;
known value with exclusions/missing facts => LOW; otherwise backed canonical
source references => MEDIUM. The engine never invents an 82% coverage figure:
coverage=null with a plain explanation. No confidence deduction is subtracted
from business scores; confidence controls eligibility.

Foreign currencies are disclosed and excluded without inferred FX. Canonical
incomplete totals stay null. Missing charges block result, but do not block
sales or bank flow. Missing bank facts do not block payroll. No payroll data is
different from explicit payroll-not-applicable. Zero manual charges remain an
explicit zero. NO_ACTIVITY means no activity in the observed imported dataset,
not certification that the business did nothing. Fiscal opening/configuration,
invalid canonical amounts and unclassified purchases remain visible. Fiscal
classification limitations affect the canonical tax engine; classification
quality is not turned into a business loss.

## Signals, recommendations and priorities

22 deterministic signal templates are defined in `SIGNAL_CATALOG`:
SALES_DECLINE, NEGATIVE_RESULT, PURCHASE_TO_SALES_PRESSURE, PAYROLL_PRESSURE,
BANK_FLOW_RECOVERY,
SALES_DOWN_COSTS_UP, EXPENSES_GROW_FASTER_THAN_SALES, SALES_FLAT_PAYROLL_UP,
NEGATIVE_FLOW_WITH_PROFIT, POSITIVE_FLOW_NEGATIVE_RESULT,
THREE_MONTH_SALES_DECLINE, TWO_NEGATIVE_RESULT_MONTHS,
HIGH_SUPPLIER_CONCENTRATION, LOW_CLASSIFICATION_COVERAGE,
FISCAL_PRESSURE_SPIKE, BANK_OUTFLOW_SPIKE, IMPROVING_MARGIN, RECORD_SALES,
COST_CONTROL_IMPROVING, MISSING_CRITICAL_DATA, FOREIGN_CURRENCY_EXCLUSIONS,
RECURRING_NEGATIVE_FLOW.

Business signals require non-null metric evidence with at least MEDIUM
confidence. Data-gap rules describe information limitations rather than assert
business outcomes. SALES_DOWN_COSTS_UP suppresses the related expense-growth
signal. The interface separates positive signals and limits action priorities
to five. Ranking: severity×4 + persistence×2 + deterioration + actionability +
confidence factor (2 HIGH, 1 otherwise) + monetary-evidence-presence factor;
ties use stable rule code order. Monetary relevance is deliberately coarse,
not a fabricated estimate of financial impact. Each of the 44 metric templates
and 22 signal templates provides a traceable review action: **66 templates**.
They recommend reviewing, validating and investigating, never autonomous decisions.

## Extension points and deliberate deferrals

Metric codes, pillar assignment, versioned rules and canonical evidence allow
future additions without widget calculation logic. No configuration engine or
schema is needed. Existing ALERT_SETTINGS remains unchanged and does not silently
override this independently versioned health methodology.

Deferred: EBITDA, product contribution/break-even, fixed/variable costs,
receivables/payables ratios, available cash, runway, working capital, seasonality,
reliable customer concentration, ambiguous bank balance changes and exclusively
fiscal anomalies. Tax configuration is a limitation entry, not a scored count.
No forecasting, scenarios, AI narrative/chatbot, peer/sector/market benchmarks,
cross-tenant cohort access or source-record modifications. No future features
appear as working controls. Timeline is recalculated, not persisted or presented
as a historical immutable snapshot.
