-- ============================================================
-- POSTCHECK FOR MIGRATION 018 (SUPERADMIN OPERATIONAL CAPABILITIES)
-- ============================================================
-- Inspects updated RPC definitions to verify SUPERADMIN capability expansion
-- without weakening tenant isolation (private.org_id() IS NOT NULL check).

DO $$
DECLARE
  v_def TEXT;
BEGIN
  -- 1. Check create_import
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'create_import';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: create_import does not include SUPERADMIN role';
  END IF;
  IF v_def NOT LIKE '%v_org_id IS NULL%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: create_import does not check v_org_id IS NULL';
  END IF;

  -- 2. Check persist_import_batch
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_import_batch';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch does not include SUPERADMIN role';
  END IF;
  IF v_def NOT LIKE '%v_org_id IS NULL%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_import_batch does not check v_org_id IS NULL';
  END IF;

  -- 3. Check persist_perceptions_batch
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_perceptions_batch';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_perceptions_batch does not include SUPERADMIN role';
  END IF;

  -- 4. Check persist_financial_movements_batch
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'persist_financial_movements_batch';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: persist_financial_movements_batch does not include SUPERADMIN role';
  END IF;

  -- 5. Check request_failed_import_retry
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'request_failed_import_retry';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: request_failed_import_retry does not include SUPERADMIN role';
  END IF;

  -- 6. Check resolve_issue
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'resolve_issue';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: resolve_issue does not include SUPERADMIN role';
  END IF;

  -- 7. Check upsert_arca_activity_catalog
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname = 'upsert_arca_activity_catalog';
  IF v_def NOT LIKE '%SUPERADMIN%' THEN
    RAISE EXCEPTION 'Postcheck FAILED: upsert_arca_activity_catalog does not include SUPERADMIN role';
  END IF;

  RAISE NOTICE 'Postcheck PASSED for Migration 018.';
END $$;

-- Verify RLS remain enabled on all tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('eco_normalized_records', 'eco_financial_movements', 'eco_source_imports', 'eco_org_tax_categories', 'eco_org_economic_activities', 'eco_org_activity_iibb_rates');
