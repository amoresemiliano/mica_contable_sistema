-- Verification script for Migration 018 (SUPERADMIN Operational Capability Inheritance)
BEGIN;

-- 1. Check all target RPC definitions for SUPERADMIN authorization
DO $$
DECLARE
  v_procname TEXT;
  v_def TEXT;
  v_target_procs TEXT[] := ARRAY[
    'create_import',
    'persist_import_batch',
    'persist_perceptions_batch',
    'persist_financial_movements_batch',
    'request_failed_import_retry',
    'resolve_issue',
    'soft_delete_normalized_record',
    'restore_normalized_record',
    'soft_delete_financial_movement',
    'restore_financial_movement',
    'update_record_classification',
    'update_movement_classification',
    'bulk_update_record_classification',
    'create_global_tax_category',
    'update_global_tax_category',
    'create_global_economic_activity',
    'update_global_economic_activity',
    'upsert_arca_activity_catalog',
    'create_org_activity_iibb_rate',
    'update_org_activity_iibb_rate'
  ];
BEGIN
  FOREACH v_procname IN ARRAY v_target_procs
  LOOP
    SELECT pg_get_functiondef(oid) INTO v_def
    FROM pg_proc
    WHERE proname = v_procname;

    IF v_def IS NULL THEN
      RAISE EXCEPTION 'Verification FAILED: RPC % does not exist', v_procname;
    END IF;

    IF v_def NOT LIKE '%SUPERADMIN%' THEN
      RAISE EXCEPTION 'Verification FAILED: RPC % does not contain SUPERADMIN authorization', v_procname;
    END IF;
  END LOOP;
END $$;

-- 2. Verify RLS remains enabled on all multitenant tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'eco_normalized_records',
    'eco_financial_movements',
    'eco_source_imports',
    'eco_org_tax_categories',
    'eco_org_economic_activities',
    'eco_org_activity_iibb_rates'
  );

ROLLBACK;
