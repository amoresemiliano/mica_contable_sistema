-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 020 (WP-A2 REAL USER AUTHORIZATION ASSIGNMENTS)
-- ============================================================
-- Read-only verification of M019 baseline foundation, target organizations,
-- required role templates, and target user identity existence before M020.
-- Fails closed with explicit exception if any baseline prerequisite is missing.

DO $$
DECLARE
  v_auth_count INT;
  v_org_count INT;
  v_tpl_count INT;
  v_profile_count INT;
  v_calle_auth_id UUID;
  v_calle_profile_id UUID;
  v_vegen_profile_id UUID;
  v_marianela_profile_id UUID;
  v_emiliano_profile_id UUID;
  v_edravi_profile_id UUID;
BEGIN
  -- 1. Verify M019 capability foundation schema prerequisites
  IF EXISTS (
    SELECT 1 FROM (
      VALUES 
        ('eco_capabilities'),
        ('eco_role_templates'),
        ('eco_role_template_capabilities'),
        ('eco_platform_role_org_capabilities'),
        ('eco_membership_capability_overrides'),
        ('eco_user_platform_role'),
        ('eco_user_platform_capability_overrides'),
        ('eco_user_active_context')
    ) AS req(tablename)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = req.tablename
    )
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more WP-A1 foundation tables are missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_organization_members' AND column_name = 'role_template_id'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: eco_organization_members.role_template_id column is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'current_profile_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'active_org_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'can_platform'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'can_org'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more private authorization helper functions are missing.';
  END IF;

  -- 2. AUTH.USERS privilege preflight (explicit read access check)
  BEGIN
    SELECT COUNT(*) INTO v_auth_count FROM auth.users;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Preflight FAILED: auth.users table is inaccessible or caller lacks SELECT privilege: %', SQLERRM;
  END BEGIN;

  -- 3. Verify target organizations exist with exact names and frozen UUIDs
  SELECT COUNT(*) INTO v_org_count
  FROM public.eco_organizations
  WHERE (id = '38419581-8163-482c-9813-616fa6214d71' AND name = 'DEMO NORTE')
     OR (id = 'c7af5a5c-1aac-4add-9873-8073044bf979' AND name = 'DEMO SUR')
     OR (id = '1f5d071f-a09e-4825-9f12-88533383599e' AND name = 'DEMO OESTE');

  IF v_org_count < 3 THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more target DEV organizations (DEMO NORTE, DEMO SUR, DEMO OESTE) are missing or UUID mismatch.';
  END IF;

  -- 4. Verify required role templates exist and are active
  SELECT COUNT(*) INTO v_tpl_count
  FROM public.eco_role_templates
  WHERE code IN ('PLATFORM_SUPERADMIN', 'ACCOUNTING_SUPERADMIN', 'TENANT_ADMIN')
    AND is_active = TRUE;

  IF v_tpl_count < 3 THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more required role templates (PLATFORM_SUPERADMIN, ACCOUNTING_SUPERADMIN, TENANT_ADMIN) are missing or inactive.';
  END IF;

  -- 5. Verify required auth users exist in auth.users for accounts A, B, C, D
  SELECT COUNT(*) INTO v_profile_count
  FROM auth.users
  WHERE email IN ('vegendigital@gmail.com', 'drcmarianela@gmail.com', 'emilianodirosa1@gmail.com', 'edravi77@gmail.com');

  IF v_profile_count < 4 THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more core target auth.users (vegendigital, drcmarianela, emilianodirosa1, edravi77) are missing.';
  END IF;

  -- 6. Verify profile mappings exist for core target users A, B, C, D
  SELECT COUNT(*) INTO v_profile_count
  FROM public.eco_user_profiles p
  JOIN auth.users u ON u.id = p.auth_user_id
  WHERE u.email IN ('vegendigital@gmail.com', 'drcmarianela@gmail.com', 'emilianodirosa1@gmail.com', 'edravi77@gmail.com')
    AND p.is_active = TRUE;

  IF v_profile_count < 4 THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more core target user profiles (vegendigital, drcmarianela, emilianodirosa1, edravi77) are missing or inactive.';
  END IF;

  -- 7. CALLE PROFILE SPECIAL CASE Verification
  SELECT id INTO v_calle_auth_id
  FROM auth.users
  WHERE email = 'calleelcalvario16@gmail.com';

  IF v_calle_auth_id IS NULL THEN
    RAISE EXCEPTION 'Preflight FAILED: Required user calleelcalvario16@gmail.com does not exist in auth.users (CASE 1 precheck failure).';
  END IF;

  SELECT id INTO v_calle_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_calle_auth_id;

  IF v_calle_profile_id IS NOT NULL THEN
    RAISE NOTICE 'Preflight info: Calle user profile pre-exists (CASE 2).';
  ELSE
    RAISE NOTICE 'Preflight info: Calle user profile will be created during migration using canonical contract (CASE 3).';
  END IF;

  -- 8. Target M020 authorization relationship absence checks (Reversibility Safety Preflight)
  SELECT p.id INTO v_vegen_profile_id     FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'vegendigital@gmail.com';
  SELECT p.id INTO v_marianela_profile_id FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'drcmarianela@gmail.com';
  SELECT p.id INTO v_emiliano_profile_id  FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'emilianodirosa1@gmail.com';
  SELECT p.id INTO v_edravi_profile_id    FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'edravi77@gmail.com';

  -- 8.1 Platform roles absence check
  IF v_vegen_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_user_platform_role pr
    JOIN public.eco_role_templates rt ON rt.id = pr.role_template_id
    WHERE pr.user_profile_id = v_vegen_profile_id AND rt.code = 'PLATFORM_SUPERADMIN'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: vegendigital already has pre-existing PLATFORM_SUPERADMIN platform role row.';
  END IF;

  IF v_marianela_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_user_platform_role pr
    JOIN public.eco_role_templates rt ON rt.id = pr.role_template_id
    WHERE pr.user_profile_id = v_marianela_profile_id AND rt.code = 'ACCOUNTING_SUPERADMIN'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: drcmarianela already has pre-existing ACCOUNTING_SUPERADMIN platform role row.';
  END IF;

  -- 8.2 Target memberships absence check
  IF v_marianela_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_marianela_profile_id
      AND organization_id IN ('38419581-8163-482c-9813-616fa6214d71'::UUID, 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID, '1f5d071f-a09e-4825-9f12-88533383599e'::UUID)
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: drcmarianela already has pre-existing membership in DEMO NORTE, SUR, or OESTE.';
  END IF;

  IF v_emiliano_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_emiliano_profile_id AND organization_id = '38419581-8163-482c-9813-616fa6214d71'::UUID
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: emilianodirosa1 already has pre-existing membership in DEMO NORTE.';
  END IF;

  IF v_edravi_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_edravi_profile_id AND organization_id = 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: edravi77 already has pre-existing membership in DEMO SUR.';
  END IF;

  IF v_calle_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_calle_profile_id AND organization_id = '1f5d071f-a09e-4825-9f12-88533383599e'::UUID
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: calleelcalvario16 already has pre-existing membership in DEMO OESTE.';
  END IF;

  -- 8.3 Active context absence check
  IF EXISTS (
    SELECT 1 FROM public.eco_user_active_context
    WHERE user_profile_id IN (
      v_vegen_profile_id,
      v_marianela_profile_id,
      v_emiliano_profile_id,
      v_edravi_profile_id
    ) OR (v_calle_profile_id IS NOT NULL AND user_profile_id = v_calle_profile_id)
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more target accounts already have a pre-existing active context row.';
  END IF;

  RAISE NOTICE 'Preflight check PASSED for Migration 020 (WP-A2 Real User Authorization Assignments).';
END $$;
