# DEV-MODULE-EXPORTS-01

Base: `87b2619d9f7edabe9351d0b48a09162709f27937` (`dev`).
Status: IMPLEMENTED / locally verified / READY_FOR_MANUAL_CHECK after a separately authorized DEV deployment.

## Audit and implementation

The operational Extractos control in `index.html` calls `AppStore.exportBankMovements`:
SheetJS `json_to_sheet`, sheet `Extractos`, filename `Extractos_Bancarios.xlsx`.
It exports its bank collection and has no operational CSV button or CSV utility.
That method and its control remain unchanged; a regression test checks its headers,
values, worksheet and filename. The reporting CSV convention elsewhere in the
repository is UTF-8 BOM, semicolon separators, quoted fields and CRLF. The new
operational CSV follows those conventions, including spreadsheet formula protection.
No reporting code was changed.

The new shared `core/moduleExports.js` handles authorization, company scoping,
CSV serialization, workbook creation and downloading. Module adapters select scalar
fields from the actual persisted view models. It reuses the existing SheetJS
dependency and browser vendor bundle; there are no added dependencies. The exact
grid extractors are shared between rendering and exports, with identical values.
Secondary buttons use the existing `btn-secondary` style and wrapping groups.

## Dataset contract

- Comprobantes and Percepciones export **all matching loaded records before UI
  pagination**, in the current grid sort order. Search, operation/jurisdiction,
  month or custom date bounds use `OperationalGrid.filterAndSort`, exactly as the UI.
  Checkbox selection and column visibility do not change the report; its accounting
  columns have fixed ordering. Existing grid date/jurisdiction semantics are preserved.
- Sueldos has no employee grid or period selector. Its source is a payroll **totals
  row**, not individual employees. Export the single `appStore.salaries` consolidated
  period displayed in Detalle de Liquidación Importada. Other loaded periods are
  excluded. No employee, CUIL, employer contribution or manual settlement fields
  are invented.
- Comprobantes exports date, operation, voucher type and number, CUIT, name,
  currency, exchange rate, taxable/non-taxable net, exempt amount, IVA, other taxes,
  total, category/activity names and classification state. Amounts and credit-note
  signs are copied from the canonical view model, without recalculation, conversion
  or sign inversion; USD remains USD.
- Percepciones exports date, period, type, source/tax, regime, jurisdiction, CUIT,
  agent/name, voucher, canonical amount and category/activity names. IVA and IIBB
  sources remain distinct. Base/rate/currency are absent from the canonical loaded
  perception model and are not fabricated or extracted from raw JSON.
- Payroll exports the displayed remunerative/non-remunerative totals, advances,
  proportional SAC, mandatory union contribution, FAECYS, net pay, calculated gross
  and calculated union contribution, together with period/source.
- Missing fields are blank. No raw payload, JSON, internal IDs or employee detail
  is included. XLSX preserves numeric types. Dates remain readable source strings.
- Names follow `mica_<module>_<sanitized company>_<period or range or todos>.<ext>`.
  Payroll uses its displayed period. Unbounded grid exports use `todos`.

## Company and permission boundaries

Both formats require the existing export action (`RECORD_VIEW` + `REPORT_EXPORT`)
in the established `TENANT_READY` context. Each exported row must explicitly match
`activeOrganizationId`. No caller-supplied organization is accepted. No additional
fetch, service role, permission, SQL or remote operation is introduced.
Downloads read current state synchronously rather than retaining a dataset closure.
Loading/error datasets and SWITCHING/LOADING/ERROR/signed-out contexts cannot export.
Existing `clearTenantState` clears all data on a confirmed company switch. Export
controls disable for an empty dataset and direct calls give a nontechnical message.

## Local validation

Passed: **68 tests across 3 suites**, including 16 new export tests and existing
grid/context tests:

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests --runTestsByPath tests/ui/moduleExports.test.js tests/ui/operationalGrid.test.js tests/ui/ownerOperationalContext.test.js
node tests/browser/module-exports.mjs
```

The browser uses the actual index, styles and UI modules with synthetic local
records and a stubbed Supabase client; no remote application or database is used.
Edge headless passes at 1440px and 390px: all six format actions per viewport,
CSV blob contents, XLSX download dispatch, enabled/empty controls, filter state,
context transition and control bounds. Full-page scroll width does not increase
when the export groups are shown. Workbook bytes are separately written and read
back in the unit tests; opening in desktop Excel/LibreOffice is a manual check.

The broad Jest run could not complete: historical SQL fingerprint tests fail
(administration038, operational039b, sql039c/e/g/i/j/k and moduleImport039), then
an unrelated reporting test terminates with `root.querySelector is not a function`
at `financeUi.js:30`. The failing SQL 009 hash is
`56a5716b8b8ae6676a7d50f53a88681b004b656e4c896c98c444fb9f462bd06f`
in **both the base commit and working tree**, versus the historical fixture's
`74da6cead124530f0f2e38891119d2ee44c5bc43b025125e9905944016e3e708`.
Reporting implementation and tests are unchanged. An initial unrestricted Jest
discovery also included untracked historical `.local-data` copies; the focused
command above confines discovery to canonical test paths.

## Manual DEV acceptance after separate deployment

1. Select company A. In Comprobantes apply a month, operation and search. Download
   CSV and Excel; compare row count and totals with the filtered summary, including
   all pages. Confirm a credit note retains its sign and USD currency is explicit.
2. In Percepciones filter IVA, then ARBA/IIBB. Download both formats and confirm
   source/regime/jurisdiction and signed amounts match the respective list.
3. In Sueldos download both formats. Confirm the single consolidated period and
   totals match the imported detail. Open XLSX in Excel/LibreOffice and sum numeric cells.
4. Switch A to B, then to an empty company. Confirm no A records appear in B and
   exports disable during switching and for empty results. Check accents/quotes.
5. At desktop and mobile widths verify import remains available under its existing
   permissions and the secondary exports fit. Confirm Extractos Excel is unchanged.

No SQL/auth/edge/import behavior changes. No SQL executed, PROD touched or deployment
performed. Preexisting user files, including `tests/db/042_multiorg_and_rate_assignments.sql`,
are excluded from this work package's commit.
