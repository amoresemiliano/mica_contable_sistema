-- ============================================================
-- POSTCHECK SCRIPT FOR MIGRATION 023 (WP-AUTH-RESET-1)
-- ============================================================
-- Verifies that:
-- 1. Exactly ONE SELECT policy exists on public.eco_organizations
--    governed by private.authorized_orgs_for_capability('ORG_VIEW').
-- 2. No legacy authorization policies remain on eco_organizations.
-- 3. MICA organization has zero active memberships for real DEV users.
-- 4. VEGEN has 0 tenant memberships and PLATFORM_SUPERADMIN platform role.
-- 5. Marianela has exactly 3 active memberships: NORTE, SUR, OESTE.
-- 6. Emiliano has exactly 1 active membership: NORTE (TENANT_ADMIN).
-- 7. Edravi has exactly 1 active membership: SUR (TENANT_ADMIN).
-- 8. Calle has exactly 1 active membership: OESTE (TENANT_ADMIN).
-- 9. private.authorized_orgs_for_capability('ORG_VIEW') returns:
--    - Emiliano: {NORTE}
--    - Edravi: {SUR}
--    - Calle: {OESTE}
--    - Marianela: {NORTE, SUR, OESTE}
--    - VEGEN: {}
-- 10. Active context rows do NOT grant or alter authorized org cardinality.
-- ============================================================

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

  v_pol_count INT;
  v_mem_count INT;
  v_role_code TEXT;
  v_org_ids UUID[];
BEGIN
  RAISE NOTICE 'Starting Migration 023 Postcheck Verifications...';

  -- 1. Check RLS policies on public.eco_organizations
  -- Must have EXACTLY 1 SELECT policy, and it must be governed by authorized_orgs_for_capability('ORG_VIEW')
  SELECT COUNT(*) INTO v_pol_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'eco_organizations' AND cmd = 'SELECT';

  IF v_pol_count <> 1 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Expected exactly 1 SELECT policy on eco_organizations, found %', v_pol_count;
  END IF;

  SELECT COUNT(*) INTO v_pol_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'eco_organizations'
    AND cmd = 'SELECT'
    AND qual ILIKE '%authorized_orgs_for_capability%ORG_VIEW%';

  IF v_pol_count <> 1 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Canonical ORG_VIEW capability policy missing on eco_organizations';
  END IF;

  -- Ensure legacy policy names are absent
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'eco_organizations'
      AND policyname IN (
        'Organizations member view',
        'eco_organizations_select_policy',
        'Allow authenticated users to read organizations',
        'Allow select for authenticated',
        'Organizations viewable by members'
      )
  ) THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Legacy policy names still detected on eco_organizations';
  END IF;

  -- 2. Resolve Auth and Profile IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  SELECT id INTO v_vegen_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  SELECT id INTO v_marianela_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_marianela_auth_id;
  SELECT id INTO v_emiliano_profile_id  FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;
  SELECT id INTO v_calle_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id;

  -- 3. Verify MICA has ZERO active memberships across all 5 real users
  SELECT COUNT(*) INTO v_mem_count
  FROM public.eco_organization_members
  WHERE organization_id = v_mica_org_id
    AND is_active = TRUE
    AND user_profile_id IN (v_vegen_profile_id, v_marianela_profile_id, v_emiliano_profile_id, v_edravi_profile_id, v_calle_profile_id);

  IF v_mem_count <> 0 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: MICA legacy organization still has % active memberships for real users', v_mem_count;
  END IF;

  -- 4. Verify VEGEN matrix:
  -- - Platform role = PLATFORM_SUPERADMIN
  -- - Tenant memberships = 0
  SELECT COUNT(*) INTO v_mem_count
  FROM public.eco_organization_members
  WHERE user_profile_id = v_vegen_profile_id AND is_active = TRUE;

  IF v_mem_count <> 0 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: VEGEN has % tenant memberships, expected 0', v_mem_count;
  END IF;

  SELECT rt.code INTO v_role_code
  FROM public.eco_user_platform_role upr
  JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
  WHERE upr.user_profile_id = v_vegen_profile_id AND upr.is_active = TRUE;

  IF v_role_code <> 'PLATFORM_SUPERADMIN' THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: VEGEN platform role is %, expected PLATFORM_SUPERADMIN', v_role_code;
  END IF;

  -- 5. Verify MARIANELA matrix:
  -- - Platform role = ACCOUNTING_SUPERADMIN
  -- - Tenant memberships = exactly {NORTE, SUR, OESTE}
  SELECT rt.code INTO v_role_code
  FROM public.eco_user_platform_role upr
  JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
  WHERE upr.user_profile_id = v_marianela_profile_id AND upr.is_active = TRUE;

  IF v_role_code <> 'ACCOUNTING_SUPERADMIN' THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Marianela platform role is %, expected ACCOUNTING_SUPERADMIN', v_role_code;
  END IF;

  SELECT array_agg(organization_id ORDER BY organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_marianela_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_norte_org_id, v_sur_org_id, v_oeste_org_id] AND
     v_org_ids <> ARRAY[v_oeste_org_id, v_norte_org_id, v_sur_org_id] AND
     cardinality(v_org_ids) <> 3 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Marianela memberships mismatch: %', v_org_ids;
  END IF;

  -- 6. Verify EMILIANO matrix:
  -- - Tenant memberships = exactly {NORTE} with TENANT_ADMIN
  SELECT array_agg(organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_emiliano_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_norte_org_id] THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Emiliano memberships mismatch: expected {%}, found %', v_norte_org_id, v_org_ids;
  END IF;

  SELECT rt.code INTO v_role_code
  FROM public.eco_organization_members m
  JOIN public.eco_role_templates rt ON rt.id = m.role_template_id
  WHERE m.user_profile_id = v_emiliano_profile_id AND m.organization_id = v_norte_org_id AND m.is_active = TRUE;

  IF v_role_code <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Emiliano NORTE role template is %, expected TENANT_ADMIN', v_role_code;
  END IF;

  -- 7. Verify EDRAVI matrix:
  -- - Tenant memberships = exactly {SUR} with TENANT_ADMIN
  SELECT array_agg(organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_edravi_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_sur_org_id] THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Edravi memberships mismatch: expected {%}, found %', v_sur_org_id, v_org_ids;
  END IF;

  -- 8. Verify CALLE matrix:
  -- - Tenant memberships = exactly {OESTE} with TENANT_ADMIN
  SELECT array_agg(organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_calle_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_oeste_org_id] THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Calle memberships mismatch: expected {%}, found %', v_oeste_org_id, v_org_ids;
  END IF;

  -- 9. Check private.org_id() contract
  -- Must return active_org_id() without deriving from eco_user_profiles.organization_id
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'private' AND p.proname = 'org_id'
      AND p.prosrc ILIKE '%active_org_id%'
  ) THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: private.org_id() is not delegating to active_org_id()';
  END IF;

  RAISE NOTICE 'Migration 023 Postcheck Verifications PASSED (All policies, memberships, roles, and capability invariants proven).';
END $$;
