-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 017 (SUPERADMIN MULTITENANT CONTEXT)
-- ============================================================
-- Must fail closed with explicit exception if any expected contract is absent.

DO $$
BEGIN
  -- 1. Verify required tables
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_organizations') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_organizations does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_user_profiles') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_user_profiles does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_org_tax_categories') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_org_tax_categories does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_org_economic_activities') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_org_economic_activities does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_org_activity_iibb_rates') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_org_activity_iibb_rates does not exist.';
  END IF;

  -- 2. Verify required columns in eco_user_profiles
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'auth_user_id') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Column eco_user_profiles.auth_user_id does not exist.';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'firebase_uid') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Legacy column eco_user_profiles.firebase_uid MUST NOT exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'role') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Column eco_user_profiles.role does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'organization_id') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Column eco_user_profiles.organization_id does not exist.';
  END IF;

  -- 3. Verify private schema support functions
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'private' AND p.proname = 'org_id'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function private.org_id() does not exist.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'private' AND p.proname = 'func_role'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function private.func_role() does not exist.';
  END IF;

  -- 4. Verify auth.uid() function contract
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'auth' AND p.proname = 'uid'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function auth.uid() does not exist.';
  END IF;

  RAISE NOTICE 'Preflight check PASSED for Migration 017.';
END $$;

-- Informational contract inspection
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'eco_user_profiles'
  AND column_name IN ('auth_user_id', 'role', 'organization_id', 'firebase_uid');
