-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 022 (WP-A3.2.1)
-- ============================================================
-- Verifies baseline schema, M019/M020/M021 tables, capability codes,
-- functions, columns, and append-only trigger before applying M022.
-- DO NOT mutate state in this script.
-- ============================================================

DO $$
DECLARE
    v_missing_tables TEXT[] := ARRAY[]::TEXT[];
    v_missing_caps TEXT[] := ARRAY[]::TEXT[];
    v_missing_functions TEXT[] := ARRAY[]::TEXT[];
    v_missing_columns TEXT[] := ARRAY[]::TEXT[];
    v_table_name TEXT;
    v_cap_code TEXT;
    v_fn_name TEXT;
BEGIN
    RAISE NOTICE 'Starting Migration 022 Preflight Checks...';

    -- 1. Check required tables
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
        'eco_organizations',
        'eco_audit_events'
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

    -- 2. Check required active capability codes
    FOREACH v_cap_code IN ARRAY ARRAY[
        'ORG_VIEW',
        'ORG_MEMBER_VIEW',
        'ORG_MEMBER_MANAGE',
        'ORG_MEMBER_PERMISSION_MANAGE',
        'AUDIT_VIEW_ORG',
        'SUPPORT_IMPERSONATE',
        'ACCESS_ANY_ORG'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.eco_capabilities
            WHERE code = v_cap_code AND is_active = TRUE
        ) THEN
            v_missing_caps := array_append(v_missing_caps, v_cap_code);
        END IF;
    END LOOP;

    IF array_length(v_missing_caps, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight FAILED: Required active capabilities missing: %', array_to_string(v_missing_caps, ', ');
    END IF;

    -- 3. Check M019 / M021 private helper functions exist
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

    -- 4. Check existing target public RPCs exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'change_user_role'
    ) THEN
        v_missing_functions := array_append(v_missing_functions, 'public.change_user_role');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'set_user_active'
    ) THEN
        v_missing_functions := array_append(v_missing_functions, 'public.set_user_active');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'switch_superadmin_org_context'
    ) THEN
        v_missing_functions := array_append(v_missing_functions, 'public.switch_superadmin_org_context');
    END IF;

    IF array_length(v_missing_functions, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight FAILED: Required functions missing: %', array_to_string(v_missing_functions, ', ');
    END IF;

    -- 5. Check required columns exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'auth_user_id'
    ) THEN
        v_missing_columns := array_append(v_missing_columns, 'public.eco_user_profiles.auth_user_id');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'eco_organization_members' AND column_name = 'user_profile_id'
    ) THEN
        v_missing_columns := array_append(v_missing_columns, 'public.eco_organization_members.user_profile_id');
    END IF;

    IF array_length(v_missing_columns, 1) > 0 THEN
        RAISE EXCEPTION 'Preflight FAILED: Required schema columns missing: %', array_to_string(v_missing_columns, ', ');
    END IF;

    -- 6. Check required trigger enforce_append_only_audit on eco_audit_events
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' 
          AND c.relname = 'eco_audit_events' 
          AND t.tgname = 'enforce_append_only_audit'
    ) THEN
        RAISE EXCEPTION 'Preflight FAILED: Trigger enforce_append_only_audit on eco_audit_events is missing';
    END IF;

    RAISE NOTICE 'Migration 022 Preflight Passed: Baseline state is verified and valid for WP-A3.2.1.';
END $$;
