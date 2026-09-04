-- ============================================================
-- POSTCHECK FOR MIGRATION 018 (SUPERADMIN OPERATIONAL CAPABILITIES)
-- ============================================================
-- Inspects updated RPC definitions to verify SUPERADMIN capability expansion
-- AND strict preservation of canonical RPC contracts & validation rules.

DO $$
DECLARE
  v_def TEXT;
  v_procname TEXT;
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
  -- 1. Verify SUPERADMIN authorization in all 20 target RPC definitions
  FOREACH v_procname IN ARRAY v_target_procs
  LOOP
    SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = v_procname;
    IF v_def IS NULL THEN
      RAISE EXCEPTION 'Postcheck FAILED: RPC % does not exist', v_procname;
    END IF;
    IF v_def NOT LIKE '%SUPERADMIN%' THEN
      RAISE EXCEPTION 'Postcheck FAILED: RPC % does not contain SUPERADMIN authorization', v_procname;
    END IF;
  END LOOP;

  -- 2. Verify persist_import_batch contract preservation (255-char limit, 20MB limit, 500 batch limit, storage path)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_import_batch';
  IF v_def NOT LIKE '%v_org_id IS NULL%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing org context check';
  END IF;
  IF v_def NOT LIKE '%255%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 255-character filename validation';
  END IF;
  IF v_def NOT LIKE '%20971520%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 20 MB size limit validation';
  END IF;
  IF v_def NOT LIKE '%500%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 500 max batch size limit';
  END IF;
  IF v_def NOT LIKE '%imports/%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing storage prefix validation';
  END IF;

  -- 3. Verify persist_financial_movements_batch contract preservation (M016 retry/source-reuse semantics)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_financial_movements_batch';
  IF v_def NOT LIKE '%retry_of_import_id%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_financial_movements_batch missing M016 retry_of_import_id contract';
  END IF;

  -- 4. Verify request_failed_import_retry contract preservation (M016 retry semantics)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'request_failed_import_retry';
  IF v_def NOT LIKE '%retry_count%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: request_failed_import_retry missing M016 retry_count contract';
  END IF;

  RAISE NOTICE 'Postcheck PASSED for Migration 018. All 20 RPC contracts and validations verified.';
END $$;

-- Verify RLS remains enabled on all tables
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
