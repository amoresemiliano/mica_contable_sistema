# 044 perception canonical file reuse

Status: IMPLEMENTED; runtime verification pending. No SQL executed, deployment, or PROD access.

The failing statement is the unconditional `IF EXISTS (SELECT 1 FROM public.eco_source_files WHERE import_id = p_import_id)` followed by `RAISE EXCEPTION 'File already registered for import %', p_import_id` in the perception worker. Its canonical source is `sql/039c_functional_stabilization.sql`, perception metadata section. Chunk 0 inserts a file; chunk 1 reaches this guard and fails before the reuse helper. The lookup has no org predicate, but widening/scoping that lookup would not fix same-import rejection.

043 renamed the worker, substituted `reuse_039c_file` with `reuse_import_chunk_file`, renamed its completion audit event, and admitted PROCESSING. It did not remove the earlier guard. This is case A: a separate legacy guard remains before reuse, rather than unconditional insertion after reuse (B). The insertion is already conditional on the helper returning NULL. The legacy helper authorizes explicit failed-import retries; the chunk helper instead authorizes an active org/hash manifest, locks the hash, and rejects files belonging to another import (E). The status change is necessary but does not bypass the file guard (D).

Financial is unaffected by this defect: its canonical worker has no unconditional import-file guard, admits PROCESSING already, and inserts only when the helper returns NULL. 044 changes only the perception worker, removing exactly one guard. Public authorization, creator checks, manifest equality, receipts, sequence checks, source trace, aggregate finalization, 500-row cap, and all private ACLs remain in place. CREATE OR REPLACE preserves the worker's owner and ACL. No grants are added.

Repository inspection explains the reported error and determines the intended repair; it cannot prove installed DEV definitions equal repository expectations. `sql/044_preflight_readonly.sql` returns function definitions and body hashes only. 044 independently pins normalized body hashes for both workers, the chunk helper, and both chunk RPCs, plus owner/security-definer/search_path checks, and aborts on drift. Worker hashes reproduce the exact 043 transformations of the canonical bodies pinned by 043.

Manual DEV checks, as privileged migration/harness owner:

1. Run `sql/044_preflight_readonly.sql`; compare returned hashes with 044 preflight. Investigate any mismatch; do not bypass pins or rerun 043.
2. Apply `sql/044_fix_resumable_perception_file_reuse.sql` once. No deployment is needed for this private function replacement.
3. Run `tests/db/043_resumable_import_chunks.sql`. Both kinds retain 1/499/500/501/1000/1001 cases, canonical file identity checks for every chunk/replay, injected second-chunk failure/resume, final one-file counts, metadata and foreign-import hash rejection, and cross-org rejection. Public calls use authenticated; internal counts use harness owner; final ROLLBACK removes fixtures.
4. If rollback is needed, use `sql/044_fix_resumable_perception_file_reuse_down.sql`. It checks installed-definition drift and refuses incomplete imports. It restores the defective 043 worker without deleting import data; rolling back removes this repair.

The harness already had local visibility/owner-count corrections when this task began; these were preserved. This task adds metadata mutation and same-hash/different-import negative cases. No historical 043 migration changes were made. Runtime assertions are prepared, not reported as passed.
