-- Migration 016 Down: Rollback operational read contracts & retry support
BEGIN;

DROP FUNCTION IF EXISTS public.reprocess_failed_import(UUID);
DROP FUNCTION IF EXISTS public.get_active_economic_activities();
DROP FUNCTION IF EXISTS public.get_active_tax_categories();

COMMIT;
