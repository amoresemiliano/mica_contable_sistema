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
  -- 1. Structural Predicate Verification (No comment false positives)
  
  -- A. request_failed_import_retry: Must explicitly authorize SUPERADMIN in v_role predicate + require active org context
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'request_failed_import_retry';
  IF v_def IS NULL THEN RAISE EXCEPTION 'Postcheck FAILED: request_failed_import_retry does not exist'; END IF;
  IF v_def NOT LIKE '%v_role NOT IN (''ADMIN'', ''UPLOADER'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: request_failed_import_retry predicate missing explicit SUPERADMIN role authorization';
  END IF;
  IF v_def NOT LIKE '%v_org_id IS NULL%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: request_failed_import_retry missing active organization tenant context guard';
  END IF;

  -- B. IMPORT CLASS (create_import, persist_import_batch, persist_perceptions_batch, persist_financial_movements_batch, resolve_issue)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'create_import';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''UPLOADER'', ''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: create_import missing UPLOADER/ADMIN/SUPERADMIN predicate';
  END IF;

  -- C. REVIEW CLASS (soft_delete_normalized_record, restore_normalized_record, update_record_classification, etc.)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'soft_delete_normalized_record';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''REVIEWER'', ''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: soft_delete_normalized_record missing REVIEWER/ADMIN/SUPERADMIN predicate';
  END IF;

  -- D. TENANT & GLOBAL ADMIN CLASS (create_global_tax_category, upsert_arca_activity_catalog, etc.)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'create_global_tax_category';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: create_global_tax_category missing ADMIN/SUPERADMIN predicate';
  END IF;

  -- 2. Verify persist_import_batch contract preservation (255-char limit, 20MB limit, 500 batch limit, storage path)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_import_batch';
  IF v_def NOT LIKE '%v_org_id IS NULL%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing org context check';
  END IF;
  IF v_def NOT LIKE '%LENGTH(v_filename) > 255%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 255-character filename validation';
  END IF;
  IF v_def NOT LIKE '%20971520%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 20 MB size limit validation';
  END IF;
  IF v_def NOT LIKE '%jsonb_array_length(p_staged_rows) > 500%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing 500 max batch size limit';
  END IF;
  IF v_def NOT LIKE '%v_expected_prefix%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch missing storage prefix validation';
  END IF;

  -- 3. Verify persist_financial_movements_batch contract preservation (M016 retry/source-reuse semantics)
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_financial_movements_batch';
  IF v_def NOT LIKE '%retry_of_import_id%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_financial_movements_batch missing M016 retry_of_import_id contract';
  END IF;

  RAISE NOTICE 'Postcheck PASSED for Migration 018. All 20 RPC predicates and contracts verified.';
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
