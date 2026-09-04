-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 018 (SUPERADMIN OPERATIONAL CAPABILITIES)
-- ============================================================
-- Read-only verification. Fails closed with explicit exception if missing contracts.

DO $$
BEGIN
  -- 1. Verify M017 is installed (switch_superadmin_org_context exists)
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'public' AND p.proname = 'switch_superadmin_org_context'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Migration 017 RPC switch_superadmin_org_context does not exist.';
  END IF;

  -- 2. Verify private schema support functions exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'private' AND p.proname = 'org_id'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function private.org_id() does not exist.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'private' AND p.proname = 'func_role'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function private.func_role() does not exist.';
  END IF;

  -- 3. Verify auth.uid() function contract
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'auth' AND p.proname = 'uid'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function auth.uid() does not exist.';
  END IF;

  -- 4. Verify RLS is enabled on multitenant tables
  IF EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN ('eco_normalized_records', 'eco_financial_movements', 'eco_source_imports', 'eco_org_tax_categories', 'eco_org_economic_activities', 'eco_org_activity_iibb_rates')
      AND rowsecurity = FALSE
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: RLS is disabled on one or more required multitenant tables.';
  END IF;

  RAISE NOTICE 'Preflight check PASSED for Migration 018.';
END $$;

-- Informational RPC signature inspection
SELECT
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'create_import',
    'persist_import_batch',
    'persist_perceptions_batch',
    'persist_financial_movements_batch',
    'request_failed_import_retry',
    'resolve_issue',
    'create_global_tax_category',
    'upsert_arca_activity_catalog'
  )
ORDER BY p.proname;
