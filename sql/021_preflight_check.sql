-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 021 (WP-A3.2.0)
-- ============================================================
-- Verifies baseline schema, M019/M020 tables and function existence
-- before applying WP-A3.2.0 performance indexes & helper primitives.
-- ============================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_table_name TEXT;
    v_missing_functions TEXT[] := ARRAY[]::TEXT[];
    v_fn_name TEXT;
BEGIN
    RAISE NOTICE 'Starting Migration 021 Preflight Checks...';

    -- 1. Check required tables from M019/M020
    FOREACH v_table_name IN ARRAY ARRAY[
        'eco_capabilities',
        'eco_role_templates',
        'eco_role_template_capabilities',
        'eco_platform_role_org_capabilities',
        'eco_membership_capability_overrides',
        'eco_user_platform_role',
        'eco_user_platform_capability_overrides',
        'eco_user_active_context',
        'eco_organization_members',
        'eco_user_profiles',
        'eco_organizations'
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
        RAISE EXCEPTION 'Preflight FAILED: Required authorization tables missing: %', array_to_string(v_missing_tables, ', ');
    END IF;

    -- 2. Check existing core functions from M019
    FOREACH v_fn_name IN ARRAY ARRAY[
        'current_profile_id',
        'active_org_id',
        'can_platform',
        'can_org'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'private' AND p.proname = v_fn_name
        ) THEN
            v_missing_functions := array_append(v_missing_functions, v_fn_name);
        END IF;
    END LOOP;

    IF array_length(v_missing_functions, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight FAILED: Core private functions missing: %', array_to_string(v_missing_functions, ', ');
    END IF;

    RAISE NOTICE 'Migration 021 Preflight Passed: All baseline tables and functions present.';
END $$;
