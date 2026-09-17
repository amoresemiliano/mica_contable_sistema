-- ============================================================
-- DB Test Suite: 025_operational_consistency_wp_func_2.sql
-- Work Package: WP-FUNC-2
-- Operational Identity, Persistence & CRUD Consistency Verification
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_emiliano_auth_id UUID;
  v_import_id UUID;
  v_file_hash CONSTANT TEXT := '99887766554433221100aabbccddeeff99887766554433221100aabbccddeeff';
  v_staged_rows JSONB;
  v_persist_res JSONB;
  v_mvmt_count INT;
  v_row_id UUID;
  v_fn_def TEXT;
BEGIN
  RAISE NOTICE 'Starting DB Test Suite 025_operational_consistency_wp_func_2...';

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
  -- TEST SECTION 1: persist_financial_movements_batch ROW_ID CONTRACT
  -- ============================================================
  SELECT pg_get_functiondef(oid) INTO v_fn_def 
  FROM pg_proc 
  WHERE proname = 'persist_financial_movements_batch';

  IF v_fn_def !~ 'RETURNING id INTO v_row_id' THEN
    RAISE EXCEPTION 'TEST 1 FAILED: persist_financial_movements_batch does not populate v_row_id from eco_import_rows first';
  END IF;

  RAISE NOTICE 'TEST 1 PASSED: persist_financial_movements_batch row_id contract verified in SQL definition.';


  -- ============================================================
  -- TEST SECTION 2: BANK STATEMENT PERSISTENCE & READBACK CONTRACT
  -- ============================================================
  INSERT INTO public.eco_source_imports (
    organization_id, source_type, operation_type, status, accepted_rows
  ) VALUES (
    v_norte_org_id, 'BANK_STATEMENT_BBVA', 'BANCO', 'PENDING', 0
  ) RETURNING id INTO v_import_id;

  v_staged_rows := jsonb_build_array(
    jsonb_build_object(
      'sourceRowNumber', 1,
      'rawRow', jsonb_build_object('fecha', '15/09/2026', 'descripcion', 'DEBITO DIRECTO IMPUESTOS', 'monto', '-1500.50'),
      'normalizedData', jsonb_build_object(
        'fecha', '15/09/2026',
        'fechaValor', '15/09/2026',
        'descripcion', 'DEBITO DIRECTO IMPUESTOS',
        'monto', '-1500.50',
        'tipo', 'DEBITO',
        'referencia', 'REF123456',
        'accountIdentifier', 'ACC001'
      )
    )
  );

  v_persist_res := public.persist_financial_movements_batch(
    v_import_id,
    jsonb_build_object(
      'sha256_hash', v_file_hash,
      'original_name', 'extracto_test.csv',
      'size_bytes', 512,
      'mime_type', 'text/csv',
      'storage_path', 'test/extracto_test.csv'
    ),
    v_staged_rows
  );

  IF (v_persist_res->>'accepted_rows')::INT != 1 THEN
    RAISE EXCEPTION 'TEST 2A FAILED: Expected 1 accepted row, got %', v_persist_res;
  END IF;

  SELECT COUNT(*) INTO v_mvmt_count
  FROM public.eco_financial_movements
  WHERE organization_id = v_norte_org_id AND import_id = v_import_id AND row_id IS NOT NULL;

  IF v_mvmt_count != 1 THEN
    RAISE EXCEPTION 'TEST 2B FAILED: Financial movement record with NOT NULL row_id not found (count = %).', v_mvmt_count;
  END IF;

  RAISE NOTICE 'TEST 2 PASSED: Bank statement persistence and row_id contract verified.';


  -- ============================================================
  -- TEST SECTION 3: SOFT DELETE & RESTORE RPC AUTHORIZATION CONTRACT
  -- ============================================================
  SELECT row_id INTO v_row_id
  FROM public.eco_financial_movements
  WHERE import_id = v_import_id LIMIT 1;

  PERFORM public.soft_delete_financial_movement(
    (SELECT id FROM public.eco_financial_movements WHERE import_id = v_import_id LIMIT 1)
  );

  SELECT COUNT(*) INTO v_mvmt_count
  FROM public.get_active_financial_movements();

  IF v_mvmt_count != 0 THEN
    RAISE EXCEPTION 'TEST 3 FAILED: Soft-deleted financial movement still returned by get_active_financial_movements (count = %).', v_mvmt_count;
  END IF;

  RAISE NOTICE 'TEST 3 PASSED: Soft delete financial movement contract verified.';

  RAISE NOTICE '============================================================';
  RAISE NOTICE 'ALL DB TESTS IN 025_operational_consistency_wp_func_2.sql PASSED!';
  RAISE NOTICE '============================================================';
END $$;

ROLLBACK;
