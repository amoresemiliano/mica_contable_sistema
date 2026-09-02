-- Migration 016 Down: Rollback failed import retry support
BEGIN;

DROP FUNCTION IF EXISTS public.request_failed_import_retry(UUID);

COMMIT;
