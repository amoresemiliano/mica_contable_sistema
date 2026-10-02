-- Supabase SQL Editor: run the complete script as postgres on isolated DEV after 035.
-- Existing actors only: no users, grants, or organizations are created/modified as fixtures.
-- Requires an active owner, a catalog-only actor, and two active organizations.
-- All context switches/audit entries roll back. If execution stops on error, ROLLBACK first.
BEGIN;
DO $harness$
DECLARE
  v_candidate RECORD;
  v_owner UUID;
  v_catalog_only UUID;
  v_expected_ids UUID[];
  v_ids UUID[];
  v_inactive UUID;
  v_missing UUID;
  v_org UUID;
  v_snapshot JSONB;
  v_context JSONB;
  v_dataset TEXT;
  v_signature TEXT;
  v_call TEXT;
  v_reader TEXT;
  v_row JSONB;
  v_after UUID;
  v_previous UUID;
  v_page_count INTEGER;
  v_total BIGINT;
  v_expected_count BIGINT;
  v_record_counts BIGINT[] := ARRAY[]::BIGINT[];
  v_financial_counts BIGINT[] := ARRAY[]::BIGINT[];
  v_index INTEGER;
BEGIN
  -- Privileged discovery; helpers honor real grants and DENY overrides.
  FOR v_candidate IN SELECT id, auth_user_id FROM public.eco_user_profiles
    WHERE is_active IS TRUE AND auth_user_id IS NOT NULL ORDER BY id LOOP
    PERFORM set_config('request.jwt.claim.sub', v_candidate.auth_user_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_candidate.auth_user_id, 'role', 'authenticated')::TEXT, true);
    IF private.can_platform('ACCESS_ANY_ORG') THEN
      v_owner := COALESCE(v_owner, v_candidate.auth_user_id);
    ELSIF private.can_platform('CATALOG_ASSIGN_ANY_ORG') THEN
      v_catalog_only := COALESCE(v_catalog_only, v_candidate.auth_user_id);
    END IF;
    EXIT WHEN v_owner IS NOT NULL AND v_catalog_only IS NOT NULL;
  END LOOP;
  IF v_owner IS NULL THEN RAISE EXCEPTION '035 prerequisite: no active ACCESS_ANY_ORG actor'; END IF;
  IF v_catalog_only IS NULL THEN RAISE EXCEPTION '035 prerequisite: no catalog assignment actor without ACCESS_ANY_ORG'; END IF;
  SELECT array_agg(id ORDER BY name, id) INTO v_expected_ids FROM public.eco_organizations WHERE is_active IS TRUE;
  IF COALESCE(cardinality(v_expected_ids), 0) < 2 THEN RAISE EXCEPTION '035 prerequisite: two active organizations required'; END IF;
  SELECT id INTO v_inactive FROM public.eco_organizations WHERE is_active IS NOT TRUE ORDER BY id LIMIT 1;
  LOOP
    v_missing := gen_random_uuid();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = v_missing);
  END LOOP;
  -- Counts under postgres detect omitted rows as well as mixed/duplicate pages.
  FOREACH v_org IN ARRAY v_expected_ids[1:2] LOOP
    SELECT count(*) INTO v_expected_count FROM public.eco_normalized_records WHERE organization_id = v_org AND deleted_at IS NULL;
    v_record_counts := array_append(v_record_counts, v_expected_count);
    SELECT count(*) INTO v_expected_count FROM public.eco_financial_movements WHERE organization_id = v_org AND deleted_at IS NULL;
    v_financial_counts := array_append(v_financial_counts, v_expected_count);
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY[
    'public.list_operational_org_targets()', 'public.switch_superadmin_org_context(uuid)',
    'public.get_my_operational_context()', 'public.get_operational_snapshot(uuid)',
    'public.get_operational_records_page(uuid,uuid,integer)', 'public.get_operational_financials_page(uuid,uuid,integer)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN RAISE EXCEPTION '035 RPC missing: %', v_signature; END IF;
    IF has_function_privilege('anon', v_signature, 'EXECUTE') THEN RAISE EXCEPTION 'anon has EXECUTE on %', v_signature; END IF;
    IF NOT has_function_privilege('authenticated', v_signature, 'EXECUTE') THEN RAISE EXCEPTION 'authenticated lacks EXECUTE on %', v_signature; END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
      WHERE p.oid = v_signature::regprocedure AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'PUBLIC has EXECUTE on %', v_signature;
    END IF;
  END LOOP;

  PERFORM set_config('request.jwt.claim.sub', v_owner::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner, 'role', 'authenticated')::TEXT, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  -- Restricted-role assertions use public RPCs only.
  IF NOT EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(NULL) WHERE code = 'ACCESS_ANY_ORG' AND scope = 'PLATFORM') THEN
    RAISE EXCEPTION 'Owner capability missing at public boundary';
  END IF;
  SELECT array_agg(organization_id ORDER BY organization_name, organization_id) INTO v_ids FROM public.list_operational_org_targets();
  IF v_ids IS DISTINCT FROM v_expected_ids THEN RAISE EXCEPTION 'Targets differ from active organizations'; END IF;
  PERFORM public.switch_superadmin_org_context(NULL);
  v_context := public.get_my_operational_context();
  IF NOT (v_context ? 'organization_id') OR v_context->>'organization_id' IS NOT NULL THEN RAISE EXCEPTION 'Initial Platform context failed'; END IF;
  FOR v_index IN 1..2 LOOP
    v_org := v_ids[v_index];
    PERFORM public.switch_superadmin_org_context(v_org);
    v_context := public.get_my_operational_context();
    IF (v_context->>'organization_id')::UUID IS DISTINCT FROM v_org
      OR NULLIF(v_context->>'organization_name', '') IS NULL
      OR NOT (v_context ? 'profile_name' AND v_context ? 'profile_scope') THEN RAISE EXCEPTION 'Canonical context mismatch'; END IF;
    v_snapshot := public.get_operational_snapshot(v_org);
    IF (v_snapshot->>'organization_id')::UUID IS DISTINCT FROM v_org THEN RAISE EXCEPTION 'Snapshot mismatch'; END IF;
    IF v_snapshot ? 'records' OR v_snapshot ? 'financials' THEN RAISE EXCEPTION 'Historical data in snapshot'; END IF;
    FOREACH v_dataset IN ARRAY ARRAY['categories','activities','rates'] LOOP
      IF jsonb_typeof(v_snapshot->v_dataset) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Missing snapshot dataset %', v_dataset; END IF;
      IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_snapshot->v_dataset) r WHERE (r->>'organization_id')::UUID IS DISTINCT FROM v_org) THEN
        RAISE EXCEPTION 'Mixed tenants in %', v_dataset;
      END IF;
    END LOOP;
    FOREACH v_reader IN ARRAY ARRAY['get_operational_records_page','get_operational_financials_page'] LOOP
      v_after := NULL;
      v_total := 0;
      v_expected_count := CASE WHEN v_reader = 'get_operational_records_page' THEN v_record_counts[v_index] ELSE v_financial_counts[v_index] END;
      LOOP
        v_page_count := 0;
        v_previous := v_after;
        FOR v_row IN EXECUTE format('SELECT * FROM public.%I($1, $2, $3)', v_reader) USING v_org, v_after, 2 LOOP
          IF (v_row->>'organization_id')::UUID IS DISTINCT FROM v_org OR v_row->>'id' IS NULL
            OR (v_previous IS NOT NULL AND (v_row->>'id')::UUID <= v_previous) THEN RAISE EXCEPTION 'Tenant/cursor violation in %', v_reader; END IF;
          v_previous := (v_row->>'id')::UUID;
          v_page_count := v_page_count + 1;
        END LOOP;
        IF v_page_count > 2 THEN RAISE EXCEPTION 'Page limit ignored by %', v_reader; END IF;
        EXIT WHEN v_page_count = 0;
        v_total := v_total + v_page_count;
        IF v_total > v_expected_count THEN RAISE EXCEPTION 'Unexpected/duplicate rows in %', v_reader; END IF;
        v_after := v_previous;
      END LOOP;
      IF v_total <> v_expected_count THEN RAISE EXCEPTION 'Incomplete reader %: % / %', v_reader, v_total, v_expected_count; END IF;
      IF v_total = 0 THEN RAISE NOTICE '%: org % empty; non-empty pagination not exercised', v_reader, v_org; END IF;
      BEGIN
        EXECUTE format('SELECT * FROM public.%I($1, NULL, 501)', v_reader) USING v_org;
        RAISE EXCEPTION 'Unbounded page unexpectedly allowed by %', v_reader;
      EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    END LOOP;
  END LOOP;
  -- Now in the second org: reads for the first must fail even when it is empty.
  FOREACH v_call IN ARRAY ARRAY[
    'SELECT public.get_operational_snapshot($1)', 'SELECT * FROM public.get_operational_records_page($1, NULL, 500)',
    'SELECT * FROM public.get_operational_financials_page($1, NULL, 500)'
  ] LOOP
    BEGIN
      EXECUTE v_call USING v_ids[1];
      RAISE EXCEPTION 'Foreign tenant read unexpectedly allowed: %', v_call;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  FOREACH v_org IN ARRAY ARRAY[v_missing, v_inactive] LOOP
    IF v_org IS NULL THEN RAISE NOTICE 'Inactive-target case skipped: no inactive organization exists; no fixture created'; CONTINUE; END IF;
    BEGIN
      PERFORM public.switch_superadmin_org_context(v_org);
      RAISE EXCEPTION 'Missing/inactive target unexpectedly allowed';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    IF (public.get_my_operational_context()->>'organization_id')::UUID IS DISTINCT FROM v_ids[2] THEN RAISE EXCEPTION 'Rejected switch changed context'; END IF;
  END LOOP;
  PERFORM public.switch_superadmin_org_context(NULL);
  v_context := public.get_my_operational_context();
  IF NOT (v_context ? 'organization_id') OR v_context->>'organization_id' IS NOT NULL THEN RAISE EXCEPTION 'Final Platform context failed'; END IF;
  EXECUTE 'RESET ROLE';

  PERFORM set_config('request.jwt.claim.sub', v_catalog_only::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_catalog_only, 'role', 'authenticated')::TEXT, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(NULL) WHERE code = 'CATALOG_ASSIGN_ANY_ORG' AND scope = 'PLATFORM')
    OR EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(NULL) WHERE code = 'ACCESS_ANY_ORG' AND scope = 'PLATFORM') THEN
    RAISE EXCEPTION 'Catalog-only actor does not meet negative-test precondition';
  END IF;
  BEGIN
    PERFORM public.list_operational_org_targets();
    RAISE EXCEPTION 'Catalog-only user unexpectedly obtained operational targets';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.switch_superadmin_org_context(NULL);
    RAISE EXCEPTION 'Catalog-only user unexpectedly switched context';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';

  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'anon')::TEXT, true);
  EXECUTE 'SET LOCAL ROLE anon';
  FOREACH v_call IN ARRAY ARRAY[
    'SELECT * FROM public.list_operational_org_targets()', 'SELECT public.switch_superadmin_org_context(NULL)',
    'SELECT public.get_my_operational_context()', 'SELECT public.get_operational_snapshot($1)',
    'SELECT * FROM public.get_operational_records_page($1, NULL, 500)', 'SELECT * FROM public.get_operational_financials_page($1, NULL, 500)'
  ] LOOP
    BEGIN
      EXECUTE v_call USING v_ids[1];
      RAISE EXCEPTION 'anon execution unexpectedly allowed: %', v_call;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE '035 passed: owner %, catalog-only %, orgs %; all changes will roll back', v_owner, v_catalog_only, v_ids[1:2];
END;
$harness$;
ROLLBACK;
