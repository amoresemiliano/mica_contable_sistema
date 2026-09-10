-- ============================================================
-- DB BEHAVIORAL SECURITY & BENCHMARK SUITE FOR WP-A3.2.0 (MIGRATION 021)
-- ============================================================
-- Tests real user matrix, negative isolation, synthetic override fixtures,
-- and set-based authorization join primitives under a transaction.
-- All changes are rolled back at the end of the test.
-- ============================================================

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

  -- Synthetic fixture variables
  v_synth_auth_id     UUID := gen_random_uuid();
  v_synth_profile_id  UUID;
  v_synth_mem_a_id    UUID;
  v_synth_mem_b_id    UUID;
  v_synth_inactive_mem_id UUID;
  v_uploader_tpl_id   UUID;
  v_tenant_admin_tpl_id UUID;
  v_cap_import_create_id UUID;
  v_cap_org_invite_id    UUID;
  v_cap_record_view_id   UUID;
  v_count_authorized_orgs INT;
BEGIN
  -- 1. Resolve Auth User IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  -- Resolve Templates & Capabilities
  SELECT id INTO v_uploader_tpl_id FROM public.eco_role_templates WHERE code = 'UPLOADER';
  SELECT id INTO v_tenant_admin_tpl_id FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN';
  SELECT id INTO v_cap_import_create_id FROM public.eco_capabilities WHERE code = 'IMPORT_CREATE';
  SELECT id INTO v_cap_org_invite_id FROM public.eco_capabilities WHERE code = 'ORG_MEMBER_INVITE';
  SELECT id INTO v_cap_record_view_id FROM public.eco_capabilities WHERE code = 'RECORD_VIEW';

  -- ============================================================
  -- 1. REAL USER BASELINE TESTS
  -- ============================================================

  -- VEGEN (Platform Superadmin, no tenant membership)
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  IF NOT private.can_platform('PLATFORM_MANAGE') THEN
    RAISE EXCEPTION 'Test FAILED: VEGEN denied PLATFORM_MANAGE';
  END IF;
  IF private.can_org(v_norte_org_id, 'ORG_VIEW') THEN
    RAISE EXCEPTION 'Negative Test FAILED: VEGEN granted tenant can_org without active membership';
  END IF;

  -- Marianela (Accounting Superadmin bridge in NORTE, SUR, OESTE; no MICA)
  PERFORM set_config('request.jwt.claim.sub', v_marianela_auth_id::text, true);
  IF NOT private.can_org(v_norte_org_id, 'RECORD_VIEW') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied RECORD_VIEW in NORTE';
  END IF;
  IF NOT private.can_org(v_sur_org_id, 'RECORD_VIEW') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied RECORD_VIEW in SUR';
  END IF;
  IF NOT private.can_org(v_oeste_org_id, 'RECORD_VIEW') THEN
    RAISE EXCEPTION 'Test FAILED: Marianela denied RECORD_VIEW in OESTE';
  END IF;
  IF private.can_org(v_mica_org_id, 'RECORD_VIEW') THEN
    RAISE EXCEPTION 'Negative Test FAILED: Marianela granted RECORD_VIEW in legacy MICA without membership';
  END IF;

  -- Emiliano (NORTE only)
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  IF NOT private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano denied ORG_MEMBER_INVITE in NORTE';
  END IF;
  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') OR private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test FAILED: Emiliano granted access to unassigned tenant';
  END IF;

  -- Edravi (SUR only)
  PERFORM set_config('request.jwt.claim.sub', v_edravi_auth_id::text, true);
  IF NOT private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Edravi denied ORG_MEMBER_INVITE in SUR';
  END IF;
  IF private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') OR private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test FAILED: Edravi granted access to unassigned tenant';
  END IF;

  -- Calle (OESTE only)
  PERFORM set_config('request.jwt.claim.sub', v_calle_auth_id::text, true);
  IF NOT private.can_org(v_oeste_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Test FAILED: Calle denied ORG_MEMBER_INVITE in OESTE';
  END IF;
  IF private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') OR private.can_org(v_sur_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Negative Test FAILED: Calle granted access to unassigned tenant';
  END IF;


  -- ============================================================
  -- 2. SYNTHETIC FIXTURE TESTS (OVERRIDE PRECEDENCE & ISOLATION)
  -- ============================================================

  -- Create synthetic auth user in auth.users to satisfy foreign key constraint
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) VALUES (
    v_synth_auth_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'synthetic_test_wp_a320_' || v_synth_auth_id::text || '@mica.test',
    'fake_encrypted_password',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

  -- Resolve auto-created profile generated by the auth.users trigger
  SELECT id INTO v_synth_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_auth_id;

  IF v_synth_profile_id IS NULL THEN
    RAISE EXCEPTION 'Synthetic Test Error: eco_user_profiles row was not automatically created for auth.users id %', v_synth_auth_id;
  END IF;

  -- Ensure synthetic profile is active
  UPDATE public.eco_user_profiles
  SET is_active = TRUE
  WHERE id = v_synth_profile_id;

  -- A. BASE_DENY + OVERRIDE_ALLOW:
  -- Assign UPLOADER role in Org NORTE (UPLOADER does not have ORG_MEMBER_INVITE).
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_synth_profile_id, v_uploader_tpl_id, TRUE)
  RETURNING id INTO v_synth_mem_a_id;

  PERFORM set_config('request.jwt.claim.sub', v_synth_auth_id::text, true);

  -- Baseline: must be FALSE without override
  IF private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Synthetic Test Error: UPLOADER unexpectedly has ORG_MEMBER_INVITE base grant';
  END IF;

  -- Add explicit ALLOW override
  INSERT INTO public.eco_membership_capability_overrides (membership_id, capability_id, effect)
  VALUES (v_synth_mem_a_id, v_cap_org_invite_id, 'ALLOW');

  -- Verify: ALLOW override grants capability absent from template
  IF NOT private.can_org(v_norte_org_id, 'ORG_MEMBER_INVITE') THEN
    RAISE EXCEPTION 'Synthetic Test FAILED: ALLOW override failed to grant absent capability';
  END IF;

  -- B. BASE_ALLOW + OVERRIDE_DENY:
  -- UPLOADER naturally has IMPORT_CREATE. Add explicit DENY override for IMPORT_CREATE.
  INSERT INTO public.eco_membership_capability_overrides (membership_id, capability_id, effect)
  VALUES (v_synth_mem_a_id, v_cap_import_create_id, 'DENY');

  -- Verify: DENY override removes base capability
  IF private.can_org(v_norte_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Synthetic Test FAILED: DENY override failed to revoke base capability';
  END IF;

  -- C. CROSS_ORG_OVERRIDE_ISOLATION:
  -- Same synthetic user also belongs to Org SUR as UPLOADER with NO overrides.
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_synth_profile_id, v_uploader_tpl_id, TRUE)
  RETURNING id INTO v_synth_mem_b_id;

  -- Verify Org NORTE (has DENY for IMPORT_CREATE) -> FALSE
  IF private.can_org(v_norte_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Synthetic Test FAILED: Org NORTE did not respect DENY override';
  END IF;

  -- Verify Org SUR (standard UPLOADER, no override) -> TRUE
  IF NOT private.can_org(v_sur_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Synthetic Test FAILED: DENY override leaked across tenant boundary into Org SUR';
  END IF;

  -- D. INACTIVE MEMBERSHIP TEST
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_oeste_org_id, v_synth_profile_id, v_tenant_admin_tpl_id, FALSE)
  RETURNING id INTO v_synth_inactive_mem_id;

  IF private.can_org(v_oeste_org_id, 'RECORD_VIEW') THEN
    RAISE EXCEPTION 'Synthetic Test FAILED: Inactive membership granted authorization';
  END IF;


  -- ============================================================
  -- 3. SET-BASED AUTHORIZATION HELPER VERIFICATION
  -- ============================================================

  -- Test private.authorized_orgs_for_capability with Marianela (accounting bridge)
  PERFORM set_config('request.jwt.claim.sub', v_marianela_auth_id::text, true);
  SELECT COUNT(*) INTO v_count_authorized_orgs
  FROM private.authorized_orgs_for_capability('RECORD_VIEW');

  IF v_count_authorized_orgs <> 3 THEN
    RAISE EXCEPTION 'Set Helper Test FAILED: Marianela expected 3 authorized orgs for RECORD_VIEW, got %', v_count_authorized_orgs;
  END IF;

  -- Test private.authorized_orgs_for_capability with Emiliano
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  SELECT COUNT(*) INTO v_count_authorized_orgs
  FROM private.authorized_orgs_for_capability('ORG_MEMBER_INVITE');

  IF v_count_authorized_orgs <> 1 THEN
    RAISE EXCEPTION 'Set Helper Test FAILED: Emiliano expected 1 authorized org for ORG_MEMBER_INVITE, got %', v_count_authorized_orgs;
  END IF;

  RAISE NOTICE 'All DB behavioral, synthetic override, and set-based authorization tests passed successfully.';
END $$;

ROLLBACK;
