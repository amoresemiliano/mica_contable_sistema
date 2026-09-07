-- ============================================================
-- MIGRATION 020: WP-A2 REAL USER AUTHORIZATION ASSIGNMENTS
-- ============================================================
-- Assigns real DEV user accounts into WP-A1 shadow authorization model:
--   vegendigital@gmail.com      -> PLATFORM_SUPERADMIN, Active Context: NULL
--   drcmarianela@gmail.com       -> ACCOUNTING_SUPERADMIN, Memberships: NORTE, SUR, OESTE (role_template_id=NULL), Active Context: NORTE
--   emilianodirosa1@gmail.com    -> Memberships: NORTE (TENANT_ADMIN), Active Context: NORTE
--   edravi77@gmail.com           -> Memberships: SUR (TENANT_ADMIN), Active Context: SUR
--   calleelcalvario16@gmail.com  -> Memberships: OESTE (TENANT_ADMIN), Active Context: OESTE
--
-- Pure additive shadow-state. Does not alter legacy profile role/organization_id, RLS, or RPCs.

BEGIN;

DO $$
DECLARE
  -- Organization UUID constants (resolved & frozen from DEV DB evidence)
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;

  -- Role Template IDs
  v_platform_superadmin_tpl_id UUID;
  v_acct_superadmin_tpl_id     UUID;
  v_tenant_admin_tpl_id        UUID;

  -- Auth User IDs
  v_vegen_auth_id     UUID;
  v_marianela_auth_id UUID;
  v_emiliano_auth_id  UUID;
  v_edravi_auth_id    UUID;
  v_calle_auth_id     UUID;

  -- Profile IDs
  v_vegen_profile_id     UUID;
  v_marianela_profile_id UUID;
  v_emiliano_profile_id  UUID;
  v_edravi_profile_id    UUID;
  v_calle_profile_id     UUID;
BEGIN
  -- 1. Resolve Role Template IDs
  SELECT id INTO v_platform_superadmin_tpl_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN' AND is_active = TRUE;
  SELECT id INTO v_acct_superadmin_tpl_id     FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN' AND is_active = TRUE;
  SELECT id INTO v_tenant_admin_tpl_id        FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN' AND is_active = TRUE;

  IF v_platform_superadmin_tpl_id IS NULL OR v_acct_superadmin_tpl_id IS NULL OR v_tenant_admin_tpl_id IS NULL THEN
    RAISE EXCEPTION 'Migration 020 FAILED: One or more required role templates missing or inactive.';
  END IF;

  -- 2. Resolve Auth User IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  IF v_vegen_auth_id IS NULL OR v_marianela_auth_id IS NULL OR v_emiliano_auth_id IS NULL OR v_edravi_auth_id IS NULL OR v_calle_auth_id IS NULL THEN
    RAISE EXCEPTION 'Migration 020 FAILED: One or more target auth.users entries could not be resolved.';
  END IF;

  -- 3. Resolve User Profile IDs
  SELECT id INTO v_vegen_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  SELECT id INTO v_marianela_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_marianela_auth_id;
  SELECT id INTO v_emiliano_profile_id  FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;

  SELECT id INTO v_calle_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id;

  -- CALLE SPECIAL CASE: Create profile if missing (CASE 3) using canonical contract
  IF v_calle_profile_id IS NULL THEN
    INSERT INTO public.eco_user_profiles (auth_user_id, role, is_active)
    VALUES (v_calle_auth_id, 'USER', TRUE)
    RETURNING id INTO v_calle_profile_id;
  END IF;

  IF v_vegen_profile_id IS NULL OR v_marianela_profile_id IS NULL OR v_emiliano_profile_id IS NULL OR v_edravi_profile_id IS NULL OR v_calle_profile_id IS NULL THEN
    RAISE EXCEPTION 'Migration 020 FAILED: One or more target user profiles could not be resolved/created.';
  END IF;

  -- ============================================================
  -- 4. PLATFORM ROLE ASSIGNMENTS
  -- ============================================================
  -- A) vegendigital -> PLATFORM_SUPERADMIN
  INSERT INTO public.eco_user_platform_role (user_profile_id, role_template_id, is_active)
  VALUES (v_vegen_profile_id, v_platform_superadmin_tpl_id, TRUE);

  -- B) drcmarianela -> ACCOUNTING_SUPERADMIN
  INSERT INTO public.eco_user_platform_role (user_profile_id, role_template_id, is_active)
  VALUES (v_marianela_profile_id, v_acct_superadmin_tpl_id, TRUE);


  -- ============================================================
  -- 5. ORGANIZATION MEMBERSHIP ASSIGNMENTS
  -- ============================================================
  -- B) drcmarianela -> DEMO NORTE, SUR, OESTE (role_template_id = NULL)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_marianela_profile_id, NULL, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = NULL, is_active = TRUE;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_marianela_profile_id, NULL, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = NULL, is_active = TRUE;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_oeste_org_id, v_marianela_profile_id, NULL, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = NULL, is_active = TRUE;

  -- C) emilianodirosa1 -> DEMO NORTE ONLY (role_template_id = TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_emiliano_profile_id, v_tenant_admin_tpl_id, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = v_tenant_admin_tpl_id, is_active = TRUE;

  -- D) edravi77 -> DEMO SUR ONLY (role_template_id = TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_edravi_profile_id, v_tenant_admin_tpl_id, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = v_tenant_admin_tpl_id, is_active = TRUE;

  -- E) calleelcalvario16 -> DEMO OESTE ONLY (role_template_id = TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_oeste_org_id, v_calle_profile_id, v_tenant_admin_tpl_id, TRUE)
  ON CONFLICT (organization_id, user_profile_id)
  DO UPDATE SET role_template_id = v_tenant_admin_tpl_id, is_active = TRUE;


  -- ============================================================
  -- 6. ACTIVE CONTEXT ASSIGNMENTS
  -- ============================================================
  -- A) vegendigital -> NULL / GLOBAL
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_vegen_profile_id, NULL)
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = NULL;

  -- B) drcmarianela -> DEMO NORTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_marianela_profile_id, v_norte_org_id)
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = v_norte_org_id;

  -- C) emilianodirosa1 -> DEMO NORTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_emiliano_profile_id, v_norte_org_id)
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = v_norte_org_id;

  -- D) edravi77 -> DEMO SUR
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_edravi_profile_id, v_sur_org_id)
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = v_sur_org_id;

  -- E) calleelcalvario16 -> DEMO OESTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id)
  VALUES (v_calle_profile_id, v_oeste_org_id)
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = v_oeste_org_id;

  RAISE NOTICE 'Migration 020 (WP-A2 Real User Authorization Assignments) APPLIED SUCCESSFULLY.';
END $$;

COMMIT;
