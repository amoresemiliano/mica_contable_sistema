-- ============================================================
-- MIGRATION 023: WP-AUTH-RESET-1 CANONICAL AUTHORIZATION FOUNDATION
--                & CLEAN DEV AUTHORIZATION CUTOVER
-- ============================================================
-- 1. Reconciles all canonical capabilities (Platform & Org).
-- 2. Reconciles canonical role templates (Platform & Org) idempotently,
--    preserving existing UUIDs, normalizing scopes and descriptions.
-- 3. Recreates all canonical role template capability mappings & bridges.
-- 4. Eliminates legacy effective authorization paths and policies.
-- 5. Neutralizes legacy MICA organization (59436df3-9f15-4f5e-b17e-37c55482521c).
-- 6. Resets the five real DEV users to the exact canonical matrix.
-- 7. Resets active contexts and normalizes compatibility display fields.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. RECONCILE CANONICAL CAPABILITIES (PLATFORM & ORGANIZATION)
-- ============================================================

-- A. Platform Capabilities (17)
INSERT INTO public.eco_capabilities (code, scope, description, is_active) VALUES
  ('PLATFORM_MANAGE', 'PLATFORM', 'Manage system-wide configuration and platform settings', TRUE),
  ('ORGANIZATION_CREATE', 'PLATFORM', 'Create new tenant organizations', TRUE),
  ('ORGANIZATION_UPDATE', 'PLATFORM', 'Update tenant organization settings and details', TRUE),
  ('ORGANIZATION_ARCHIVE', 'PLATFORM', 'Archive or deactivate tenant organizations', TRUE),
  ('GLOBAL_USER_MANAGE', 'PLATFORM', 'Manage platform users globally across all tenants', TRUE),
  ('PLAN_MANAGE', 'PLATFORM', 'Manage subscription plans and billing tiers', TRUE),
  ('GLOBAL_CATALOG_VIEW', 'PLATFORM', 'View global tax and economic activity catalogs', TRUE),
  ('GLOBAL_CATALOG_MANAGE', 'PLATFORM', 'Manage global tax and economic activity catalogs', TRUE),
  ('CATALOG_ASSIGN_ANY_ORG', 'PLATFORM', 'Assign global catalog categories/activities to any tenant organization', TRUE),
  ('RATE_MANAGE_ANY_ORG', 'PLATFORM', 'Manage IIBB rates for any tenant organization', TRUE),
  ('ACCESS_ANY_ORG', 'PLATFORM', 'Future entitlement for elevated platform-wide tenant access', TRUE),
  ('REPORT_COMPARE_SCOPED_ORGS', 'PLATFORM', 'Access cross-organizational comparative reports', TRUE),
  ('REPORT_CONSOLIDATED_SCOPED_ORGS', 'PLATFORM', 'Access consolidated financial reports across scoped organizations', TRUE),
  ('SAAS_ANALYTICS_VIEW', 'PLATFORM', 'View SaaS platform usage analytics and operational metrics', TRUE),
  ('SUPPORT_IMPERSONATE', 'PLATFORM', 'Support access to impersonate user sessions for troubleshooting', TRUE),
  ('HARD_DELETE_EXCEPTIONAL', 'PLATFORM', 'Perform exceptional hard deletion of system data', TRUE),
  ('AUDIT_PLATFORM_VIEW', 'PLATFORM', 'View global platform audit logs', TRUE)
ON CONFLICT (code) DO UPDATE SET
  scope = EXCLUDED.scope,
  description = EXCLUDED.description,
  is_active = TRUE;

-- B. Organization Capabilities (25)
INSERT INTO public.eco_capabilities (code, scope, description, is_active) VALUES
  ('ORG_VIEW', 'ORGANIZATION', 'View organization details and dashboard', TRUE),
  ('ORG_SETTINGS_VIEW', 'ORGANIZATION', 'View organization configuration settings', TRUE),
  ('ORG_SETTINGS_MANAGE', 'ORGANIZATION', 'Modify organization configuration settings', TRUE),
  ('ORG_MEMBER_VIEW', 'ORGANIZATION', 'View organization members list', TRUE),
  ('ORG_MEMBER_INVITE', 'ORGANIZATION', 'Invite new members to organization', TRUE),
  ('ORG_MEMBER_MANAGE', 'ORGANIZATION', 'Manage existing organization members', TRUE),
  ('ORG_MEMBER_PERMISSION_MANAGE', 'ORGANIZATION', 'Manage member role templates and capability overrides', TRUE),
  ('IMPORT_VIEW', 'ORGANIZATION', 'View import history and details', TRUE),
  ('IMPORT_CREATE', 'ORGANIZATION', 'Create new import batch', TRUE),
  ('IMPORT_RETRY', 'ORGANIZATION', 'Request retry for failed import', TRUE),
  ('IMPORT_REVIEW', 'ORGANIZATION', 'Review import issues and status', TRUE),
  ('RECORD_VIEW', 'ORGANIZATION', 'View normalized accounting records', TRUE),
  ('RECORD_CLASSIFY', 'ORGANIZATION', 'Classify normalized accounting records', TRUE),
  ('RECORD_SOFT_DELETE', 'ORGANIZATION', 'Soft delete normalized accounting records', TRUE),
  ('RECORD_RESTORE', 'ORGANIZATION', 'Restore soft-deleted normalized accounting records', TRUE),
  ('PERCEPTION_IMPORT', 'ORGANIZATION', 'Execute tax perceptions file import', TRUE),
  ('BANK_IMPORT', 'ORGANIZATION', 'Execute bank statement file import', TRUE),
  ('PAYROLL_IMPORT', 'ORGANIZATION', 'Execute payroll file import', TRUE),
  ('ISSUE_RESOLVE', 'ORGANIZATION', 'Resolve import validation issues', TRUE),
  ('CATALOG_ORG_VIEW', 'ORGANIZATION', 'View organization assigned catalog categories', TRUE),
  ('REPORT_VIEW', 'ORGANIZATION', 'View organization financial reports', TRUE),
  ('REPORT_EXPORT', 'ORGANIZATION', 'Export organization financial reports', TRUE),
  ('TICKET_CREATE', 'ORGANIZATION', 'Create support tickets for organization', TRUE),
  ('TICKET_VIEW_ORG', 'ORGANIZATION', 'View support tickets for organization', TRUE),
  ('AUDIT_VIEW_ORG', 'ORGANIZATION', 'View organization audit log events', TRUE)
ON CONFLICT (code) DO UPDATE SET
  scope = EXCLUDED.scope,
  description = EXCLUDED.description,
  is_active = TRUE;


-- ============================================================
-- 2. RECONCILE CANONICAL ROLE TEMPLATES (PLATFORM & ORG)
-- ============================================================
-- Preserves existing UUIDs if code exists, normalizes scope, is_active, name, description.

INSERT INTO public.eco_role_templates (code, scope, name, description, is_active) VALUES
  ('PLATFORM_SUPERADMIN', 'PLATFORM', 'Platform Super Admin', 'Full administrative authority across the entire platform', TRUE),
  ('ACCOUNTING_SUPERADMIN', 'PLATFORM', 'Accounting Super Admin', 'Platform-level accounting authority with multi-org capabilities', TRUE),
  ('TENANT_ADMIN', 'ORGANIZATION', 'Tenant Admin', 'Full administrative authority within a single organization', TRUE),
  ('ACCOUNTANT', 'ORGANIZATION', 'Accountant', 'Full operational accounting and reporting authority', TRUE),
  ('UPLOADER', 'ORGANIZATION', 'Data Uploader', 'Authority to upload and import files into organization', TRUE),
  ('REVIEWER', 'ORGANIZATION', 'Data Reviewer', 'Authority to review and classify imported records', TRUE),
  ('READ_ONLY', 'ORGANIZATION', 'Read Only Access', 'Read-only viewing access to organization data', TRUE),
  ('EXTERNAL_AUDITOR', 'ORGANIZATION', 'External Auditor', 'Read-only access with audit log visibility', TRUE)
ON CONFLICT (code) DO UPDATE SET
  scope = EXCLUDED.scope,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  is_active = TRUE;


-- ============================================================
-- 3. RECREATE CANONICAL ROLE TEMPLATE CAPABILITY MAPPINGS
-- ============================================================

DO $$
DECLARE
    v_template_id UUID;
    v_cap_code TEXT;
    v_cap_id UUID;
    v_caps TEXT[];
BEGIN
    -- 1. PLATFORM_SUPERADMIN -> ALL 17 Platform Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN';
    FOR v_cap_id IN SELECT id FROM public.eco_capabilities WHERE scope = 'PLATFORM' LOOP
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 2. ACCOUNTING_SUPERADMIN -> Platform Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN';
    v_caps := ARRAY[
        'GLOBAL_CATALOG_VIEW', 'CATALOG_ASSIGN_ANY_ORG', 'RATE_MANAGE_ANY_ORG',
        'REPORT_COMPARE_SCOPED_ORGS', 'REPORT_CONSOLIDATED_SCOPED_ORGS'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 3. ACCOUNTING_SUPERADMIN -> Organization Capability Bridge (eco_platform_role_org_capabilities)
    v_caps := ARRAY[
        'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'IMPORT_VIEW', 'IMPORT_CREATE', 'IMPORT_RETRY',
        'IMPORT_REVIEW', 'RECORD_VIEW', 'RECORD_CLASSIFY', 'RECORD_SOFT_DELETE', 'RECORD_RESTORE',
        'PERCEPTION_IMPORT', 'BANK_IMPORT', 'PAYROLL_IMPORT', 'ISSUE_RESOLVE', 'CATALOG_ORG_VIEW',
        'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE', 'TICKET_VIEW_ORG', 'AUDIT_VIEW_ORG'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_platform_role_org_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 4. TENANT_ADMIN -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN';
    v_caps := ARRAY[
        'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'ORG_SETTINGS_MANAGE', 'ORG_MEMBER_VIEW', 'ORG_MEMBER_INVITE',
        'ORG_MEMBER_MANAGE', 'ORG_MEMBER_PERMISSION_MANAGE', 'IMPORT_VIEW', 'IMPORT_CREATE', 'IMPORT_RETRY',
        'IMPORT_REVIEW', 'RECORD_VIEW', 'RECORD_CLASSIFY', 'RECORD_SOFT_DELETE', 'PERCEPTION_IMPORT',
        'BANK_IMPORT', 'PAYROLL_IMPORT', 'ISSUE_RESOLVE', 'CATALOG_ORG_VIEW', 'REPORT_VIEW',
        'REPORT_EXPORT', 'TICKET_CREATE', 'TICKET_VIEW_ORG', 'AUDIT_VIEW_ORG'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 5. ACCOUNTANT -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'ACCOUNTANT';
    v_caps := ARRAY[
        'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'IMPORT_VIEW', 'IMPORT_CREATE', 'IMPORT_RETRY',
        'IMPORT_REVIEW', 'RECORD_VIEW', 'RECORD_CLASSIFY', 'RECORD_SOFT_DELETE', 'PERCEPTION_IMPORT',
        'BANK_IMPORT', 'PAYROLL_IMPORT', 'ISSUE_RESOLVE', 'CATALOG_ORG_VIEW', 'REPORT_VIEW',
        'REPORT_EXPORT', 'TICKET_CREATE', 'TICKET_VIEW_ORG', 'AUDIT_VIEW_ORG'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 6. UPLOADER -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'UPLOADER';
    v_caps := ARRAY[
        'ORG_VIEW', 'IMPORT_VIEW', 'IMPORT_CREATE', 'IMPORT_RETRY', 'RECORD_VIEW',
        'PERCEPTION_IMPORT', 'BANK_IMPORT', 'PAYROLL_IMPORT', 'CATALOG_ORG_VIEW',
        'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 7. REVIEWER -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'REVIEWER';
    v_caps := ARRAY[
        'ORG_VIEW', 'IMPORT_VIEW', 'IMPORT_REVIEW', 'RECORD_VIEW', 'RECORD_CLASSIFY',
        'ISSUE_RESOLVE', 'CATALOG_ORG_VIEW', 'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 8. READ_ONLY -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'READ_ONLY';
    v_caps := ARRAY[
        'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'IMPORT_VIEW', 'IMPORT_REVIEW', 'RECORD_VIEW',
        'CATALOG_ORG_VIEW', 'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;

    -- 9. EXTERNAL_AUDITOR -> Org Capabilities
    SELECT id INTO v_template_id FROM public.eco_role_templates WHERE code = 'EXTERNAL_AUDITOR';
    v_caps := ARRAY[
        'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'IMPORT_VIEW', 'IMPORT_REVIEW', 'RECORD_VIEW',
        'CATALOG_ORG_VIEW', 'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE', 'AUDIT_VIEW_ORG'
    ];
    FOREACH v_cap_code IN ARRAY v_caps LOOP
        SELECT id INTO v_cap_id FROM public.eco_capabilities WHERE code = v_cap_code;
        INSERT INTO public.eco_role_template_capabilities (role_template_id, capability_id)
        VALUES (v_template_id, v_cap_id) ON CONFLICT DO NOTHING;
    END LOOP;
END $$;


-- ============================================================
-- 4. ELIMINATE LEGACY AUTHORIZATION POLICIES & OBSOLETE PATHS
-- ============================================================

-- Drop all competing permissive SELECT policies on public.eco_organizations
DROP POLICY IF EXISTS "Organizations member view" ON public.eco_organizations;
DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;
DROP POLICY IF EXISTS "eco_organizations_select_policy" ON public.eco_organizations;
DROP POLICY IF EXISTS "Allow authenticated users to read organizations" ON public.eco_organizations;
DROP POLICY IF EXISTS "Allow select for authenticated" ON public.eco_organizations;
DROP POLICY IF EXISTS "Organizations viewable by members" ON public.eco_organizations;
DROP POLICY IF EXISTS org_members_read_orgs ON public.eco_organizations;

-- Ensure RLS is enabled and forced
ALTER TABLE public.eco_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_organizations FORCE ROW LEVEL SECURITY;

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

-- Neutralize private.org_id() so it never falls back to eco_user_profiles.organization_id
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
-- 5. DETERMINISTIC REAL DEV USER MEMBERSHIP & ROLE RESET
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

  -- 4. Neutralize ANY memberships in legacy MICA organization for real DEV users
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

  RAISE NOTICE 'Migration 023 (Canonical Authorization Foundation & DEV Cutover) Applied Successfully.';
END $$;

COMMIT;
