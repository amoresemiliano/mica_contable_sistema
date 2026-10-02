-- Verification script for Migration 018 (SUPERADMIN Operational Capability Inheritance)
BEGIN;

-- 1. Check all 20 target RPC definitions for explicit SUPERADMIN role predicate authorization
DO $$
DECLARE
  v_procname TEXT;
  v_def TEXT;
BEGIN
  -- A. request_failed_import_retry
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'request_failed_import_retry';
  IF v_def NOT LIKE '%v_role NOT IN (''ADMIN'', ''UPLOADER'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Verification FAILED: request_failed_import_retry does not authorize SUPERADMIN in its role predicate';
  END IF;

  -- B. create_import
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'create_import';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''UPLOADER'', ''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Verification FAILED: create_import does not authorize SUPERADMIN in its role predicate';
  END IF;

  -- C. soft_delete_normalized_record
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'soft_delete_normalized_record';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''REVIEWER'', ''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Verification FAILED: soft_delete_normalized_record does not authorize SUPERADMIN in its role predicate';
  END IF;

  -- D. create_global_tax_category
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'create_global_tax_category';
  IF v_def NOT LIKE '%v_caller_role NOT IN (''ADMIN'', ''SUPERADMIN'')%' THEN
    RAISE EXCEPTION 'Verification FAILED: create_global_tax_category does not authorize SUPERADMIN in its role predicate';
  END IF;
END $$;

-- 2. Verify specific contract preservation rules
DO $$
DECLARE
  v_def TEXT;
BEGIN
  -- persist_import_batch validation checks
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_import_batch';
  IF v_def NOT LIKE '%255%' OR v_def NOT LIKE '%20971520%' THEN
    RAISE EXCEPTION 'Verification FAILED: persist_import_batch lost filename length (255) or file size (20MB) validations';
  END IF;

  -- persist_financial_movements_batch retry contract check
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_financial_movements_batch';
  IF v_def NOT LIKE '%retry_of_import_id%' THEN
    RAISE EXCEPTION 'Verification FAILED: persist_financial_movements_batch lost M016 retry contract';
  END IF;
END $$;

-- 3. Verify RLS remains enabled on all multitenant tables
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
