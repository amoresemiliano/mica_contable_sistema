-- ============================================================
-- SMALL CANONICAL AUTHORIZATION MATRIX ACCEPTANCE TEST (023)
-- ============================================================
-- Tests real DEV personas directly under authenticated role simulation.
-- Zero synthetic user setup machinery. Compact, readable (< 200 lines).
--
-- Executes under BEGIN ... ROLLBACK.
--
-- Matrix Assertions:
-- 1. EMILIANO:   eco_organizations SELECT = {DEMO NORTE}
-- 2. EDRAVI:     eco_organizations SELECT = {DEMO SUR}
-- 3. CALLE:      eco_organizations SELECT = {DEMO OESTE}
-- 4. MARIANELA:  eco_organizations SELECT = {DEMO NORTE, DEMO SUR, DEMO OESTE}
-- 5. VEGEN:      eco_organizations SELECT = {} (Platform superadmin has NO implicit tenant visibility)
-- 6. MICA:       Zero tenant visibility for all normal personas
-- 7. Active context manipulation does NOT expand authorized organization visibility
-- 8. Cross-tenant mutation RPC (change_user_role on foreign org) fails with FORBIDDEN/TARGET_NOT_FOUND
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.harness_023_set_persona(p_auth_id UUID) RETURNS void AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'TEST_NOT_RUNNING_AS_AUTHENTICATED (current_user=%)', current_user;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.harness_023_reset_role() RETURNS void AS $$
BEGIN
  EXECUTE 'RESET ROLE';
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;
  v_mica_org_id  CONSTANT UUID := '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID;

  v_vegen_auth_id     UUID;
  v_marianela_auth_id UUID;
  v_emiliano_auth_id  UUID;
  v_edravi_auth_id    UUID;
  v_calle_auth_id     UUID;

  v_emiliano_profile_id UUID;
  v_edravi_profile_id   UUID;

  v_org_count INT;
  v_seen_norte BOOLEAN;
  v_seen_sur BOOLEAN;
  v_seen_oeste BOOLEAN;
  v_seen_mica BOOLEAN;

  v_exception_raised BOOLEAN;
BEGIN
  -- Privileged user resolution
  PERFORM public.harness_023_reset_role();

  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  SELECT id INTO v_emiliano_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id   FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;

  RAISE NOTICE 'Running 023 Canonical Authorization Matrix Acceptance Tests...';

  -- ============================================================
  -- 1. EMILIANO (Tenant Admin NORTE)
  -- ============================================================
  PERFORM public.harness_023_set_persona(v_emiliano_auth_id);

  SELECT COUNT(*),
         bool_or(id = v_norte_org_id),
         bool_or(id = v_sur_org_id),
         bool_or(id = v_oeste_org_id),
         bool_or(id = v_mica_org_id)
  INTO v_org_count, v_seen_norte, v_seen_sur, v_seen_oeste, v_seen_mica
  FROM public.eco_organizations;

  IF v_org_count <> 1 OR v_seen_norte IS NOT TRUE OR v_seen_sur IS TRUE OR v_seen_mica IS TRUE THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Emiliano saw % orgs (norte=%, sur=%, mica=%), expected {NORTE} only',
      v_org_count, v_seen_norte, v_seen_sur, v_seen_mica;
  END IF;

  -- ============================================================
  -- 2. EDRAVI (Tenant Admin SUR)
  -- ============================================================
  PERFORM public.harness_023_set_persona(v_edravi_auth_id);

  SELECT COUNT(*),
         bool_or(id = v_norte_org_id),
         bool_or(id = v_sur_org_id),
         bool_or(id = v_oeste_org_id),
         bool_or(id = v_mica_org_id)
  INTO v_org_count, v_seen_norte, v_seen_sur, v_seen_oeste, v_seen_mica
  FROM public.eco_organizations;

  IF v_org_count <> 1 OR v_seen_sur IS NOT TRUE OR v_seen_norte IS TRUE OR v_seen_mica IS TRUE THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Edravi saw % orgs (sur=%, norte=%, mica=%), expected {SUR} only',
      v_org_count, v_seen_sur, v_seen_norte, v_seen_mica;
  END IF;

  -- ============================================================
  -- 3. CALLE (Tenant Admin OESTE)
  -- ============================================================
  PERFORM public.harness_023_set_persona(v_calle_auth_id);

  SELECT COUNT(*),
         bool_or(id = v_norte_org_id),
         bool_or(id = v_sur_org_id),
         bool_or(id = v_oeste_org_id),
         bool_or(id = v_mica_org_id)
  INTO v_org_count, v_seen_norte, v_seen_sur, v_seen_oeste, v_seen_mica
  FROM public.eco_organizations;

  IF v_org_count <> 1 OR v_seen_oeste IS NOT TRUE OR v_seen_norte IS TRUE OR v_seen_mica IS TRUE THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Calle saw % orgs (oeste=%, norte=%, mica=%), expected {OESTE} only',
      v_org_count, v_seen_oeste, v_seen_norte, v_seen_mica;
  END IF;

  -- ============================================================
  -- 4. MARIANELA (Accounting Superadmin: NORTE, SUR, OESTE)
  -- ============================================================
  PERFORM public.harness_023_set_persona(v_marianela_auth_id);

  SELECT COUNT(*),
         bool_or(id = v_norte_org_id),
         bool_or(id = v_sur_org_id),
         bool_or(id = v_oeste_org_id),
         bool_or(id = v_mica_org_id)
  INTO v_org_count, v_seen_norte, v_seen_sur, v_seen_oeste, v_seen_mica
  FROM public.eco_organizations;

  IF v_org_count <> 3 OR v_seen_norte IS NOT TRUE OR v_seen_sur IS NOT TRUE OR v_seen_oeste IS NOT TRUE OR v_seen_mica IS TRUE THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Marianela saw % orgs (norte=%, sur=%, oeste=%, mica=%), expected {NORTE, SUR, OESTE}',
      v_org_count, v_seen_norte, v_seen_sur, v_seen_oeste, v_seen_mica;
  END IF;

  -- ============================================================
  -- 5. VEGEN (Platform Superadmin: No Tenant Membership)
  -- ============================================================
  PERFORM public.harness_023_set_persona(v_vegen_auth_id);

  SELECT COUNT(*) INTO v_org_count
  FROM public.eco_organizations;

  IF v_org_count <> 0 THEN
    RAISE EXCEPTION 'Matrix Test FAILED: VEGEN saw % orgs, expected 0 (platform role alone must not grant tenant access)', v_org_count;
  END IF;

  -- ============================================================
  -- 6. ACTIVE CONTEXT CANNOT GRANT UNAUTHORIZED ORG ACCESS
  -- ============================================================
  -- Privileged: set Emiliano active context to DEMO SUR
  PERFORM public.harness_023_reset_role();
  UPDATE public.eco_user_active_context
  SET organization_id = v_sur_org_id
  WHERE user_profile_id = v_emiliano_profile_id;

  -- Emiliano as authenticated: must STILL see only NORTE
  PERFORM public.harness_023_set_persona(v_emiliano_auth_id);

  SELECT COUNT(*), bool_or(id = v_norte_org_id), bool_or(id = v_sur_org_id)
  INTO v_org_count, v_seen_norte, v_seen_sur
  FROM public.eco_organizations;

  IF v_org_count <> 1 OR v_seen_norte IS NOT TRUE OR v_seen_sur IS TRUE THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Active context granted unauthorized organization access to Emiliano!';
  END IF;

  -- ============================================================
  -- 7. CROSS-TENANT MUTATION RPC FAILS CLOSED
  -- ============================================================
  -- Emiliano attempts to change role of Edravi in DEMO SUR -> must be rejected
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_edravi_profile_id, 'ACCOUNTANT', v_sur_org_id);
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;

  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Matrix Test FAILED: Emiliano cross-org change_user_role on SUR was not rejected!';
  END IF;

  PERFORM public.harness_023_reset_role();
  RAISE NOTICE '023 Canonical Authorization Matrix Acceptance Test PASSED ALL ASSERTIONS.';
END $$;

ROLLBACK;
