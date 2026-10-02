-- ============================================================
-- DB BEHAVIORAL SECURITY TEST SUITE FOR MIGRATION 020 (WP-A2)
-- ============================================================
-- Validates authorization helper evaluation for real target accounts
-- under WP-A2 shadow authorization state.
-- Runs inside transaction (BEGIN ... ROLLBACK) to guarantee zero permanent mutation.

BEGIN;

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

  v_vegen_profile_id     UUID;
  v_marianela_profile_id UUID;
  v_emiliano_profile_id  UUID;
  v_edravi_profile_id    UUID;
  v_calle_profile_id     UUID;

  v_test_mem_id UUID;
BEGIN
  -- 1. Resolve Auth User IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  -- Resolve Profile IDs
  SELECT id INTO v_vegen_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  SELECT id INTO v_marianela_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_marianela_auth_id;
  SELECT id INTO v_emiliano_profile_id  FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;
  SELECT id INTO v_calle_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id;

  IF v_vegen_profile_id IS NULL OR v_marianela_profile_id IS NULL OR v_emiliano_profile_id IS NULL OR v_edravi_profile_id IS NULL OR v_calle_profile_id IS NULL THEN
    RAISE EXCEPTION 'DB Test FAILED: One or more target user profiles could not be resolved.';
  END IF;

  -- ============================================================
  -- POSITIVE ASSERTIONS
  -- ============================================================

  -- 1. vegendigital has expected platform superadmin capability
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  IF NOT private.can_platform('PLATFORM_MANAGE') THEN
    RAISE EXCEPTION 'Test FAILED: vegendigital denied PLATFORM_MANAGE capability';
  END IF;

  -- 2. Marianela has expected accounting platform capability
  PERFORM set_config('request.jwt.claim.sub', v_marianela_auth_id::text, true);
  IF NOT private.can_platform('REPORT_COMPARE_SCOPED_ORGS') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied REPORT_COMPARE_SCOPED_ORGS capability';
  END IF;

  -- 3, 4, 5. Marianela can_org for configured accounting bridge capability in NORTE, SUR, OESTE
  IF NOT private.can_org(v_norte_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied IMPORT_CREATE in DEMO NORTE';
  END IF;
  IF NOT private.can_org(v_sur_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied IMPORT_CREATE in DEMO SUR';
  END IF;
  IF NOT private.can_org(v_oeste_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied IMPORT_CREATE in DEMO OESTE';
  END IF;

  -- 6. Emiliano can_org NORTE for a TENANT_ADMIN capability
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  IF NOT private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano denied ORG_MEMBER_INVITE in DEMO NORTE';
  END IF;

  -- 7. Edravi can_org SUR for a TENANT_ADMIN capability
  PERFORM set_config('request.jwt.claim.sub', v_edravi_auth_id::text, true);
  IF NOT private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Edravi denied ORG_MEMBER_INVITE in DEMO SUR';
  END IF;

  -- 8. Calle can_org OESTE for a TENANT_ADMIN capability
  PERFORM set_config('request.jwt.claim.sub', v_calle_auth_id::text, true);
  IF NOT private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Calle denied ORG_MEMBER_INVITE in DEMO OESTE';
  END IF;


  -- ============================================================
  -- MANDATORY NEGATIVE TESTS
  -- ============================================================

  -- A. TENANT ISOLATION
  -- Emiliano: NORTE TRUE, SUR FALSE, OESTE FALSE
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Emiliano incorrectly granted access to DEMO SUR';
  END IF;
  IF private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Emiliano incorrectly granted access to DEMO OESTE';
  END IF;

  -- Edravi: NORTE FALSE, SUR TRUE, OESTE FALSE
  PERFORM set_config('request.jwt.claim.sub', v_edravi_auth_id::text, true);
  IF private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Edravi incorrectly granted access to DEMO NORTE';
  END IF;
  IF private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Edravi incorrectly granted access to DEMO OESTE';
  END IF;

  -- Calle: NORTE FALSE, SUR FALSE, OESTE TRUE
  PERFORM set_config('request.jwt.claim.sub', v_calle_auth_id::text, true);
  IF private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Calle incorrectly granted access to DEMO NORTE';
  END IF;
  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test A FAILED: Calle incorrectly granted access to DEMO SUR';
  END IF;

  -- B. MARIANELA MEMBERSHIP BOUNDARY
  -- Marianela MUST NOT receive org capabilities for legacy MICA because she has no active membership there
  PERFORM set_config('request.jwt.claim.sub', v_marianela_auth_id::text, true);
  IF private.can_org(v_mica_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Negative Test B FAILED: Marianela granted org capabilities for legacy MICA without membership';
  END IF;

  -- C. PLATFORM PRIVILEGE ESCALATION
  -- Emiliano (TENANT_ADMIN) MUST NOT have ACCOUNTING_SUPERADMIN platform capability
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  IF private.can_platform('REPORT_COMPARE_SCOPED_ORGS') THEN
    RAISE EXCEPTION 'Negative Test C FAILED: Emiliano granted ACCOUNTING_SUPERADMIN platform capability';
  END IF;

  -- D. NULL ROLE TEMPLATE SAFETY
  -- Membership exists + role_template_id IS NULL + no eligible platform-role org bridge -> can_org returns FALSE
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  -- Emiliano has NO platform role bridge. Insert a test membership with NULL template in DEMO SUR.
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_emiliano_profile_id, NULL, TRUE)
  RETURNING id INTO v_test_mem_id;

  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test D FAILED: Membership with NULL role_template_id granted capability without platform bridge';
  END IF;
  DELETE FROM public.eco_organization_members WHERE id = v_test_mem_id;

  -- E. ACTIVE CONTEXT IS NOT AUTHORIZATION
  -- Setting active context to an unauthorized org must NOT make can_org true
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_emiliano_profile_id, v_sur_org_id)
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = v_sur_org_id;

  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test E FAILED: Active context granted org access without membership';
  END IF;

  -- Restore Emiliano active context to NORTE
  UPDATE public.eco_user_active_context SET organization_id = v_norte_org_id WHERE user_profile_id = v_emiliano_profile_id;

  -- F. PLATFORM SUPERADMIN NO TENANT BYPASS
  -- PLATFORM_SUPERADMIN assignment alone must NOT make can_org return TRUE without membership
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  IF private.can_org(v_norte_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Negative Test F FAILED: PLATFORM_SUPERADMIN bypassed can_org without membership';
  END IF;

  -- G. DUPLICATE PROTECTION
  -- Verify UNIQUE(organization_id, user_profile_id) catalog constraint
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid = 'public.eco_organization_members'::regclass
      AND c.contype IN ('u', 'p')
      AND (
        SELECT ARRAY_AGG(attname ORDER BY attname)
        FROM pg_attribute
        WHERE attrelid = c.conrelid AND attnum = ANY(c.conkey)
      ) = ARRAY['organization_id', 'user_profile_id']::name[]
  ) THEN
    RAISE EXCEPTION 'Negative Test G FAILED: Composite UNIQUE(organization_id, user_profile_id) missing on eco_organization_members';
  END IF;

  -- H. LEGACY INVARIANCE
  -- Verify M020 did not alter legacy profile role/organization_id fields
  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_profiles
    WHERE auth_user_id = v_vegen_auth_id AND role = 'SUPERADMIN' AND organization_id IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.eco_user_profiles
    WHERE auth_user_id = v_emiliano_auth_id AND role = 'SUPERADMIN' AND organization_id = v_mica_org_id
  ) THEN
    RAISE EXCEPTION 'Negative Test H FAILED: Legacy profile role or organization_id was mutated';
  END IF;

  RAISE NOTICE 'In-database WP-A2 behavioral security test suite PASSED cleanly.';
END $$;

ROLLBACK;
