-- ============================================================
-- PREFLIGHT CHECK FOR MIGRATION 019 (WP-A1 CAPABILITY FOUNDATION)
-- ============================================================
-- Read-only verification of existing schema invariants before WP-A1.
-- Fails closed with explicit exception if baseline prerequisites are missing.

DO $$
BEGIN
  -- 1. Verify schema prerequisites
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'private'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: private schema does not exist';
  END IF;

  -- 2. Verify baseline table existence
  IF EXISTS (
    SELECT 1 FROM (
      VALUES ('eco_user_profiles'), ('eco_organizations'), ('eco_organization_members')
    ) AS required(tablename)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = required.tablename
    )
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: One or more baseline core tables (eco_user_profiles, eco_organizations, eco_organization_members) are missing.';
  END IF;

  -- 3. Verify membership unique invariant UNIQUE(organization_id, user_profile_id)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.eco_organization_members'::regclass
      AND contype IN ('u', 'p')
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: eco_organization_members missing unique membership constraint';
  END IF;

  -- 4. Verify legacy profile columns remain intact
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'organization_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'role'
  ) THEN
    RAISE EXCEPTION 'Preflight FAILED: eco_user_profiles missing legacy organization_id or role column';
  END IF;

  -- 5. Verify auth.uid() function contract
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p 
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace 
    WHERE n.nspname = 'auth' AND p.proname = 'uid'
  ) THEN
    RAISE EXCEPTION 'Preflight check FAILED: Function auth.uid() does not exist.';
  END IF;

  RAISE NOTICE 'Preflight check PASSED for Migration 019 (WP-A1 Capability Foundation).';
END $$;
