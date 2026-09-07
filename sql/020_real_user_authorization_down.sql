-- ============================================================
-- ROLLBACK MIGRATION 020: WP-A2 REAL USER AUTHORIZATION ASSIGNMENTS
-- ============================================================
-- Reverses WP-A2 shadow authorization assignments for the 5 target DEV users:
--   1. Removes platform role assignments created by M020 for vegendigital & Marianela.
--   2. Removes DEV org memberships created by M020 (DEMO NORTE, SUR, OESTE).
--      Preserves legacy MICA memberships untouched.
--   3. Removes active context assignments for the 5 target profiles.
--   4. Retains Calle profile identity (IDENTITY_PROFILE_RETENTION = SAFE_NON_AUTHORIZATION_STATE).
--
-- Safety note: Reversibility safety depends on 020_preflight_check.sql proving that all
-- target M020 authorization rows (platform roles, memberships, active context) were absent
-- prior to M020 execution.

BEGIN;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;

  v_platform_superadmin_tpl_id UUID;
  v_acct_superadmin_tpl_id     UUID;

  v_vegen_profile_id     UUID;
  v_marianela_profile_id UUID;
  v_emiliano_profile_id  UUID;
  v_edravi_profile_id    UUID;
  v_calle_profile_id     UUID;
BEGIN
  -- 1. Resolve Profile IDs via auth.users email lookup
  SELECT p.id INTO v_vegen_profile_id     FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'vegendigital@gmail.com';
  SELECT p.id INTO v_marianela_profile_id FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'drcmarianela@gmail.com';
  SELECT p.id INTO v_emiliano_profile_id  FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'emilianodirosa1@gmail.com';
  SELECT p.id INTO v_edravi_profile_id    FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'edravi77@gmail.com';
  SELECT p.id INTO v_calle_profile_id     FROM public.eco_user_profiles p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'calleelcalvario16@gmail.com';

  -- 2. Remove M020 active context assignments
  DELETE FROM public.eco_user_active_context
  WHERE user_profile_id IN (
    v_vegen_profile_id,
    v_marianela_profile_id,
    v_emiliano_profile_id,
    v_edravi_profile_id,
    v_calle_profile_id
  );

  -- 3. Remove M020 DEV org memberships (DEMO NORTE, SUR, OESTE)
  DELETE FROM public.eco_organization_members
  WHERE organization_id IN (v_norte_org_id, v_sur_org_id, v_oeste_org_id)
    AND user_profile_id IN (
      v_marianela_profile_id,
      v_emiliano_profile_id,
      v_edravi_profile_id,
      v_calle_profile_id
    );

  -- 4. Remove M020 platform role assignments
  SELECT id INTO v_platform_superadmin_tpl_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN';
  SELECT id INTO v_acct_superadmin_tpl_id     FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN';

  IF v_vegen_profile_id IS NOT NULL AND v_platform_superadmin_tpl_id IS NOT NULL THEN
    DELETE FROM public.eco_user_platform_role
    WHERE user_profile_id = v_vegen_profile_id AND role_template_id = v_platform_superadmin_tpl_id;
  END IF;

  IF v_marianela_profile_id IS NOT NULL AND v_acct_superadmin_tpl_id IS NOT NULL THEN
    DELETE FROM public.eco_user_platform_role
    WHERE user_profile_id = v_marianela_profile_id AND role_template_id = v_acct_superadmin_tpl_id;
  END IF;

  RAISE NOTICE 'Rollback for Migration 020 (WP-A2 Real User Authorization Assignments) COMPLETED SUCCESSFULLY.';
END $$;

COMMIT;
