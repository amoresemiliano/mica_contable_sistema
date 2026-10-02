-- ============================================================
-- POSTCHECK SCRIPT FOR MIGRATION 022 (WP-A3.2.1)
-- ============================================================
-- Verifies that all target RPCs, platform audit table, and RLS policies
-- have been successfully migrated to the capability architecture and
-- no legacy role checks remain.
-- ============================================================

DO $$
DECLARE
    v_proc_def TEXT;
    v_pol_count INT;
    v_sec_def BOOLEAN;
    v_search_path TEXT;
    v_rls_enabled BOOLEAN;
BEGIN
    RAISE NOTICE 'Starting Migration 022 Postcheck Verifications...';

    -- 1. Check change_user_role definition & properties
    SELECT prosrc, prosecdef, proconfig
    INTO v_proc_def, v_sec_def, v_search_path
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'change_user_role';

    IF v_proc_def IS NULL THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.change_user_role does not exist';
    END IF;

    IF NOT v_sec_def THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.change_user_role is not SECURITY DEFINER';
    END IF;

    IF v_proc_def ILIKE '%func_role%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.change_user_role still contains legacy func_role() checks';
    END IF;

    IF v_proc_def NOT ILIKE '%ORG_MEMBER_PERMISSION_MANAGE%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.change_user_role does not enforce ORG_MEMBER_PERMISSION_MANAGE';
    END IF;

    IF v_proc_def NOT ILIKE '%eco_organization_members%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.change_user_role does not update eco_organization_members';
    END IF;

    -- 2. Check set_user_active (tenant scoped) definition & properties
    SELECT prosrc, prosecdef, v_search_path
    INTO v_proc_def, v_sec_def, v_search_path
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'set_user_active';

    IF v_proc_def IS NULL THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_user_active does not exist';
    END IF;

    IF NOT v_sec_def THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_user_active is not SECURITY DEFINER';
    END IF;

    IF v_proc_def ILIKE '%func_role%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_user_active still contains legacy func_role() checks';
    END IF;

    IF v_proc_def NOT ILIKE '%ORG_MEMBER_MANAGE%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_user_active does not enforce ORG_MEMBER_MANAGE';
    END IF;

    IF v_proc_def NOT ILIKE '%eco_organization_members%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_user_active does not operate on eco_organization_members';
    END IF;

    -- 3. Check set_global_user_active (platform scoped) definition & properties
    SELECT prosrc, prosecdef, v_search_path
    INTO v_proc_def, v_sec_def, v_search_path
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'set_global_user_active';

    IF v_proc_def IS NULL THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_global_user_active does not exist';
    END IF;

    IF NOT v_sec_def THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_global_user_active is not SECURITY DEFINER';
    END IF;

    IF v_proc_def NOT ILIKE '%GLOBAL_USER_MANAGE%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_global_user_active does not enforce GLOBAL_USER_MANAGE';
    END IF;

    IF v_proc_def NOT ILIKE '%eco_user_profiles%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_global_user_active does not operate on eco_user_profiles';
    END IF;

    IF v_proc_def NOT ILIKE '%eco_platform_audit_events%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.set_global_user_active does not emit to eco_platform_audit_events';
    END IF;

    -- 4. Check switch_superadmin_org_context definition & properties
    SELECT prosrc, prosecdef, v_search_path
    INTO v_proc_def, v_sec_def, v_search_path
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'switch_superadmin_org_context';

    IF v_proc_def IS NULL THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context does not exist';
    END IF;

    IF NOT v_sec_def THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context is not SECURITY DEFINER';
    END IF;

    IF v_proc_def NOT ILIKE '%SUPPORT_IMPERSONATE%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context does not enforce SUPPORT_IMPERSONATE';
    END IF;

    IF v_proc_def NOT ILIKE '%eco_platform_audit_events%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context does not emit to eco_platform_audit_events';
    END IF;

    -- 5. Check platform audit table, append-only trigger, and RLS
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'eco_platform_audit_events'
    ) THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.eco_platform_audit_events table does not exist';
    END IF;

    SELECT relrowsecurity INTO v_rls_enabled
    FROM pg_class
    WHERE relname = 'eco_platform_audit_events';

    IF NOT v_rls_enabled THEN
        RAISE EXCEPTION 'Postcheck FAILED: RLS is not enabled on public.eco_platform_audit_events';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'enforce_append_only_platform_audit'
    ) THEN
        RAISE EXCEPTION 'Postcheck FAILED: enforce_append_only_platform_audit trigger is missing on eco_platform_audit_events';
    END IF;

    -- 6. Check RLS policies on eco_organizations
    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'eco_organizations'
      AND cmd = 'SELECT' AND qual ILIKE '%authorized_orgs_for_capability%ORG_VIEW%';

    IF v_pol_count = 0 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Capability policy for eco_organizations missing';
    END IF;

    -- 7. Check RLS policies on eco_user_profiles
    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'eco_user_profiles'
      AND cmd = 'SELECT' AND qual ILIKE '%authorized_orgs_for_capability%ORG_MEMBER_VIEW%';

    IF v_pol_count = 0 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Capability policy for eco_user_profiles missing';
    END IF;

    -- 8. Check RLS policies on eco_audit_events
    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'eco_audit_events'
      AND cmd = 'SELECT' AND qual ILIKE '%authorized_orgs_for_capability%AUDIT_VIEW_ORG%';

    IF v_pol_count = 0 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Capability policy for eco_audit_events missing';
    END IF;

    -- 9. Check RLS policy on eco_platform_audit_events
    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'eco_platform_audit_events'
      AND cmd = 'SELECT' AND (qual ILIKE '%AUDIT_PLATFORM_VIEW%' OR qual ILIKE '%PLATFORM_MANAGE%');

    IF v_pol_count = 0 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Platform capability policy for eco_platform_audit_events missing';
    END IF;

    RAISE NOTICE 'Migration 022 Postcheck Verifications PASSED (All RPCs, platform audit table, triggers, and set-based RLS policies verified).';
END $$;
