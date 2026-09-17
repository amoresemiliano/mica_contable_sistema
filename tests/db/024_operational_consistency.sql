-- ============================================================
-- DB Test Suite: 024_operational_consistency.sql
-- Work Package: WP-FUNC-1
-- Operational Read/Write Consistency & Pipeline Hardening Tests
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_emiliano_auth_id UUID;
  v_test_cat_id UUID;
  v_test_cat_count INT;
  v_import_id UUID;
  v_file_hash CONSTANT TEXT := '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';
  v_check_res JSONB;
  v_persist_res JSONB;
  v_activity_cnt INT;
  v_fn_def TEXT;
BEGIN
  RAISE NOTICE 'Starting DB Test Suite 024_operational_consistency...';

  -- 1. SETUP AUTHENTICATION CONTEXT (Emiliano - ADMIN)
  SELECT id INTO v_emiliano_auth_id FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  IF v_emiliano_auth_id IS NULL THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: emilianodirosa1@gmail.com auth user not found';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::TEXT, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  -- Set active org context to DEMO NORTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  SELECT id, v_norte_org_id, NOW()
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_emiliano_auth_id
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = v_norte_org_id, updated_at = NOW();

  -- ============================================================
  -- TEST SECTION 1: SALARY & BANK PERSISTENCE CONTRACT (MIGRATION 024 COLUMN NAMES)
  -- ============================================================
  SELECT pg_get_functiondef(oid) INTO v_fn_def 
  FROM pg_proc 
  WHERE proname = 'persist_financial_movements_batch';

  IF v_fn_def !~ 'movement_type' OR v_fn_def !~ 'financial_fingerprint' THEN
    RAISE EXCEPTION 'TEST 1 FAILED: persist_financial_movements_batch does not reference movement_type or financial_fingerprint';
  END IF;

  IF v_fn_def ~ '\btipo\b' AND v_fn_def ~ 'eco_financial_movements' THEN
    RAISE EXCEPTION 'TEST 1 FAILED: persist_financial_movements_batch still contains stale "tipo" column reference';
  END IF;

  RAISE NOTICE 'TEST 1 PASSED: persist_financial_movements_batch correctly references movement_type and financial_fingerprint.';


  -- ============================================================
  -- TEST SECTION 2: FILE IMPORT DEDUPLICATION & RETRY INVARIANT
  -- ============================================================
  -- A. Check file importable for unused hash -> Must be importable
  v_check_res := public.check_file_importable(v_file_hash);
  IF (v_check_res->>'importable')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST 2A FAILED: Clean hash reported as not importable (got %).', v_check_res;
  END IF;

  -- B. Create a dummy import record (0 accepted rows)
  INSERT INTO public.eco_source_imports (
    organization_id, source_type, operation_type, status, accepted_rows
  ) VALUES (
    v_norte_org_id, 'BANK_STATEMENT_BBVA', 'BANCO', 'FAILED', 0
  ) RETURNING id INTO v_import_id;

  INSERT INTO public.eco_source_files (
    import_id, organization_id, original_name, storage_path, mime_type, size_bytes, sha256_hash, source_type
  ) VALUES (
    v_import_id, v_norte_org_id, 'test_bank.csv', 'test/path.csv', 'text/csv', 1024, v_file_hash, 'BANK_STATEMENT_BBVA'
  );

  -- C. Check file importable for hash linked to failed/0-accepted import -> MUST STILL BE IMPORTABLE!
  v_check_res := public.check_file_importable(v_file_hash);
  IF (v_check_res->>'importable')::BOOLEAN IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST 2B FAILED: Failed/0-accepted import hash blocked re-import (got %).', v_check_res;
  END IF;

  -- D. Update import record to set status = COMPLETED with 0 accepted rows (e.g. duplicate-only import)
  UPDATE public.eco_source_imports SET accepted_rows = 0, status = 'COMPLETED' WHERE id = v_import_id;

  -- E. Check file importable -> MUST BE BLOCKED because import completed successfully
  v_check_res := public.check_file_importable(v_file_hash);
  IF (v_check_res->>'importable')::BOOLEAN IS TRUE THEN
    RAISE EXCEPTION 'TEST 2C FAILED: Completed duplicate-only import file hash (status = COMPLETED) was NOT blocked.';
  END IF;

  RAISE NOTICE 'TEST 2 PASSED: File deduplication and retry invariant verified.';


  -- ============================================================
  -- TEST SECTION 3: CATEGORY CREATE & TENANT ASSIGNMENT CONTRACT
  -- ============================================================
  -- 1. Create global category
  v_test_cat_id := public.create_global_tax_category(
    'TEST_CAT_024_' || LEFT(gen_random_uuid()::TEXT, 8),
    'Test Category 024 Description',
    'EXPENSE'
  );

  IF v_test_cat_id IS NULL THEN
    RAISE EXCEPTION 'TEST 3A FAILED: create_global_tax_category returned NULL';
  END IF;

  -- 2. Assign category to org using normal tenant active-context path (p_target_org_id = NULL)
  PERFORM public.assign_tax_category_to_org(v_test_cat_id, NULL, NULL);

  -- 3. Verify category is returned in Org Mode read query
  SELECT COUNT(*) INTO v_test_cat_count
  FROM public.eco_org_tax_categories
  WHERE organization_id = v_norte_org_id AND category_id = v_test_cat_id AND is_active = TRUE;

  IF v_test_cat_count != 1 THEN
    RAISE EXCEPTION 'TEST 3B FAILED: Organization tax category assignment not found (count = %).', v_test_cat_count;
  END IF;

  RAISE NOTICE 'TEST 3 PASSED: Category global creation and tenant assignment contract verified.';


  -- ============================================================
  -- TEST SECTION 4: ECONOMIC ACTIVITIES IMPORT COUNT CONTRACT
  -- ============================================================
  v_activity_cnt := public.upsert_arca_activity_catalog(jsonb_build_array(
    jsonb_build_object('arca_code', 'TEST_ACT_024_A', 'name', 'Test Activity 024 A', 'description', 'Desc A'),
    jsonb_build_object('arca_code', 'TEST_ACT_024_B', 'name', 'Test Activity 024 B', 'description', 'Desc B')
  ));

  IF v_activity_cnt != 2 THEN
    RAISE EXCEPTION 'TEST 4 FAILED: upsert_arca_activity_catalog expected 2, got %', v_activity_cnt;
  END IF;

  RAISE NOTICE 'TEST 4 PASSED: ARCA activity catalog upsert returned DB-confirmed count 2.';

  RAISE NOTICE '============================================================';
  RAISE NOTICE 'ALL DB TESTS IN 024_operational_consistency.sql PASSED!';
  RAISE NOTICE '============================================================';
END $$;

ROLLBACK;
