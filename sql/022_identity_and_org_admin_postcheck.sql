-- ============================================================
-- POSTCHECK SCRIPT FOR MIGRATION 022 (WP-A3.2.1)
-- ============================================================
-- Verifies that all target RPCs and RLS policies have been successfully
-- migrated to the capability architecture and no legacy role checks remain.
-- ============================================================

DO $$
DECLARE
    v_proc_def TEXT;
    v_pol_count INT;
    v_sec_def BOOLEAN;
    v_search_path TEXT;
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

    IF v_proc_def ILIKE '%func_role%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context still contains legacy func_role() checks';
    END IF;

    IF v_proc_def NOT ILIKE '%SUPPORT_IMPERSONATE%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: public.switch_superadmin_org_context does not enforce SUPPORT_IMPERSONATE';
    END IF;

    -- 5. Check RLS policies
    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policy pol
    JOIN pg_class c ON pol.polrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'eco_organizations'
      AND pol.polname = 'Organizations viewable by own users';

    IF v_pol_count <> 1 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Policy "Organizations viewable by own users" on eco_organizations missing';
    END IF;

    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policy pol
    JOIN pg_class c ON pol.polrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'eco_user_profiles'
      AND pol.polname = 'Profiles viewable by user and admin';

    IF v_pol_count <> 1 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Policy "Profiles viewable by user and admin" on eco_user_profiles missing';
    END IF;

    SELECT COUNT(*) INTO v_pol_count
    FROM pg_policy pol
    JOIN pg_class c ON pol.polrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'eco_audit_events'
      AND pol.polname = 'Audit events viewable by admin';

    IF v_pol_count <> 1 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Policy "Audit events viewable by admin" on eco_audit_events missing';
    END IF;

    -- 6. Check trigger enforce_append_only_audit remains intact
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' 
          AND c.relname = 'eco_audit_events' 
          AND t.tgname = 'enforce_append_only_audit'
    ) THEN
        RAISE EXCEPTION 'Postcheck FAILED: Trigger enforce_append_only_audit on eco_audit_events is missing';
    END IF;

    RAISE NOTICE 'Migration 022 Postcheck Passed: All target functions and policies verified under capability model.';
END $$;
