# DEV-OPERATIONAL-WORKSPACE-REFINEMENT-01

Base: `2bcf327af8db5ff538196436bce12fda58cbd9f5` / `dev`.
Status: workspace implemented and locally verified; live category identity diagnosis pending.
No deployment, remote SQL, data repair or PROD operation.

## Shared workspace

`operationalWorkspace.js` mounts the same structure for Comprobantes, Percepciones,
Bancos and Sueldos. Row 1 contains module title, one organization selector and
email/role. The redundant entity label is hidden; organization is removed from
the user badge. Users without switching authority still see a disabled selector
for the confirmed company. Administration uses a generic tenant context label or
PLATAFORMA, retaining the separate managed-company selector only in platform mode.
The categorization page title is Categorización impositiva.

Row 2 reuses existing filter, date, search and column controls, then appends Importar
and Descargar menus. Existing input IDs, accepted extensions, change/drop listeners,
import envelope and parsers are preserved. Large drop zones live inside the closed
import menu and remain usable for drag/drop when opened. Supported imports:
ARCA compras/ventas CSV; perceptions TXT/CSV/XLS/XLSX; bank XLS/XLSX; payroll XLS/XLSX.
Menus follow existing permissions and `btn-primary`/`btn-secondary` styling.

The data remains immediately after controls and existing summaries/bulk actions.
Payroll's displayed consolidated period now uses a scrollable table before its
unchanged manual settlement inputs and calculations. It remains a single totals
record, with no fabricated employees or new period-selection semantics.

## Downloads

All four menus offer CSV, Excel and PDF. The shared module exporter now supports
Bancos as well. The original Extractos store method remains unchanged and tested;
its former standalone control is replaced by the shared, filtered download menu.
No dependencies were added. CSV/XLSX retain the previous work package's fixed
accounting column contract; hiding screen columns does not remove those columns.

PDF is a browser print preview: the user chooses Save as PDF. It snapshots all
matching records before pagination, in current sort order, using visible reportable
columns. Currency/exchange rate remain explicit even when hidden in Comprobantes.
PDF includes module, selected company, date/period/search/type filters, UTC generation
timestamp and record count. Values are HTML escaped; no JSON or internal IDs appear.
Print uses an isolated iframe, landscape layout and repeated column headings.

Authorization remains `RECORD_VIEW` + `REPORT_EXPORT` within the confirmed tenant.
All export rows must match the active organization. Empty/loading/error contexts
cannot download. PDF introduces no additional data fetch or broader permission.

## Sorting and scrolling

Root cause of the rightmost Comprobantes sorting failure: grids sorted keys
`categoria`, `actividad`, `estado`, while records contain classification IDs and
`confirmada`; there were no extractors for the rendered labels.
`operationalSemantics.js` resolves catalog labels and categorized/pending semantics
for rendering filters, ordering and export ordering. It also maps Neto/Exentas,
operation, perception columns and bank classification. Bank Estado is now sortable.
Date sorting parses both DD/MM/YYYY and ISO through the existing grid date parser.
Sorting acts on a filtered array copy before pagination; native stable sorting
preserves tied source order. Missing classifications sort as blank labels. Existing
column preferences remain intact; no storage keys or defaults are reset.

Root cause of inaccessible mobile columns: the existing mobile stylesheet changed
table wrappers to `overflow-x:visible` and converted table elements into cards.
Operational wrappers now use dedicated internal horizontal scrolling, readable
table widths, native table display on mobile and touch scrolling. Catalog wrappers
also receive bounded horizontal overflow. Sidebar and outer page widths stay usable.
No sticky-column machinery was introduced.

## Multiple tabs and company safety

Sidebar items become real `href="#tab-…"` links. Plain click navigates the SPA;
Ctrl/Cmd/Shift/middle-click and the native context menu retain browser behavior.
Each tab's URL hash selects its module on context hydration, independently of other
tabs. Two real local browser pages were tested with Comprobantes and Bancos.

**Different modules with the same company are supported. Independent companies
per tab are not supported by the current backend.** SQL 019's `private.active_org_id`
reads `eco_user_active_context` by `user_profile_id`; the selected company is server
state per user, not independent sessionStorage state. SQL 035/037 snapshot functions
validate the requested company against that active context. No SQL/auth change is made.

When a tab starts a company switch, a BroadcastChannel message invalidates other
same-user tabs. Those tabs advance their generation, clear tenant data/cache,
disable actions and show a reload-context message. A storage-event fallback is
provided. Messages do not copy a company into another tab or authorize anything.
Existing generation checks, server-context verification and visibility refresh
remain. BroadcastChannel/storage coordinate same-origin tabs in the same browser;
they are not distributed locks across devices. Existing server checks remain the
authority. After reloading, tabs adopt the current server company explicitly.

## Category identity diagnosis and SQL decision

The Product Owner clarified that a concept should have one canonical ID; merely
hiding different IDs is not an acceptable repair.

Repository evidence:

- Global `loadTaxCategories` selects directly from `eco_tax_categories`, without
  assignment joins. It builds assignment metadata separately by `category_id`.
  Organization assignments therefore do not multiply the global definition query.
- Schema 014 defines categories by primary-key ID and organization assignments by
  `(organization_id, category_id)`. It has no unique concept/name constraint.
- The UI maps each loaded global definition once. Identity deduplication now guards
  repeated rows with the **same ID**. Distinct IDs are never collapsed by display name.
- A diagnostic detects distinct IDs sharing normalized name and category type;
  platform UI reports that review is required. Income/expense semantics remain
  separate. Organization assignment and activation continue to use canonical IDs.

**Live root cause remains unproven.** This session has no authenticated DEV data
connection. Local tests establish representation semantics, not the contents of
BAIGORRIA's live catalog. No row has been deleted, renamed, merged or reassigned.
No repair migration is justified without actual conflicting IDs and reference counts.
`SQL_CHANGED=NO`, `MIGRATION_REQUIRED=UNDETERMINED`, `MIGRATION_FILE=none`.

Read-only diagnostic, if needed in the authenticated DEV browser console while in
platform catalog context (REST reads only, no SQL execution):

```javascript
const { supabase } = await import('/src/js/core/services/supabaseClient.js');
const { duplicateDefinitions } = await import('/src/js/core/operationalSemantics.js');
const definitions = [];
for (let offset = 0; ; offset += 500) {
  const { data, error } = await supabase.from('eco_tax_categories')
    .select('id,name,category_type,is_active').order('id').range(offset, offset + 499);
  if (error) throw error;
  definitions.push(...data);
  if (data.length < 500) break;
}
const conflictIds = new Set(duplicateDefinitions(definitions).flat());
console.table(definitions.filter(row => conflictIds.has(row.id)));
```

If IDs differ, subsequent repair needs an explicitly selected survivor, an inventory
of every category reference and assignment (including custom names/activation),
conflict resolution, transaction/rollback strategy and a new migration. None is
invented or executed in this package. The category identity requirement prevents
closing the complete work package until this evidence is reviewed.

## Validation and acceptance

Focused Jest command:

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests --runTestsByPath tests/ui/operationalWorkspace.test.js tests/ui/moduleExports.test.js tests/ui/operationalGrid.test.js tests/ui/ownerOperationalContext.test.js tests/ui/adminUx01.test.js tests/ui/admin039e.test.js tests/ui/settingsRoleContext.test.js tests/parsers.test.js tests/importCompatibility.test.js tests/reportingExports.test.js
node tests/browser/module-exports.mjs
```

Coverage includes semantic category/activity/state sorting, full filtered scope,
stable ties/nulls, CSV/XLSX round trips for four modules, four PDF adapters, visible
PDF columns, native click semantics, context invalidation, category identity and
assignments, original Extractos export, imports and reporting-export regression.
Browser uses actual index/styles/UI with synthetic local data and stubbed Supabase.
It checks 1440px/390px layouts, all four headers, imports, downloads, enabled columns,
scrolling to rightmost content, no page overflow, two real tabs and BroadcastChannel.
PDF HTML/dispatch is tested; actual Save as PDF pagination remains a manual check.
Final focused result: **255 tests passed in 10 suites; zero failures**. The local
browser run passed all four modules, 1440px/390px, 8 CSV and 8 XLSX dispatches,
8 PDF snapshots, file pickers, native links and two-page context invalidation.

Known preexisting broad-suite failures from the base: historical SQL fingerprint
mismatches and an unrelated reporting fake-DOM `root.querySelector` failure.
No reporting engines, Gerencia/Métricas components, parsers or SQL 045/046/047 change.

Manual checks after a separately authorized DEV deployment:

1. In each operational module confirm company appears once, email/role is correct,
   menus fit and import chooses the existing file picker; drag/drop works when open.
2. Enable all columns and sort Categoría/Actividad/Estado in both directions; change
   pages and scroll to the right at desktop and mobile widths.
3. Filter records, download CSV/Excel, then print to PDF; compare company, scope,
   signs/currency, visible PDF columns and page breaks.
4. Open Bancos in another tab using Ctrl/Cmd/middle-click. Keep Comprobantes in the
   first; switch company in one and verify the other clears and requires context reload.
5. In platform categorization inspect the read-only duplicate-ID diagnostic and
   verify organization assignments before deciding on any data-repair migration.

Unrelated preexisting user changes, including the modified DB test 042, are excluded.
