-- Migration 016 Down: Rollback failed import retry support and persistent lineage column
BEGIN;

DROP FUNCTION IF EXISTS public.request_failed_import_retry(UUID);

DROP INDEX IF EXISTS public.idx_eco_source_imports_retry_of;

ALTER TABLE public.eco_source_imports
DROP COLUMN IF EXISTS retry_of_import_id;

COMMIT;
