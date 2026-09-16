-- ============================================================
-- MIGRATION 023: WP-AUTH-RESET-1 CLEAN DEV AUTHORIZATION CUTOVER
-- ============================================================
-- Eliminates legacy authorization paths, neutralizes legacy MICA
-- organization authorization, replaces eco_organizations RLS with
-- the single canonical policy, and resets DEV real-user memberships
-- into the exact canonical matrix.
--
-- Target Matrix:
-- 1. VEGEN DIGITAL (vegendigital@gmail.com):
--    - Platform Role: PLATFORM_SUPERADMIN
--    - Tenant Memberships: 0
--    - Active Context: NULL
--
-- 2. MARIANELA (drcmarianela@gmail.com):
--    - Platform Role: ACCOUNTING_SUPERADMIN
--    - Tenant Memberships: DEMO NORTE, DEMO SUR, DEMO OESTE (role_template_id = NULL)
--    - Active Context: DEMO NORTE
--
-- 3. EMILIANO (emilianodirosa1@gmail.com):
--    - Platform Role: NONE
--    - Tenant Memberships: DEMO NORTE only (TENANT_ADMIN)
--    - Active Context: DEMO NORTE
--
-- 4. EDRAVI (edravi77@gmail.com):
--    - Platform Role: NONE
--    - Tenant Memberships: DEMO SUR only (TENANT_ADMIN)
--    - Active Context: DEMO SUR
--
-- 5. CALLE (calleelcalvario16@gmail.com):
--    - Platform Role: NONE
--    - Tenant Memberships: DEMO OESTE only (TENANT_ADMIN)
--    - Active Context: DEMO OESTE
--
-- Legacy MICA Org (59436df3-9f15-4f5e-b17e-37c55482521c):
-- - Zero active tenant memberships for all normal users.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. DROP ALL OBSOLETE & COMPETING POLICIES ON eco_organizations
-- ============================================================
-- In PostgreSQL, multiple PERMISSIVE SELECT policies on the same table
-- are combined with OR. To guarantee fail-closed multitenant isolation,
-- every legacy policy name ever introduced must be dropped.

DROP POLICY IF EXISTS "Organizations member view" ON public.eco_organizations;
DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;
DROP POLICY IF EXISTS "eco_organizations_select_policy" ON public.eco_organizations;
DROP POLICY IF EXISTS "Allow authenticated users to read organizations" ON public.eco_organizations;
DROP POLICY IF EXISTS "Allow select for authenticated" ON public.eco_organizations;
DROP POLICY IF EXISTS "Organizations viewable by members" ON public.eco_organizations;

-- Ensure RLS is enabled and forced
ALTER TABLE public.eco_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_organizations FORCE ROW LEVEL SECURITY;

-- Revoke mutation rights from authenticated, grant SELECT only
REVOKE INSERT, UPDATE, DELETE ON public.eco_organizations FROM authenticated;
GRANT SELECT ON public.eco_organizations TO authenticated;

-- Create the SINGLE CANONICAL SELECT policy for public.eco_organizations
CREATE POLICY "Organizations viewable by own users"
ON public.eco_organizations
FOR SELECT
TO authenticated
USING (
  id IN (
    SELECT private.authorized_orgs_for_capability('ORG_VIEW')
  )
);


-- ============================================================
-- 2. NEUTRALIZE LEGACY FUNCTIONS THAT RELIED ON PROFILE FIELDS
-- ============================================================
-- Historically, private.org_id() and private.func_role() read
-- eco_user_profiles.organization_id and eco_user_profiles.role.
-- Under the canonical model, active organization context is
-- managed via private.active_org_id() and capabilities via private.can_org().
-- To prevent accidental legacy authorization derivation, align private.org_id()
-- to read strictly through canonical private.active_org_id().

CREATE OR REPLACE FUNCTION private.org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.active_org_id();
$$;

REVOKE ALL ON FUNCTION private.org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.org_id() TO authenticated;


-- ============================================================
-- 3. DETERMINISTIC REAL DEV USER MEMBERSHIP & ROLE RESET
-- ============================================================

DO $$
DECLARE
  -- Organization UUID constants
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;
  v_mica_org_id  CONSTANT UUID := '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID;

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

  v_real_profile_ids UUID[];
BEGIN
  -- 1. Resolve Role Template IDs
  SELECT id INTO v_platform_superadmin_tpl_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN' AND is_active = TRUE;
  SELECT id INTO v_acct_superadmin_tpl_id     FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN' AND is_active = TRUE;
  SELECT id INTO v_tenant_admin_tpl_id        FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN' AND is_active = TRUE;

  IF v_platform_superadmin_tpl_id IS NULL OR v_acct_superadmin_tpl_id IS NULL OR v_tenant_admin_tpl_id IS NULL THEN
    RAISE EXCEPTION 'Migration 023 FAILED: Required role templates missing or inactive.';
  END IF;

  -- 2. Resolve Auth User IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  IF v_vegen_auth_id IS NULL OR v_marianela_auth_id IS NULL OR v_emiliano_auth_id IS NULL OR v_edravi_auth_id IS NULL OR v_calle_auth_id IS NULL THEN
    RAISE EXCEPTION 'Migration 023 FAILED: Target auth.users entries could not be resolved.';
  END IF;

  -- 3. Resolve or Create User Profile IDs
  SELECT id INTO v_vegen_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  SELECT id INTO v_marianela_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_marianela_auth_id;
  SELECT id INTO v_emiliano_profile_id  FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;
  SELECT id INTO v_calle_profile_id     FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id;

  IF v_calle_profile_id IS NULL THEN
    INSERT INTO public.eco_user_profiles (auth_user_id, role, is_active)
    VALUES (v_calle_auth_id, 'USER', TRUE)
    RETURNING id INTO v_calle_profile_id;
  END IF;

  -- Ensure all profiles are active
  UPDATE public.eco_user_profiles
  SET is_active = TRUE
  WHERE id IN (v_vegen_profile_id, v_marianela_profile_id, v_emiliano_profile_id, v_edravi_profile_id, v_calle_profile_id);

  v_real_profile_ids := ARRAY[
    v_vegen_profile_id,
    v_marianela_profile_id,
    v_emiliano_profile_id,
    v_edravi_profile_id,
    v_calle_profile_id
  ];

  -- 4. Purge ANY memberships in legacy MICA organization for real DEV users
  DELETE FROM public.eco_organization_members
  WHERE organization_id = v_mica_org_id
    AND user_profile_id = ANY(v_real_profile_ids);

  -- Purge any stale capability overrides for real DEV users
  DELETE FROM public.eco_membership_capability_overrides
  WHERE membership_id IN (
    SELECT id FROM public.eco_organization_members WHERE user_profile_id = ANY(v_real_profile_ids)
  );
  DELETE FROM public.eco_user_platform_capability_overrides
  WHERE user_profile_id = ANY(v_real_profile_ids);

  -- ============================================================
  -- 5. RESET PLATFORM ROLES
  -- ============================================================
  -- Reset all platform roles for real DEV profiles
  DELETE FROM public.eco_user_platform_role
  WHERE user_profile_id = ANY(v_real_profile_ids);

  -- A) VEGEN -> PLATFORM_SUPERADMIN
  INSERT INTO public.eco_user_platform_role (user_profile_id, role_template_id, is_active)
  VALUES (v_vegen_profile_id, v_platform_superadmin_tpl_id, TRUE);

  -- B) MARIANELA -> ACCOUNTING_SUPERADMIN
  INSERT INTO public.eco_user_platform_role (user_profile_id, role_template_id, is_active)
  VALUES (v_marianela_profile_id, v_acct_superadmin_tpl_id, TRUE);

  -- (Emiliano, Edravi, Calle have NO platform role)


  -- ============================================================
  -- 6. RESET TENANT MEMBERSHIPS
  -- ============================================================
  -- Delete all existing tenant memberships for real DEV profiles to eliminate drift
  DELETE FROM public.eco_organization_members
  WHERE user_profile_id = ANY(v_real_profile_ids);

  -- A) VEGEN: 0 tenant memberships (none inserted)

  -- B) MARIANELA: NORTE, SUR, OESTE (role_template_id = NULL, platform bridge active)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES
    (v_norte_org_id, v_marianela_profile_id, NULL, TRUE),
    (v_sur_org_id,   v_marianela_profile_id, NULL, TRUE),
    (v_oeste_org_id, v_marianela_profile_id, NULL, TRUE);

  -- C) EMILIANO: DEMO NORTE ONLY (TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_emiliano_profile_id, v_tenant_admin_tpl_id, TRUE);

  -- D) EDRAVI: DEMO SUR ONLY (TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_edravi_profile_id, v_tenant_admin_tpl_id, TRUE);

  -- E) CALLE: DEMO OESTE ONLY (TENANT_ADMIN)
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_oeste_org_id, v_calle_profile_id, v_tenant_admin_tpl_id, TRUE);


  -- ============================================================
  -- 7. RESET ACTIVE CONTEXT ROWS
  -- ============================================================
  DELETE FROM public.eco_user_active_context
  WHERE user_profile_id = ANY(v_real_profile_ids);

  -- A) VEGEN: NULL active context (no row or organization_id = NULL)
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_vegen_profile_id, NULL, now());

  -- B) MARIANELA: DEMO NORTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_marianela_profile_id, v_norte_org_id, now());

  -- C) EMILIANO: DEMO NORTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_emiliano_profile_id, v_norte_org_id, now());

  -- D) EDRAVI: DEMO SUR
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_edravi_profile_id, v_sur_org_id, now());

  -- E) CALLE: DEMO OESTE
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_calle_profile_id, v_oeste_org_id, now());

  -- ============================================================
  -- 8. NORMALIZE NON-AUTHORITATIVE COMPATIBILITY FIELDS
  -- ============================================================
  -- Synchronize compatibility fields on eco_user_profiles for UI/frontend display
  UPDATE public.eco_user_profiles SET organization_id = NULL, role = 'SUPERADMIN' WHERE id = v_vegen_profile_id;
  UPDATE public.eco_user_profiles SET organization_id = v_norte_org_id, role = 'SUPERADMIN' WHERE id = v_marianela_profile_id;
  UPDATE public.eco_user_profiles SET organization_id = v_norte_org_id, role = 'ADMIN' WHERE id = v_emiliano_profile_id;
  UPDATE public.eco_user_profiles SET organization_id = v_sur_org_id, role = 'ADMIN' WHERE id = v_edravi_profile_id;
  UPDATE public.eco_user_profiles SET organization_id = v_oeste_org_id, role = 'ADMIN' WHERE id = v_calle_profile_id;

  RAISE NOTICE 'Migration 023 (Clean DEV Authorization Cutover) Applied Successfully.';
END $$;

COMMIT;
