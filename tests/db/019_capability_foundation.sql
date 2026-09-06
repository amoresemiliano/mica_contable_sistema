-- Verification script for Migration 019 (WP-A1 Capability Foundation)
BEGIN;

-- 1. Verify Schema Structures
DO $$
DECLARE
  v_count INT;
BEGIN
  -- Tables check
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_capabilities') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_role_templates') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_role_template_capabilities') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_platform_role_org_capabilities') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_membership_capability_overrides') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_user_platform_role') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_user_platform_capability_overrides') OR
     NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'eco_user_active_context') THEN
    RAISE EXCEPTION 'DB Verification FAILED: Foundation tables missing';
  END IF;

  -- Columns check
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'eco_organization_members' AND column_name = 'role_template_id'
  ) THEN
    RAISE EXCEPTION 'DB Verification FAILED: role_template_id missing from eco_organization_members';
  END IF;

  -- Exact composite UNIQUE(organization_id, user_profile_id) check
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'public.eco_organization_members'::regclass
      AND c.contype IN ('u', 'p')
      AND (
        SELECT ARRAY_AGG(attname ORDER BY attname)
        FROM pg_attribute
        WHERE attrelid = c.conrelid
          AND attnum = ANY(c.conkey)
      ) = ARRAY['organization_id', 'user_profile_id']::name[]
  ) THEN
    RAISE EXCEPTION 'DB Verification FAILED: Composite UNIQUE(organization_id, user_profile_id) missing on eco_organization_members';
  END IF;

  -- Seed counts check
  SELECT COUNT(*) INTO v_count FROM public.eco_capabilities;
  IF v_count < 42 THEN
    RAISE EXCEPTION 'DB Verification FAILED: Expected at least 42 capabilities, got %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_role_templates;
  IF v_count < 8 THEN
    RAISE EXCEPTION 'DB Verification FAILED: Expected at least 8 role templates, got %', v_count;
  END IF;
END $$;

-- 2. Behavioral Verification of Authorization Helpers (In-Transaction Fixtures)
DO $$
DECLARE
  v_org_id UUID;
  v_user_auth_id UUID := '00000000-0000-0000-0000-000000000001'::UUID;
  v_profile_id UUID;
  v_membership_id UUID;
  v_platform_superadmin_template_id UUID;
  v_acct_superadmin_template_id UUID;
  v_accountant_template_id UUID;
  v_uploader_template_id UUID;
  v_cap_import_create_id UUID;
  v_cap_org_settings_manage_id UUID;
  v_res BOOLEAN;
BEGIN
  -- Fetch template IDs
  SELECT id INTO v_platform_superadmin_template_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN';
  SELECT id INTO v_acct_superadmin_template_id FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN';
  SELECT id INTO v_accountant_template_id FROM public.eco_role_templates WHERE code = 'ACCOUNTANT';
  SELECT id INTO v_uploader_template_id FROM public.eco_role_templates WHERE code = 'UPLOADER';

  SELECT id INTO v_cap_import_create_id FROM public.eco_capabilities WHERE code = 'IMPORT_CREATE';
  SELECT id INTO v_cap_org_settings_manage_id FROM public.eco_capabilities WHERE code = 'ORG_SETTINGS_MANAGE';

  -- Create isolated test org
  INSERT INTO public.eco_organizations (id, name)
  VALUES ('11111111-1111-1111-1111-111111111111'::UUID, 'WP-A1 TEST ORG')
  RETURNING id INTO v_org_id;

  -- Create test profile using real schema columns
  INSERT INTO public.eco_user_profiles (id, auth_user_id, role, is_active)
  VALUES ('22222222-2222-2222-2222-222222222222'::UUID, v_user_auth_id, 'USER', TRUE)
  RETURNING id INTO v_profile_id;

  -- MANDATORY NEGATIVE TEST 1 & 12: Profile with no new authorization assignment fails closed
  -- Simulation: Test helper logic under profile context
  PERFORM set_config('request.jwt.claim.sub', v_user_auth_id::text, true);

  -- Assert current_profile_id resolves correctly
  IF private.current_profile_id() != v_profile_id THEN
    RAISE EXCEPTION 'Test FAILED: current_profile_id failed to resolve test profile';
  END IF;

  -- Assert fail closed for user with no assignments
  IF private.can_platform('PLATFORM_MANAGE') THEN
    RAISE EXCEPTION 'Test FAILED: User without platform role granted platform capability';
  END IF;
  IF private.can_org(v_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: User without membership granted org capability';
  END IF;

  -- MANDATORY NEGATIVE TEST 7 & 8: Active context without membership grants nothing
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_profile_id, v_org_id);

  IF private.can_org(v_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: Active context granted org access without membership';
  END IF;

  -- MANDATORY NEGATIVE TEST 8: ACCOUNTING_SUPERADMIN without membership grants no org access
  INSERT INTO public.eco_user_platform_role (user_profile_id, role_template_id, is_active)
  VALUES (v_profile_id, v_acct_superadmin_template_id, TRUE);

  IF NOT private.can_platform('REPORT_COMPARE_SCOPED_ORGS') THEN
    RAISE EXCEPTION 'Test FAILED: ACCOUNTING_SUPERADMIN denied platform capability';
  END IF;
  IF private.can_org(v_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: ACCOUNTING_SUPERADMIN without membership granted org access';
  END IF;

  -- MANDATORY NEGATIVE TEST 9: ACCOUNTING_SUPERADMIN with membership receives only configured bridge capabilities
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, is_active)
  VALUES (v_org_id, v_profile_id, TRUE)
  RETURNING id INTO v_membership_id;

  -- Bridge capability IMPORT_CREATE should now be TRUE
  IF NOT private.can_org(v_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: ACCOUNTING_SUPERADMIN with membership denied bridge capability IMPORT_CREATE';
  END IF;

  -- Non-bridge capability ORG_SETTINGS_MANAGE should be FALSE
  IF private.can_org(v_org_id, 'ORG_SETTINGS_MANAGE') THEN
    RAISE EXCEPTION 'Test FAILED: ACCOUNTING_SUPERADMIN granted unconfigured org capability ORG_SETTINGS_MANAGE';
  END IF;

  -- MANDATORY NEGATIVE TEST 10: Membership DENY overrides base ALLOW
  INSERT INTO public.eco_membership_capability_overrides (membership_id, capability_id, effect)
  VALUES (v_membership_id, v_cap_import_create_id, 'DENY');

  IF private.can_org(v_org_id, 'IMPORT_CREATE') THEN
    RAISE EXCEPTION 'Test FAILED: Membership DENY override failed to override base ALLOW';
  END IF;

  -- MANDATORY NEGATIVE TEST 11: Membership ALLOW grants capability absent from template
  INSERT INTO public.eco_membership_capability_overrides (membership_id, capability_id, effect)
  VALUES (v_membership_id, v_cap_org_settings_manage_id, 'ALLOW');

  IF NOT private.can_org(v_org_id, 'ORG_SETTINGS_MANAGE') THEN
    RAISE EXCEPTION 'Test FAILED: Membership ALLOW override failed to grant omitted capability';
  END IF;

  -- MANDATORY NEGATIVE TEST 14: FK ON DELETE SET NULL test on active context
  -- Delete test membership records first so org deletion is not blocked by membership FK
  IF v_membership_id IS NOT NULL THEN
    DELETE FROM public.eco_membership_capability_overrides WHERE membership_id = v_membership_id;
    DELETE FROM public.eco_organization_members WHERE id = v_membership_id;
  END IF;

  DELETE FROM public.eco_organizations WHERE id = v_org_id;

  IF EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_profile_id AND organization_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Test FAILED: Active context organization_id was not set to NULL on org deletion';
  END IF;

  RAISE NOTICE 'In-database behavioral security tests PASSED cleanly.';
END $$;

ROLLBACK;
