# Import compatibility and resumable batches

DEV-IMPORT-COMPATIBILITY-01 is implemented and statically verified on `dev`, based on `8b2bfb3ef2e098af57cc6f47df04d1d2218e13ba`. Migration 043 is prepared for manual DEV application. Database execution and deployment remain pending. PROD was not accessed. Migration 042 and the existing uncommitted 042 harness change are outside this commit.

## Content detection and format contracts

Binary signatures take precedence. An XLSX signature also requires the OOXML package filenames; arbitrary ZIPs do not qualify. SheetJS still validates workbook structure. Text dispatch uses a structural registry, with delimited contracts checked before fixed-width contracts. Extensions do not select perception parsers. Unknown text is rejected.

A textual Excel mismatch requires a known perception contract and at least 80% normalized rows. The UI displays a compatibility warning and retains it in staging warnings. Existing delimited exports retain quoted commas, escaped quotes, multiline values, optional `sep=` directives and physical source lines. Windows-1252 text is decoded when UTF-8 produces replacement characters. Sheet extraction attaches physical source numbers while retaining its existing omission of blank rows.

Offsets below are zero based, with the right boundary excluded. The contracts come from all supplied records; identifiers in committed fixtures are artificial.

| Family | Contract |
|---|---|
| Rentas quoted text XLS | `sep=,`, CUIT, perception date, perceived amount and base headers; 11 fields, optionally an empty trailing twelfth field. Mapping follows headers. |
| IVA positional CSV | Eight semicolon fields: CUIT at 2, ISO date at 4, reference at 6, decimal amount at 7. No first-row loss. Audit retains regime, operation and document type codes. |
| SIFERE compact | 51 characters: jurisdiction/regime 0:3, formatted CUIT 3:16, date 16:26, reference 26:38, marker 38:39, document type 39:40, amount 40:51. Reference may contain spaces. **Document type is never included in the amount.** |
| Rentas complete | 65 characters: CUIT 0:11, reference 11:19 (may start with a space), date YYYYMMDD 19:27, code 27:31, base 31:47, amount 47:63, marker 63:65. Both independent samples use this parser. |
| Retention fixed | 90 characters: code 0:5, formatted CUIT 5:18, date 18:28, section 28:32, reference 32:53, operation marker 53:54, space 54:55, additional reference 55:74, amount 74:90. Normalized `tipo=retencion`; marker and references remain in audit. |
| Existing ARBA | Existing 70-character parser remains available through structural recognition. |
| IVA headered | Existing OLE2/OOXML/delimited header mapping retains tax/operation audit and identifiable retention semantics, including hydration. |
| English bank header | RELEASE_DATE, TRANSACTION_TYPE, REFERENCE_ID, TRANSACTION_NET_AMOUNT, PARTIAL_BALANCE. Summary block is skipped. DD-MM-YYYY becomes ISO; sign determines debit/credit. Existing Spanish and BBVA date representations remain unchanged. |

Perception dates normalize to calendar-checked DD/MM/YYYY. Decimal points, decimal commas and Argentine thousands separators are supported. Malformed records enter staging with raw data, source row, errors and warnings; structurally incompatible files and files with zero valid rows cannot proceed through the UI.

New provincial families use the existing `PERCEPCIONES_ARBA` persistence source type, while `normalized_payload` retains their real source/jurisdiction/type metadata. No new fiscal source types or changes to fiscal-document persistence were introduced. Canonical server identity validation remains in place.

## Local real file evidence

Eighteen real files were read locally. Original files, business identifiers, customer names, references, descriptions and monetary evidence are excluded from this commit. A masked local report, including first/last normalized records, source lines, dates, amounts, balances and types, is retained at `.local-data/import-compat-evidence/reports.json`.

“Records” excludes headers, directives and summary rows. Invalid records remain staged, rather than counted as imported movements.

| Evidence | Physical rows | Records | Valid | Invalid |
|---|---:|---:|---:|---:|
| Quoted text XLS | 134 | 131 | 131 | 0 |
| SIFERE compact | 131 | 131 | 131 | 0 |
| Rentas complete primary | 131 | 131 | 131 | 0 |
| Rentas complete independent | 18 | 18 | 18 | 0 |
| Retention fixed | 3 | 3 | 3 | 0 |
| IVA semicolon | 15 | 15 | 15 | 0 |
| English bank with summary | 49 | 45 | 45 | 0 |
| IVA XLS sample A | 6 | 5 | 5 | 0 |
| IVA XLS sample B | 7 | 6 | 6 | 0 |
| IVA XLS sample C | 3 | 2 | 2 | 0 |
| IVA XLS with invalid source rows | 81 | 80 | 73 | 7 |
| Comafi | 67 | 66 | 66 | 0 |
| Additional English bank | 183 | 179 | 179 | 0 |
| Nación | 58 | 44 | 44 | 0 |
| Galicia | 33 | 32 | 32 | 0 |
| Bapro | 1,083 | 1,081 | 1,081 | 0 |
| Macro | 46 | 38 | 35 | 3 |
| Supervielle | 521 | 520 | 520 | 0 |

All 131 CUIT/date/amount tuples agree across the quoted, compact and complete exports. Every retention, independent complete, positional CSV and English bank date/amount was compared to its source fields. Existing bank normalized payloads/errors match the base commit; existing IVA valid CUIT/date/amount tuples also match. The Macro invalid rows and seven invalid IVA records are preserved from baseline behavior. SheetJS emits ZIP size warnings for the original English workbook but reads the transaction table successfully.

## Why a migration is required

Both canonical persistence RPCs cap each batch at 500 rows. Repeating them was unsafe: they finalize each call, replace counters instead of accumulating them, and the existing source-file reuse helper rejects the same import. The perception RPC also requires PENDING status. Increasing the limit or simply looping those RPCs would violate the partial failure requirement.

`sql/043_resumable_import_chunks.sql` adds a shared authenticated `persist_import_chunk` contract and `get_resumable_import` lookup. Its preflight pins both existing canonical function bodies and their owner/security/search-path properties. Private workers reuse those exact row validators through explicit scoped substitutions. Private tables/helpers remain inaccessible to authenticated callers.

Files with at most 500 rows keep their existing RPC. Larger perception and financial files use sequential chunks of at most 500, one import ID, one source-file record and one immutable manifest. Receipt hashes make exact replay idempotent; changed payloads, overlapping source lines, changed metadata, wrong order, wrong organization and wrong creator are rejected. Legacy endpoints reject attempts to write a chunk-managed import.

Each chunk and its receipt commit together. Aggregate counters remain visible as PROCESSING with no completion timestamp until the final chunk. A failed chunk rolls back only that request, preserving earlier receipts and audit evidence. Reselecting the same file obtains the original envelope and stored metadata; all chunks can be replayed safely. A lost response preserves the uploaded source because the request may have committed. A completed file follows the existing duplicate-file path.

Rollback restores the guarded public endpoints only when their installed definitions match and every chunk-managed import is complete. It preserves receipts/progress as private archives and never deletes business records. Incomplete imports must be resumed before rollback. Reinstallation after archival requires explicit review.

## Verification and DEV gates

The full local suite recorded **755 passing tests and 9 historical hash failures** across 67 suites. All mismatched historical SQL bytes also exist in the base commit: 009, 016 and the 018 up/down files. None was changed here. After final targeted changes, **187 tests passed across 10 focused suites**, including both persistence paths at 1/499/500/501/1000/1001, partial failure, receipt replay, lost final response and retention hydration.

PostgreSQL parsing passed for migration, rollback, harness, all PL/pgSQL blocks and both transformed canonical workers. `git diff --check` passed. These checks do not establish DEV database runtime behavior.

1. Manually apply `sql/043_resumable_import_chunks.sql` in DEV. Stop if the embedded preflight reports drift; do not remove its hash/authorization checks.
2. Run `tests/db/043_resumable_import_chunks.sql` in DEV as the privileged harness owner. It calls public contracts under authenticated, tests both pipelines and all six sizes, injects a rollback-only failure inside the second chunk, checks retry/isolation/identity/counters and ends with ROLLBACK.
3. Confirm privileges with this read-only query:

```sql
SELECT
 has_schema_privilege('authenticated','private','USAGE') AS must_be_false,
 has_function_privilege('authenticated','public.persist_import_chunk(uuid,jsonb,jsonb,text,integer,integer)','EXECUTE') AS must_be_true,
 has_function_privilege('authenticated','public.get_resumable_import(text)','EXECUTE') AS must_be_true,
 has_function_privilege('authenticated','private.persist_financial_chunk_rows(uuid,jsonb,jsonb)','EXECUTE') AS worker_must_be_false;
```

4. On a separately authorized DEV application deployment, preview the seven principal format families and the 1,081/520-row banks. Confirm physical source lines, signs and totals. Interrupt a large upload after its first acknowledged chunk, reselect the source, and confirm one import/file identity and final aggregate counts without duplicate movements.

Ready for manual DEV migration: YES. Ready for DEV deployment: NO, pending migration application and runtime harness acceptance. No deployment or remote SQL was performed.
