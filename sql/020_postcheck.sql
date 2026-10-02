-- ============================================================
-- POSTCHECK FOR MIGRATION 020 (WP-A2 REAL USER AUTHORIZATION ASSIGNMENTS)
-- ============================================================
-- Read-only verification that M020 platform roles, memberships, and active context
-- assignments are completely created without altering legacy authorization state.

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;

  v_platform_superadmin_tpl_id UUID;
  v_acct_superadmin_tpl_id     UUID;
  v_tenant_admin_tpl_id        UUID;

  v_vegen_profile_id     UUID;
  v_marianela_profile_id UUID;
  v_emiliano_profile_id  UUID;
  v_edravi_profile_id    UUID;
  v_calle_profile_id     UUID;

  v_count INT;
BEGIN
  -- 1. Resolve Profile IDs
  SELECT p.id INTO v_vegen_profile_id     FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'vegendigital@gmail.com';
  SELECT p.id INTO v_marianela_profile_id FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'drcmarianela@gmail.com';
  SELECT p.id INTO v_emiliano_profile_id  FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'emilianodirosa1@gmail.com';
  SELECT p.id INTO v_edravi_profile_id    FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'edravi77@gmail.com';
  SELECT p.id INTO v_calle_profile_id     FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'calleelcalvario16@gmail.com';

  IF v_vegen_profile_id IS NULL OR v_marianela_profile_id IS NULL OR v_emiliano_profile_id IS NULL OR v_edravi_profile_id IS NULL OR v_calle_profile_id IS NULL THEN
    RAISE EXCEPTION 'Postcheck FAILED: One or more target user profiles are missing.';
  END IF;

  -- 2. Verify Platform Role Assignments
  SELECT id INTO v_platform_superadmin_tpl_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN';
  SELECT id INTO v_acct_superadmin_tpl_id     FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN';
  SELECT id INTO v_tenant_admin_tpl_id        FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN';

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_platform_role
    WHERE user_profile_id = v_vegen_profile_id AND role_template_id = v_platform_superadmin_tpl_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: vegendigital is missing PLATFORM_SUPERADMIN platform role.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_platform_role
    WHERE user_profile_id = v_marianela_profile_id AND role_template_id = v_acct_superadmin_tpl_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Marianela is missing ACCOUNTING_SUPERADMIN platform role.';
  END IF;

  -- 3. Verify Memberships
  -- Marianela: NORTE, SUR, OESTE (role_template_id IS NULL)
  SELECT COUNT(*) INTO v_count
  FROM public.eco_organization_members
  WHERE user_profile_id = v_marianela_profile_id
    AND organization_id IN (v_norte_org_id, v_sur_org_id, v_oeste_org_id)
    AND role_template_id IS NULL
    AND is_active = TRUE;

  IF v_count != 3 THEN
    RAISE EXCEPTION 'Postcheck FAILED: Marianela is missing required bridge memberships in DEMO NORTE, SUR, OESTE with role_template_id NULL.';
  END IF;

  -- Emiliano: NORTE (TENANT_ADMIN)
  IF NOT EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_emiliano_profile_id AND organization_id = v_norte_org_id AND role_template_id = v_tenant_admin_tpl_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Emiliano is missing TENANT_ADMIN membership in DEMO NORTE.';
  END IF;

  -- Edravi: SUR (TENANT_ADMIN)
  IF NOT EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_edravi_profile_id AND organization_id = v_sur_org_id AND role_template_id = v_tenant_admin_tpl_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Edravi is missing TENANT_ADMIN membership in DEMO SUR.';
  END IF;

  -- Calle: OESTE (TENANT_ADMIN)
  IF NOT EXISTS (
    SELECT 1 FROM public.eco_organization_members
    WHERE user_profile_id = v_calle_profile_id AND organization_id = v_oeste_org_id AND role_template_id = v_tenant_admin_tpl_id AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Calle is missing TENANT_ADMIN membership in DEMO OESTE.';
  END IF;

  -- 4. Verify Active Context Assignments
  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_vegen_profile_id AND organization_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: vegendigital active context is NOT NULL/GLOBAL.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_marianela_profile_id AND organization_id = v_norte_org_id
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Marianela active context is NOT DEMO NORTE.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_emiliano_profile_id AND organization_id = v_norte_org_id
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Emiliano active context is NOT DEMO NORTE.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_edravi_profile_id AND organization_id = v_sur_org_id
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Edravi active context is NOT DEMO SUR.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id = v_calle_profile_id AND organization_id = v_oeste_org_id
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: Calle active context is NOT DEMO OESTE.';
  END IF;

  RAISE NOTICE 'Postcheck PASSED for Migration 020 (WP-A2 Real User Authorization Assignments). All target accounts verified.';
END $$;
