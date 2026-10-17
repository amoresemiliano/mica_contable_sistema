# DEV-CATEGORY-CANONICALIZATION-048

Base: `0b327b0af829db2d24b373d45b389c9a6b34f9a9` / `dev`.
FK inventory correction: `DEV-CATEGORY-CANONICALIZATION-048-FK-INVENTORY-FIX`,
based on `c3467541a56ada40680198581bb1c453fe243713` and the Product Owner's manual
DEV evidence. Mutation scope and survivor mapping are unchanged.
Status: **PREPARED / LOCALLY_VERIFIED / READY_FOR_MANUAL_DEV_MIGRATION**.
No remote SQL execution, deployment or PROD access. Canonicalization has not been
applied to DEV by this work package. Counts below describe the supplied diagnosis
and verified local fixture, not a new remote observation.

## Explicit mapping and expected effect

| Concept / EXPENSE | Survivor | Duplicate IDs |
|---|---|---|
| Honorarios Profesionales | `c15675d7-be33-4400-84c3-9985e1a59579` | `326eaed3-d6cb-4d63-8adb-47116ad94bf5`, `3c86c6f9-aea0-4dc3-98e0-e30836daf0e5`, `46200cf5-c488-47b8-b946-e637885c7c82`, `e26570a7-6e09-40a4-8901-62b835df145e` |
| Telefonía | `02768384-f366-4fd9-aa0c-a437866cfeb4` | `a209c838-d3e3-4e3c-9b4f-4619c83cc336` |

The five duplicate definitions are deleted only after reassignment. Both BAIGORRIA
survivor rows, including names and metadata, are preserved. Expected reference
changes: **4 organization assignment keys, 1 normalized-record category ID,
0 financial movements, 0 other references**. The 15 Honorarios records already
on the survivor are unchanged. No accounting amount, sign, payload, organization
ID or reporting calculation is recomputed. An unassigned duplicate is backed up
and deleted even though it has no references.

## Inventory and preflight

Manual DEV evidence supplied for `DEV-CATEGORY-CANONICALIZATION-048-FK-INVENTORY-FIX`
confirmed six incoming category FKs. Schema 014 documents only the three mutated
references; the local fixture and preflight now also represent the additional DEV FKs.

Mutated reference tables (unchanged data-migration scope):

- `public.eco_normalized_records.category_id`
- `public.eco_financial_movements.category_id`
- `public.eco_org_tax_categories.category_id`

Verified-zero reference tables (no INSERT/UPDATE/DELETE or row restoration by 048):

- `public.eco_classification_rules.target_category_id`
- `public.eco_movement_allocations.category_id`
- `public.eco_tax_subcategories.category_id` — `ON DELETE CASCADE`.

The supplied DEV diagnostic found zero references to the five explicit duplicate
IDs in these three additional tables. UP reasserts zero under SHARE locks before
deleting any category; it never relies on cascading deletion. References to survivor
or unrelated IDs are permitted and preserved. Read-only output labels each FK as
MUTATED/VERIFIED_ZERO and reports all six reference counts per diagnosed ID.

Reporting 045/046/047 reads the canonical relational fields and stores historical
JSON snapshots; it introduces no additional direct category FK. Those engines
and their SQL remain unchanged. Legacy text fields are labels, not canonical UUIDs.

`048_preflight_readonly.sql` prepares manual, read-only evidence for server version,
all incoming category/assignment FKs, seven explicit definitions, reference counts,
organization assignments, normalized duplicate groups and additional serialized
references. It has been executed only against local PostgreSQL fixtures.

UP repeats its own mandatory assertions under table locks; the optional report
does not replace them. It requires:

- All seven explicit IDs and expected normalized names/types; all are EXPENSE.
- No additional definition of either diagnosed concept. Other unresolved normalized
  duplicates or empty category names abort global uniqueness creation; no unrelated
  concepts are merged automatically.
- Exact normalized-record counts: 15 Honorarios survivor, 1 Telefonía duplicate,
  zero on the other five IDs. All seven must have zero financial references.
  Counts include soft-deleted rows, so unexpected historical references abort.
- Duplicate assignment counts/organization labels match the diagnosis. BAIGORRIA
  must have both survivors, MICA the Telefonía survivor, and the known duplicate
  rows must belong to DEMO OESTE, DEMO NORTE or MICA as specified. Compatible
  survivor assignments to those same organizations are allowed for safe collisions.
  BAIGORRIA must be unambiguous; its Honorarios records cannot belong to another company.
- Runtime `pg_constraint` inventory must contain exactly the six reviewed FKs, with
  exactly one single-column, validated UUID FK for each explicit table/column pair
  to `eco_tax_categories.id`; subcategories must retain ON DELETE CASCADE. Delete
  actions not supplied in the DEV evidence are not invented; their complete actual
  definitions are recorded in the ledger and compared by DOWN. Unknown/composite
  FKs, missing expected FKs and incoming assignment FKs abort
  before mutation, even if currently empty. No unreviewed user triggers or existing
  generated/identity columns may affect exact row restoration.
- A scan of all columns in public/private user tables checks for explicit duplicate
  UUIDs outside the reviewed ID/FK columns. Extra scalar, domain, array, JSON,
  cached-report or audit references abort with table/column/count. Serialized
  historical sources and immutable report snapshots are never rewritten blindly.

If DEV differs, keep the error/report and revise this new migration from evidence.
Do not bypass assertions, disable FK checks, modify old migrations or delete rows
manually. No missing reference tables are guessed.

## Assignment collisions

Noncolliding assignments keep their assignment ID, activation, assignment flag,
custom label and timestamps; only `category_id` changes. On a collision, retain
the survivor assignment ID and copy the duplicate's custom label only if the
survivor label is absent. Different nonempty custom labels or differing activation/
assignment states abort for explicit resolution, rather than broadening availability.
The duplicate assignment row is then removed. The private ledger retains both
original rows, so DOWN can restore their exact separate identities.

## Prevention and creation flow

048 adds:

- Pure immutable `public.mica_category_name_key(text)`.
- Stored generated column `canonical_name_key`.
- Unique constraint `eco_tax_categories_canonical_name_048_key` on
  `(category_type, canonical_name_key)`.
- A nonempty canonical-name check.

Normalization uses built-in Unicode NFD, removes combining marks U+0300–U+036F,
collapses the JavaScript whitespace set, trims and lowercases. It covers accents,
case, repeated spaces, tabs, NBSP and decomposed accented input. PostgreSQL 13+
with UTF8 is required and representative locale results are asserted. No extension
or production dependency is added. See the official [PostgreSQL Unicode normalization
documentation](https://www.postgresql.org/docs/17/functions-string.html).

`categoryNames.js` uses the same contract. The UI checks equivalents within the
same type, excluding the current ID when editing. Creation service first looks up
the generated key and reports **“Esta categoría ya existe en el catálogo global.”**
without calling creation/assignment RPCs when an equivalent exists. A DB uniqueness
race produces the same message. Lookup failures abort; they never fall back to
an unchecked insert. The existing SECURITY DEFINER creation RPC and its authority
checks are unchanged. The database constraint also blocks direct inserts and renames
that bypass the UI. INCOME and EXPENSE remain separate concepts.

**Deployment order: apply 048 to DEV, verify it, then deploy this application commit.**
Before the migration, the new app intentionally cannot perform an unchecked create
against a schema without the generated key. After DOWN, roll back the app before
using category creation again. Operational imports/calculations are unchanged.

## Backup and rollback

`private.migration_048_category_backup` is owner-only, RLS enabled, with privileges
revoked from PUBLIC/anon/authenticated. It contains exact full-row snapshots before
and after the merge: definitions, assignments, all relevant normalized/financial
rows, mapping, schema, incoming FKs, constraints, indexes, column/table ACLs, owners,
RLS policies, user triggers and the normalization function definition.
The FK evidence already enumerates all incoming references, including the three
additional tables and their full definitions. Their rows are not backed up or
restored, because 048 never mutates them. DOWN detects additional-FK definition drift
but permits later legitimate survivor references in these tables and preserves them.

UP and DOWN are independent transactional files. Both lock affected tables and
organizations with a 10-second lock timeout and 120-second statement timeout. The
snapshot helper and maps are temporary and removed at completion. No triggers,
RLS policies, authority helpers or FK checks are disabled.

DOWN first compares current affected state to the recorded post-state. Any edited,
added, moved or deleted affected record, category/assignment metadata change,
new FK/index, changed policy/ACL/schema or changed normalization function aborts
rollback without altering data or destroying the ledger. New unrelated records
are preserved. If safe, DOWN removes prevention, restores duplicate definitions,
original reference values and original assignment rows/IDs, verifies exact pre-state
equality, then removes the ledger. It does not infer or guess original values.
Keep the ledger intact while rollback is needed; later affected data edits require
a separately reviewed reconciliation strategy.

## Local evidence

**45 PostgreSQL integration cases passed for the FK inventory fix.** The preceding
048 application change passed 271 Jest tests in 12 suites; application code is
unchanged in this fix, so those tests were not repeated.
All SQL execution for validation was local; remote connections: zero.

The SQL harness uses PGlite 0.5.10 installed only under ignored/untracked scratch:

```powershell
npm install --prefix scratch/category048-db --no-save --package-lock=false --ignore-scripts @electric-sql/pglite@0.5.10
node tests/db/category048.mjs
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests --runTestsByPath tests/services/taxCategories.test.js tests/ui/categoryNames048.test.js tests/ui/settingsRoleContext.test.js tests/ui/operationalWorkspace.test.js tests/ui/moduleExports.test.js tests/ui/operationalGrid.test.js tests/ui/ownerOperationalContext.test.js tests/ui/adminUx01.test.js tests/ui/admin039e.test.js tests/parsers.test.js tests/importCompatibility.test.js tests/reportingExports.test.js
```

SQL cases run actual UP/DOWN and the original creation RPC against a representative
local schema with the supplied IDs/counts and RLS. They cover survivors, all demos,
metadata-preserving collisions, one moved credit/USD record, no dangling FK or
duplicate assignment, canonical global and tenant catalogs, DB duplicate prevention,
distinct types, exact rollback and negative drift cases. JavaScript cases exercise
the real UI handler, lookup/no-insert behavior, concurrent-insert error handling
and normalized-type semantics, plus operational/import/export regressions.

FK inventory fix validation additionally covers acceptance of six FKs, a seventh
FK, a missing/unvalidated/wrong-column FK, subcategory delete-action drift, nonzero
references in each verified-zero table, preservation of their existing source rows,
additional-FK rollback drift, and preservation of post-UP survivor references. The
fixture includes source rows in all three extra tables; exact UP/DOWN comparisons
include them. Their data and schema are never modified by either migration file.

Previously observed broad-suite failures at the base (historical SQL fingerprints
and reporting fake-DOM `root.querySelector`) are outside this change; the complete
broad suite was not rerun or claimed green. Prior SQL and 045/046/047 remain unchanged.
The user's preexisting modified DB test 042 and other workspace artifacts are excluded.

## Manual DEV acceptance (owner applies; agent did not execute remotely)

1. Run the read-only preflight in DEV as migration owner and compare with the supplied
   diagnosis. Review any additional reference notices before proceeding.
2. Apply the complete UP transaction. Verify the query below returns the two exact
   survivors; no explicit duplicate IDs should remain.
3. Verify normalized counts are Honorarios 15 and Telefonía 1, and company assignment
   metadata is preserved. In BAIGORRIA and demo views, check the same canonical IDs.
4. Deploy only after schema verification. Attempt an accented/case/whitespace
   equivalent category in the same type: the app should show the duplicate message
   and leave the global catalog unchanged. Platform view should list each concept once.

```sql
SELECT id,name,category_type,canonical_name_key
FROM public.eco_tax_categories
WHERE category_type='EXPENSE'
  AND canonical_name_key IN ('honorarios profesionales','telefonia')
ORDER BY canonical_name_key;

SELECT category_id,count(*)
FROM public.eco_normalized_records
WHERE category_id IN ('c15675d7-be33-4400-84c3-9985e1a59579','02768384-f366-4fd9-aa0c-a437866cfeb4')
GROUP BY category_id ORDER BY category_id;
```

Ready for manual DEV migration: **YES**, subject to its mandatory preflight.
Ready for DEV application deployment now: **NO**, apply and verify 048 first.
No implementation blockers; a preflight drift rejection is a data-review gate,
not authorization to broaden this explicit merge.
