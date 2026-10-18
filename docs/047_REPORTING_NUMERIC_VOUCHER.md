# 047 — Reporting numeric precision and voucher signs

Status: prepared for manual DEV migration; no SQL execution, deployment or PROD access.
Base: `64a7a36165f976b80f279bc0d72b11f475585bd0`.

## Evidence and scope

`arcaParser.js` emits JavaScript numbers. It sums VAT bases or subtracts IVA,
exempt, non-taxable and other amounts from total to obtain net. These operations
can produce the supplied binary floating-point tails. It accepts `parseInt(tipo)`
without a closed voucher catalog. Acceptance by the importer therefore does not
establish reporting sign semantics.

039c rounds typed monetary columns and fingerprint components to two decimals,
but also persists the original normalized JSON. The 045 projection reparses net
and IVA from that JSON using a six-decimal limit. This rejects the supplied
historical values even though their typed totals/import status may be valid.
046 changes currency projection only and deliberately retains that helper.

047 leaves installed 045/046, source JSON, imports, parser, RPCs, calculation
engine, saved reports and currency policy unchanged. Only the fiscal branch of
the live reporting view uses two new private helpers. Payroll/manual branches
continue using their original helper; this repair does not broaden their inputs.

## Numeric contract

`reporting_047_number(text)` accepts only an optional minus, 1–13 integer digits,
and an optional decimal point with 1–24 fractional digits. The fractional bound
covers the supplied JavaScript artifacts while keeping casting bounded. Absolute
raw magnitude must be at most 9,999,999,999,999.99. This retains the existing
13-integer-digit contract while ensuring each parsed value fits safe integer
cents; the engine's existing sum overflow checks remain in force.

The helper casts to exact PostgreSQL NUMERIC inside a regex-guarded CASE, checks
magnitude before rounding, then applies `round(value,2)`: nearest cent, with ties
away from zero. Net is the sum of the individually rounded canonical components.
Signs retain the original sign × absolute component convention. Nothing writes
the rounded values back to sources. Null, malformed, NaN, Infinity, exponents,
locale separators, spaces, plus signs and over-limit values return NULL.

## Complete supported sign table

The single runtime table lives in `private.reporting_047_voucher_sign(text)`.
The following is its complete supported set, not an exhaustive ARCA catalog.

| Family | Positive | Negative |
| --- | --- | --- |
| A invoice / debit / credit | 1, 2 | 3 |
| B invoice / debit / credit | 6, 7 | 8 |
| C invoice / debit / credit | 11, 12 | 13 |
| C receipt | 15 | — |
| Public utility settlement A | 17 | — |
| Fiscal-controller invoice ticket A | 81 | — |
| Electronic credit invoice A | 201, 202 | 203 |
| Electronic credit invoice B | 206, 207 | 208 |
| Electronic credit invoice C | 211, 212 | 213 |

Authoritative audit: [ARCA Libro IVA Digital, table 3](https://www.afip.gob.ar/iva/documentos/Libro-IVA-Digital-Tablas-del-Sistema.pdf)
identifies 15/17/81 as receipt C, utility settlement A and invoice ticket A.
[ARCA document semantics](https://serviciosweb.afip.gob.ar/facturacion/comprobantes/tipos.asp)
recognizes professional/service receipts as transaction documents, alongside
invoices and tickets. [ARCA's explicit sum/subtract table](https://www.afip.gob.ar/canasta-alimentaria/documentos/Tipos-de-comprobantes-de-ventas.pdf)
assigns positive signs to 15, 17 and 81 (verified in the search-indexed official
PDF text; direct PDF retrieval was unavailable). Together these support positive
reporting treatment; their occurrence in DEV alone was not used as evidence.

The parser can accept every integer, so further fall-through is unavoidable.
The ARCA catalog also lists export documents (19–22), M documents (51–59),
other tickets (82/83/109–120), receipts, sector settlements and equivalent
documents. They are deliberately outside this narrowly scoped repair's
supported set. In particular, no default-positive policy applies to those or
unknown codes. A future expansion requires an explicit sign/transaction audit.
Unknown signs propagate NULL to invoice net, taxable, VAT and amount and remain
materially incomplete. No leading-zero or malformed code coercion is added;
the canonical parser stores integer codes.

## Total zero and field independence

A typed invoice total of zero with any valid nonzero canonical net, exempt,
non-taxable, IVA or other-tax component projects amount=NULL. Its independently
valid net/taxable/VAT remain usable. No total is reconstructed. A genuinely
all-zero document keeps its zero amount. Malformed net or VAT stays NULL rather
than being replaced by zero. The supplied type-17 row projects net 238,071.98,
taxable 227,598.63, VAT 61,451.63 and unavailable amount.

Existing RPC flags and calculation dependencies are already field-specific.
`missing_amount` continues to surface as a source anomaly, but does not block
purchase net or invoice VAT. Missing material net, VAT, currency/configuration
still blocks the dependent report's review/close. USD remains excluded from ARS
and no exchange conversion is introduced.

## Migration and rollback

047 requires 045 objects and a complete installed 046 marker. It pins all seven
original reporting function bodies/security and compares the installed view to
a frozen 046 view deparsed by the same PostgreSQL instance. It rejects existing
047 markers/helpers, unexpected 046 backup metadata and security drift.
Existing function definitions/ACLs and relation owner/ACL/options/RLS are
captured and asserted unchanged. New helpers are postgres-owned, invoker,
immutable, empty-search-path, with no PUBLIC/anon/authenticated grants.

The 047 backup saves the exact pre-047 deparsed view, view identity/security and
the installed helper definitions/security. Rollback refuses drift, restores and
verifies that exact saved view, then drops only the two new helpers and its
marker, without CASCADE. The 046 marker remains intact, allowing its original
rollback contract after 047 is rolled back. Both scripts are transactional.

## Verification and manual acceptance

Local tests validate the extracted SQL numeric grammar/table against exact
decimal reference vectors and inspect migration/rollback scope. Model/service
tests consume independently specified expected RPC projections. These checks
do not execute the SQL helper or migration and cannot establish DEV runtime
success. Apply 047 manually to DEV only after review; no deploy is needed for
this projection-only repair. Then verify:

1. The eight supplied floating-tail values resolve to their expected cents.
2. Type 15/17/81 are positive; known credit notes remain negative; unknown codes
   still have unavailable net/VAT.
3. The supplied zero-total row has net 238,071.98 and IVA 61,451.63, while amount
   is unavailable; net/IVA contribute independently.
4. ARS purchase inclusion rises above 115 toward 137. Exact recovery of all 22
   cannot be certified from the supplied examples alone; USD and genuinely
   incomplete rows retain exclusions. Material incompleteness still blocks close.
5. Roll back 047 in a controlled DEV test and confirm the exact 046 projection
   returns, then reapply before acceptance. No stored report should change.

SQL: `sql/047_reporting_numeric_voucher.sql` and
`sql/047_reporting_numeric_voucher_down.sql`.

Local validation: focused reporting suites passed (103 tests before the final
installed-file hash regression; the final 047-only suite passed all 49 tests).
Full `tests` run: 875 passed, 9 failed. The failures are existing historical SQL
byte-hash manifest mismatches, unchanged from the preceding 046 baseline.
SQL parsing passed for 32 statements, four PL/pgSQL blocks and both SQL helper
bodies. `git diff --check` passed. These are local/static results, not DEV SQL
runtime verification.
