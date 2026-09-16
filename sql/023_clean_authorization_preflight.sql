-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 023 (WP-AUTH-RESET-1)
-- ============================================================
-- Verifies baseline schema, core authorization tables, real user
-- accounts in auth.users, and prerequisites before executing 023.
-- DO NOT mutate state in this script.
-- ============================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_missing_caps TEXT[] := ARRAY[]::TEXT[];
    v_missing_functions TEXT[] := ARRAY[]::TEXT[];
    v_missing_users TEXT[] := ARRAY[]::TEXT[];
    v_table_name TEXT;
    v_cap_code TEXT;
    v_fn_name TEXT;
    v_user_email TEXT;
BEGIN
    RAISE NOTICE 'Starting Migration 023 Preflight Verifications...';

    -- 1. Check required authorization tables exist
    FOREACH v_table_name IN ARRAY ARRAY[
        'eco_organizations',
        'eco_user_profiles',
        'eco_organization_members',
        'eco_user_active_context',
        'eco_user_platform_role',
        'eco_capabilities',
        'eco_role_templates',
        'eco_role_template_capabilities',
        'eco_platform_role_org_capabilities',
        'eco_membership_capability_overrides',
        'eco_audit_events',
        'eco_platform_audit_events'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = v_table_name
        ) THEN
            v_missing_tables := array_append(v_missing_tables, v_table_name);
        END IF;
    END LOOP;

    IF array_length(v_missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: Required authorization tables missing: %', array_to_string(v_missing_tables, ', ');
    END IF;

    -- 2. Check canonical private authorization functions exist
    FOREACH v_fn_name IN ARRAY ARRAY[
        'current_profile_id',
        'active_org_id',
        'can_platform',
        'can_org',
        'authorized_orgs_for_capability'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'private' AND p.proname = v_fn_name
        ) THEN
            v_missing_functions := array_append(v_missing_functions, 'private.' || v_fn_name);
        END IF;
    END LOOP;

    IF array_length(v_missing_functions, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: Required private functions missing: %', array_to_string(v_missing_functions, ', ');
    END IF;

    -- 3. Check required role templates exist
    IF NOT EXISTS (SELECT 1 FROM public.eco_role_templates WHERE code = 'PLATFORM_SUPERADMIN' AND is_active = TRUE) OR
       NOT EXISTS (SELECT 1 FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN' AND is_active = TRUE) OR
       NOT EXISTS (SELECT 1 FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN' AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: One or more required role templates (PLATFORM_SUPERADMIN, ACCOUNTING_SUPERADMIN, TENANT_ADMIN) missing or inactive';
    END IF;

    -- 4. Check canonical capability ORG_VIEW exists
    IF NOT EXISTS (
        SELECT 1 FROM public.eco_capabilities
        WHERE code = 'ORG_VIEW' AND scope = 'ORGANIZATION' AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: Active capability ORG_VIEW missing in eco_capabilities';
    END IF;

    -- 5. Check target real users exist in auth.users
    FOREACH v_user_email IN ARRAY ARRAY[
        'vegendigital@gmail.com',
        'drcmarianela@gmail.com',
        'emilianodirosa1@gmail.com',
        'edravi77@gmail.com',
        'calleelcalvario16@gmail.com'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM auth.users WHERE email = v_user_email
        ) THEN
            v_missing_users := array_append(v_missing_users, v_user_email);
        END IF;
    END LOOP;

    IF array_length(v_missing_users, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: Required auth.users missing: %', array_to_string(v_missing_users, ', ');
    END IF;

    -- 6. Check target DEV organizations exist
    IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = '38419581-8163-482c-9813-616fa6214d71'::UUID) OR
       NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID) OR
       NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = '1f5d071f-a09e-4825-9f12-88533383599e'::UUID) THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: One or more target DEV organizations (NORTE, SUR, OESTE) missing';
    END IF;

    RAISE NOTICE 'Migration 023 Preflight Verifications PASSED (All tables, functions, templates, users, and orgs verified).';
END $$;
