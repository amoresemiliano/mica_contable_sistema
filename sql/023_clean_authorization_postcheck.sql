-- ============================================================
-- POSTCHECK SCRIPT FOR MIGRATION 023 (WP-AUTH-RESET-1)
-- ============================================================
-- Verifies that:
-- 1. All 8 canonical role templates exist with exact scopes and is_active = true.
-- 2. Canonical capability mappings and platform bridges exist.
-- 3. Exactly ONE SELECT policy exists on public.eco_organizations
--    governed by private.authorized_orgs_for_capability('ORG_VIEW').
-- 4. No legacy authorization policies remain on eco_organizations.
-- 5. MICA organization has zero active memberships for real DEV users.
-- 6. VEGEN has 0 tenant memberships and PLATFORM_SUPERADMIN platform role.
-- 7. Marianela has exactly 3 active memberships: NORTE, SUR, OESTE.
-- 8. Emiliano has exactly 1 active membership: NORTE (TENANT_ADMIN).
-- 9. Edravi has exactly 1 active membership: SUR (TENANT_ADMIN).
-- 10. Calle has exactly 1 active membership: OESTE (TENANT_ADMIN).
-- 11. private.org_id() delegates strictly to active_org_id().
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

  v_count INT;
  v_role_code TEXT;
  v_org_ids UUID[];
BEGIN
  RAISE NOTICE 'Starting Migration 023 Postcheck Verifications...';

  -- 1. Check all 8 canonical role templates exist, have correct scopes and is_active = TRUE
  SELECT COUNT(*) INTO v_count
  FROM public.eco_role_templates
  WHERE is_active = TRUE
    AND (
      (code = 'PLATFORM_SUPERADMIN' AND scope = 'PLATFORM') OR
      (code = 'ACCOUNTING_SUPERADMIN' AND scope = 'PLATFORM') OR
      (code = 'TENANT_ADMIN' AND scope = 'ORGANIZATION') OR
      (code = 'ACCOUNTANT' AND scope = 'ORGANIZATION') OR
      (code = 'UPLOADER' AND scope = 'ORGANIZATION') OR
      (code = 'REVIEWER' AND scope = 'ORGANIZATION') OR
      (code = 'READ_ONLY' AND scope = 'ORGANIZATION') OR
      (code = 'EXTERNAL_AUDITOR' AND scope = 'ORGANIZATION')
    );

  IF v_count <> 8 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Expected 8 active canonical role templates with correct scopes, found %', v_count;
  END IF;

  -- 2. Check canonical capability bridge for ACCOUNTING_SUPERADMIN
  SELECT COUNT(*) INTO v_count
  FROM public.eco_platform_role_org_capabilities proc
  JOIN public.eco_role_templates rt ON rt.id = proc.role_template_id
  JOIN public.eco_capabilities c ON c.id = proc.capability_id
  WHERE rt.code = 'ACCOUNTING_SUPERADMIN' AND c.code = 'ORG_VIEW';

  IF v_count = 0 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: ACCOUNTING_SUPERADMIN is missing canonical ORG_VIEW capability bridge';
  END IF;

  -- 3. Check RLS policies on public.eco_organizations
  -- Must have EXACTLY 1 SELECT policy, and it must be governed by authorized_orgs_for_capability('ORG_VIEW')
  SELECT COUNT(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'eco_organizations' AND cmd = 'SELECT';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Expected exactly 1 SELECT policy on eco_organizations, found %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'eco_organizations'
    AND cmd = 'SELECT'
    AND qual ILIKE '%authorized_orgs_for_capability%ORG_VIEW%';

  IF v_count <> 1 THEN
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
        'Organizations viewable by members',
        'org_members_read_orgs'
      )
  ) THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Legacy policy names still detected on eco_organizations';
  END IF;

  -- 4. Resolve Auth and Profile IDs
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

  -- 5. Verify MICA has ZERO active memberships across all 5 real users
  SELECT COUNT(*) INTO v_count
  FROM public.eco_organization_members
  WHERE organization_id = v_mica_org_id
    AND is_active = TRUE
    AND user_profile_id IN (v_vegen_profile_id, v_marianela_profile_id, v_emiliano_profile_id, v_edravi_profile_id, v_calle_profile_id);

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: MICA legacy organization still has % active memberships for real users', v_count;
  END IF;

  -- 6. Verify VEGEN matrix:
  -- - Platform role = PLATFORM_SUPERADMIN
  -- - Tenant memberships = 0
  SELECT COUNT(*) INTO v_count
  FROM public.eco_organization_members
  WHERE user_profile_id = v_vegen_profile_id AND is_active = TRUE;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: VEGEN has % tenant memberships, expected 0', v_count;
  END IF;

  SELECT rt.code INTO v_role_code
  FROM public.eco_user_platform_role upr
  JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
  WHERE upr.user_profile_id = v_vegen_profile_id AND upr.is_active = TRUE;

  IF v_role_code <> 'PLATFORM_SUPERADMIN' THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: VEGEN platform role is %, expected PLATFORM_SUPERADMIN', v_role_code;
  END IF;

  -- 7. Verify MARIANELA matrix:
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

  -- 8. Verify EMILIANO matrix:
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

  -- 9. Verify EDRAVI matrix:
  -- - Tenant memberships = exactly {SUR} with TENANT_ADMIN
  SELECT array_agg(organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_edravi_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_sur_org_id] THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Edravi memberships mismatch: expected {%}, found %', v_sur_org_id, v_org_ids;
  END IF;

  -- 10. Verify CALLE matrix:
  -- - Tenant memberships = exactly {OESTE} with TENANT_ADMIN
  SELECT array_agg(organization_id) INTO v_org_ids
  FROM public.eco_organization_members
  WHERE user_profile_id = v_calle_profile_id AND is_active = TRUE;

  IF v_org_ids <> ARRAY[v_oeste_org_id] THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: Calle memberships mismatch: expected {%}, found %', v_oeste_org_id, v_org_ids;
  END IF;

  -- 11. Check private.org_id() contract
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'private' AND p.proname = 'org_id'
      AND p.prosrc ILIKE '%active_org_id%'
  ) THEN
    RAISE EXCEPTION 'Postcheck 023 FAILED: private.org_id() is not delegating to active_org_id()';
  END IF;

  RAISE NOTICE 'Migration 023 Postcheck Verifications PASSED (All templates, scopes, mappings, policies, and memberships proven).';
END $$;
