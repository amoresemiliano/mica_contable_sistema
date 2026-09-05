BEGIN;

-- ============================================================
-- MIGRATION 019: WP-A1 ADDITIVE CAPABILITY FOUNDATION
-- ============================================================
-- Introduces identity, membership & capability architecture additively.
-- Preserves existing auth, profiles, organizations, RLS, and RPCs.
-- ============================================================

-- 1. eco_capabilities
CREATE TABLE IF NOT EXISTS public.eco_capabilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('PLATFORM', 'ORGANIZATION')),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. eco_role_templates
CREATE TABLE IF NOT EXISTS public.eco_role_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('PLATFORM', 'ORGANIZATION')),
    name TEXT NOT NULL,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. eco_role_template_capabilities
CREATE TABLE IF NOT EXISTS public.eco_role_template_capabilities (
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role_template_id, capability_id)
);

-- 4. eco_platform_role_org_capabilities
CREATE TABLE IF NOT EXISTS public.eco_platform_role_org_capabilities (
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role_template_id, capability_id)
);

-- 5. eco_membership_capability_overrides
CREATE TABLE IF NOT EXISTS public.eco_membership_capability_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES public.eco_organization_members(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    effect TEXT NOT NULL CHECK (effect IN ('ALLOW', 'DENY')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (membership_id, capability_id)
);

-- 6. eco_user_platform_role
CREATE TABLE IF NOT EXISTS public.eco_user_platform_role (
    user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. eco_user_platform_capability_overrides
CREATE TABLE IF NOT EXISTS public.eco_user_platform_capability_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_profile_id UUID NOT NULL REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    effect TEXT NOT NULL CHECK (effect IN ('ALLOW', 'DENY')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_profile_id, capability_id)
);

-- 8. eco_user_active_context (ON DELETE SET NULL)
CREATE TABLE IF NOT EXISTS public.eco_user_active_context (
    user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    organization_id UUID NULL REFERENCES public.eco_organizations(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. Evolve eco_organization_members (ADD role_template_id NULLABLE)
ALTER TABLE public.eco_organization_members
ADD COLUMN IF NOT EXISTS role_template_id UUID NULL
REFERENCES public.eco_role_templates(id);

-- 10. Indexes
CREATE INDEX IF NOT EXISTS idx_eco_org_members_user_active
ON public.eco_organization_members(user_profile_id, is_active);

CREATE INDEX IF NOT EXISTS idx_eco_org_members_org_active
ON public.eco_organization_members(organization_id, is_active);

CREATE INDEX IF NOT EXISTS idx_membership_cap_overrides_membership
ON public.eco_membership_capability_overrides(membership_id);

CREATE INDEX IF NOT EXISTS idx_platform_cap_overrides_user
ON public.eco_user_platform_capability_overrides(user_profile_id);


-- ============================================================
-- SEED DATA (CAPABILITIES, ROLE TEMPLATES & MAPPINGS)
-- ============================================================

-- A. Platform Capabilities
INSERT INTO public.eco_capabilities (code, scope, description) VALUES
  ('PLATFORM_MANAGE', 'PLATFORM', 'Manage system-wide configuration and platform settings'),
  ('ORGANIZATION_CREATE', 'PLATFORM', 'Create new tenant organizations'),
  ('ORGANIZATION_UPDATE', 'PLATFORM', 'Update tenant organization settings and details'),
  ('ORGANIZATION_ARCHIVE', 'PLATFORM', 'Archive or deactivate tenant organizations'),
  ('GLOBAL_USER_MANAGE', 'PLATFORM', 'Manage platform users globally across all tenants'),
  ('PLAN_MANAGE', 'PLATFORM', 'Manage subscription plans and billing tiers'),
  ('GLOBAL_CATALOG_VIEW', 'PLATFORM', 'View global tax and economic activity catalogs'),
  ('GLOBAL_CATALOG_MANAGE', 'PLATFORM', 'Manage global tax and economic activity catalogs'),
  ('CATALOG_ASSIGN_ANY_ORG', 'PLATFORM', 'Assign global catalog categories/activities to any tenant organization'),
  ('RATE_MANAGE_ANY_ORG', 'PLATFORM', 'Manage IIBB rates for any tenant organization'),
  ('ACCESS_ANY_ORG', 'PLATFORM', 'Future entitlement for elevated platform-wide tenant access'),
  ('REPORT_COMPARE_SCOPED_ORGS', 'PLATFORM', 'Access cross-organizational comparative reports'),
  ('REPORT_CONSOLIDATED_SCOPED_ORGS', 'PLATFORM', 'Access consolidated financial reports across scoped organizations'),
  ('SAAS_ANALYTICS_VIEW', 'PLATFORM', 'View SaaS platform usage analytics and operational metrics'),
  ('SUPPORT_IMPERSONATE', 'PLATFORM', 'Support access to impersonate user sessions for troubleshooting'),
  ('HARD_DELETE_EXCEPTIONAL', 'PLATFORM', 'Perform exceptional hard deletion of system data'),
  ('AUDIT_PLATFORM_VIEW', 'PLATFORM', 'View global platform audit logs')
ON CONFLICT (code) DO NOTHING;

-- B. Organization Capabilities
INSERT INTO public.eco_capabilities (code, scope, description) VALUES
  ('ORG_VIEW', 'ORGANIZATION', 'View organization details and dashboard'),
  ('ORG_SETTINGS_VIEW', 'ORGANIZATION', 'View organization configuration settings'),
  ('ORG_SETTINGS_MANAGE', 'ORGANIZATION', 'Modify organization configuration settings'),
  ('ORG_MEMBER_VIEW', 'ORGANIZATION', 'View organization members list'),
  ('ORG_MEMBER_INVITE', 'ORGANIZATION', 'Invite new members to organization'),
  ('ORG_MEMBER_MANAGE', 'ORGANIZATION', 'Manage existing organization members'),
  ('ORG_MEMBER_PERMISSION_MANAGE', 'ORGANIZATION', 'Manage member role templates and capability overrides'),
  ('IMPORT_VIEW', 'ORGANIZATION', 'View import history and details'),
  ('IMPORT_CREATE', 'ORGANIZATION', 'Create new import batch'),
  ('IMPORT_RETRY', 'ORGANIZATION', 'Request retry for failed import'),
  ('IMPORT_REVIEW', 'ORGANIZATION', 'Review import issues and status'),
  ('RECORD_VIEW', 'ORGANIZATION', 'View normalized accounting records'),
  ('RECORD_CLASSIFY', 'ORGANIZATION', 'Classify normalized accounting records'),
  ('RECORD_SOFT_DELETE', 'ORGANIZATION', 'Soft delete normalized accounting records'),
  ('RECORD_RESTORE', 'ORGANIZATION', 'Restore soft-deleted normalized accounting records'),
  ('PERCEPTION_IMPORT', 'ORGANIZATION', 'Execute tax perceptions file import'),
  ('BANK_IMPORT', 'ORGANIZATION', 'Execute bank statement file import'),
  ('PAYROLL_IMPORT', 'ORGANIZATION', 'Execute payroll file import'),
  ('ISSUE_RESOLVE', 'ORGANIZATION', 'Resolve import validation issues'),
  ('CATALOG_ORG_VIEW', 'ORGANIZATION', 'View organization assigned catalog categories'),
  ('REPORT_VIEW', 'ORGANIZATION', 'View organization financial reports'),
  ('REPORT_EXPORT', 'ORGANIZATION', 'Export organization financial reports'),
  ('TICKET_CREATE', 'ORGANIZATION', 'Create support tickets for organization'),
  ('TICKET_VIEW_ORG', 'ORGANIZATION', 'View support tickets for organization'),
  ('AUDIT_VIEW_ORG', 'ORGANIZATION', 'View organization audit log events')
ON CONFLICT (code) DO NOTHING;

-- C. Role Templates
INSERT INTO public.eco_role_templates (code, scope, name, description) VALUES
  ('PLATFORM_SUPERADMIN', 'PLATFORM', 'Platform Super Admin', 'Full administrative authority across the entire platform'),
  ('ACCOUNTING_SUPERADMIN', 'PLATFORM', 'Accounting Super Admin', 'Platform-level accounting authority with multi-org capabilities'),
  ('TENANT_ADMIN', 'ORGANIZATION', 'Tenant Admin', 'Full administrative authority within a single organization'),
  ('ACCOUNTANT', 'ORGANIZATION', 'Accountant', 'Full operational accounting and reporting authority'),
  ('UPLOADER', 'ORGANIZATION', 'Data Uploader', 'Authority to upload and import files into organization'),
  ('REVIEWER', 'ORGANIZATION', 'Data Reviewer', 'Authority to review and classify imported records'),
  ('READ_ONLY', 'ORGANIZATION', 'Read Only Access', 'Read-only viewing access to organization data'),
  ('EXTERNAL_AUDITOR', 'ORGANIZATION', 'External Auditor', 'Read-only access with audit log visibility')
ON CONFLICT (code) DO NOTHING;

-- D. Helper to seed role template capabilities
DO $$
DECLARE
    v_template_id UUID;
    v_cap_code TEXT;
    v_cap_id UUID;
    v_caps TEXT[];
    v_tcode TEXT;
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
-- HELPER FUNCTIONS IN private SCHEMA
-- ============================================================

-- 1. private.current_profile_id()
CREATE OR REPLACE FUNCTION private.current_profile_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT id
    FROM public.eco_user_profiles
    WHERE auth_user_id = auth.uid()
      AND is_active = TRUE
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.current_profile_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.current_profile_id() TO authenticated;

-- 2. private.active_org_id()
CREATE OR REPLACE FUNCTION private.active_org_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_active_org_id UUID;
BEGIN
    v_profile_id := private.current_profile_id();
    IF v_profile_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT organization_id INTO v_active_org_id
    FROM public.eco_user_active_context
    WHERE user_profile_id = v_profile_id;

    RETURN v_active_org_id;
END;
$$;

REVOKE ALL ON FUNCTION private.active_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.active_org_id() TO authenticated;

-- 3. private.can_platform(p_capability_code TEXT)
CREATE OR REPLACE FUNCTION private.can_platform(p_capability_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_cap_id UUID;
    v_role_template_id UUID;
    v_has_base BOOLEAN := FALSE;
    v_override_effect TEXT;
BEGIN
    IF p_capability_code IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 1. current profile exists and is active
    v_profile_id := private.current_profile_id();
    IF v_profile_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 2. requested capability exists, scope = PLATFORM, is_active = TRUE
    SELECT id INTO v_cap_id
    FROM public.eco_capabilities
    WHERE code = p_capability_code
      AND scope = 'PLATFORM'
      AND is_active = TRUE;

    IF v_cap_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 3. eco_user_platform_role exists and is_active = TRUE
    -- 4. referenced role template: scope = PLATFORM, is_active = TRUE
    SELECT upr.role_template_id INTO v_role_template_id
    FROM public.eco_user_platform_role upr
    JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
    WHERE upr.user_profile_id = v_profile_id
      AND upr.is_active = TRUE
      AND rt.scope = 'PLATFORM'
      AND rt.is_active = TRUE;

    -- 5. base grant is read from eco_role_template_capabilities
    IF v_role_template_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.eco_role_template_capabilities
            WHERE role_template_id = v_role_template_id
              AND capability_id = v_cap_id
        ) INTO v_has_base;
    END IF;

    -- 6. user-specific override is read from eco_user_platform_capability_overrides
    SELECT effect INTO v_override_effect
    FROM public.eco_user_platform_capability_overrides
    WHERE user_profile_id = v_profile_id
      AND capability_id = v_cap_id;

    -- 7. explicit DENY wins
    IF v_override_effect = 'DENY' THEN
        RETURN FALSE;
    END IF;

    -- 8. explicit ALLOW can grant a capability absent from base template
    IF v_override_effect = 'ALLOW' THEN
        RETURN TRUE;
    END IF;

    -- 9. otherwise return base grant
    RETURN v_has_base;
END;
$$;

REVOKE ALL ON FUNCTION private.can_platform(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_platform(TEXT) TO authenticated;

-- 4. private.can_org(p_org_id UUID, p_capability_code TEXT)
CREATE OR REPLACE FUNCTION private.can_org(p_org_id UUID, p_capability_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_membership_id UUID;
    v_membership_role_template_id UUID;
    v_user_platform_role_template_id UUID;
    v_cap_id UUID;
    v_has_base_template BOOLEAN := FALSE;
    v_has_base_platform_bridge BOOLEAN := FALSE;
    v_has_base BOOLEAN := FALSE;
    v_override_effect TEXT;
BEGIN
    IF p_org_id IS NULL OR p_capability_code IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 1. current profile exists and is active
    v_profile_id := private.current_profile_id();
    IF v_profile_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 2. target organization exists
    IF NOT EXISTS (
        SELECT 1 FROM public.eco_organizations
        WHERE id = p_org_id
    ) THEN
        RETURN FALSE;
    END IF;

    -- 3. an ACTIVE eco_organization_members row exists for current profile + target org
    SELECT id, role_template_id INTO v_membership_id, v_membership_role_template_id
    FROM public.eco_organization_members
    WHERE organization_id = p_org_id
      AND user_profile_id = v_profile_id
      AND is_active = TRUE;

    IF v_membership_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 4. requested capability exists: scope = ORGANIZATION, is_active = TRUE
    SELECT id INTO v_cap_id
    FROM public.eco_capabilities
    WHERE code = p_capability_code
      AND scope = 'ORGANIZATION'
      AND is_active = TRUE;

    IF v_cap_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 5. membership role template, when present: scope = ORGANIZATION, is_active = TRUE
    IF v_membership_role_template_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.eco_role_template_capabilities rtc
            JOIN public.eco_role_templates rt ON rt.id = rtc.role_template_id
            WHERE rtc.role_template_id = v_membership_role_template_id
              AND rtc.capability_id = v_cap_id
              AND rt.scope = 'ORGANIZATION'
              AND rt.is_active = TRUE
        ) INTO v_has_base_template;
    END IF;

    -- 6. eligible platform-role organization grant through eco_platform_role_org_capabilities
    SELECT upr.role_template_id INTO v_user_platform_role_template_id
    FROM public.eco_user_platform_role upr
    JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
    WHERE upr.user_profile_id = v_profile_id
      AND upr.is_active = TRUE
      AND rt.scope = 'PLATFORM'
      AND rt.is_active = TRUE;

    IF v_user_platform_role_template_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.eco_platform_role_org_capabilities
            WHERE role_template_id = v_user_platform_role_template_id
              AND capability_id = v_cap_id
        ) INTO v_has_base_platform_bridge;
    END IF;

    v_has_base := (v_has_base_template OR v_has_base_platform_bridge);

    -- 7. membership-specific override is applied last (eco_membership_capability_overrides)
    SELECT effect INTO v_override_effect
    FROM public.eco_membership_capability_overrides
    WHERE membership_id = v_membership_id
      AND capability_id = v_cap_id;

    -- 8. explicit DENY wins
    IF v_override_effect = 'DENY' THEN
        RETURN FALSE;
    END IF;

    -- 9. explicit ALLOW can grant a capability omitted by all base grants
    IF v_override_effect = 'ALLOW' THEN
        RETURN TRUE;
    END IF;

    -- 10. otherwise return whether any base grant exists
    RETURN v_has_base;
END;
$$;

REVOKE ALL ON FUNCTION private.can_org(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_org(UUID, TEXT) TO authenticated;

COMMIT;
