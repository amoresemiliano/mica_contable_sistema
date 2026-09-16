-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 023 (WP-AUTH-RESET-1)
-- ============================================================
-- Verifies structural prerequisites only:
-- - Required database tables exist
-- - Required foreign key columns exist
-- - Required real user accounts exist in auth.users
-- - Target DEV organizations exist in public.eco_organizations
--
-- NOTE: Does NOT check for canonical role templates or capability
-- mappings, as Migration 023 itself creates and reconciles them
-- idempotently.
--
-- DO NOT mutate state in this script.
-- ============================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_missing_columns TEXT[] := ARRAY[]::TEXT[];
    v_missing_users TEXT[] := ARRAY[]::TEXT[];
    v_table_name TEXT;
    v_user_email TEXT;
BEGIN
    RAISE NOTICE 'Starting Migration 023 Preflight Structural Verifications...';

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

    -- 2. Check required columns on eco_role_templates
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'eco_role_templates' AND column_name = 'scope'
    ) THEN
        v_missing_columns := array_append(v_missing_columns, 'eco_role_templates.scope');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'eco_role_templates' AND column_name = 'is_active'
    ) THEN
        v_missing_columns := array_append(v_missing_columns, 'eco_role_templates.is_active');
    END IF;

    IF array_length(v_missing_columns, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: Required table columns missing: %', array_to_string(v_missing_columns, ', ');
    END IF;

    -- 3. Check target real users exist in auth.users
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

    -- 4. Check target DEV organizations exist in public.eco_organizations
    IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = '38419581-8163-482c-9813-616fa6214d71'::UUID) OR
       NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID) OR
       NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = '1f5d071f-a09e-4825-9f12-88533383599e'::UUID) THEN
        RAISE EXCEPTION 'Preflight 023 FAILED: One or more target DEV organizations (NORTE, SUR, OESTE) missing';
    END IF;

    RAISE NOTICE 'Migration 023 Preflight Structural Verifications PASSED (All tables, columns, users, and organizations verified).';
END $$;
