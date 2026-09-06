-- ============================================================
-- POSTCHECK FOR MIGRATION 019 (WP-A1 CAPABILITY FOUNDATION)
-- ============================================================
-- Validates that WP-A1 capability foundation schema and seed data
-- are completely created without altering baseline schema or application RLS.

DO $$
DECLARE
  v_count INT;
  v_fk_confdeltype CHAR;
BEGIN
  -- 1. Verify existence of all 8 new tables
  IF EXISTS (
    SELECT 1 FROM (
      VALUES 
        ('eco_capabilities'),
        ('eco_role_templates'),
        ('eco_role_template_capabilities'),
        ('eco_platform_role_org_capabilities'),
        ('eco_membership_capability_overrides'),
        ('eco_user_platform_role'),
        ('eco_user_platform_capability_overrides'),
        ('eco_user_active_context')
    ) AS req(tablename)
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = req.tablename
    )
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: One or more WP-A1 foundation tables are missing.';
  END IF;

  -- 2. Verify evolved column role_template_id on eco_organization_members
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_organization_members' AND column_name = 'role_template_id'
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: eco_organization_members.role_template_id column does not exist.';
  END IF;

  -- 3. Verify ON DELETE SET NULL on eco_user_active_context.organization_id
  SELECT confdeltype INTO v_fk_confdeltype
  FROM pg_constraint
  WHERE conrelid = 'public.eco_user_active_context'::regclass
    AND contype = 'f'
    AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.eco_user_active_context'::regclass AND attname = 'organization_id')];

  IF v_fk_confdeltype != 'n' THEN -- 'n' = SET NULL in pg_constraint
    RAISE EXCEPTION 'Postcheck FAILED: eco_user_active_context.organization_id FK is NOT ON DELETE SET NULL (got confdeltype %).', v_fk_confdeltype;
  END IF;

  -- 4. Verify UNIQUE(organization_id, user_profile_id) invariant
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conrelid = 'public.eco_organization_members'::regclass
      AND c.contype IN ('u', 'p')
      AND (
        SELECT ARRAY_AGG(attname ORDER BY attname)
        FROM pg_attribute
        WHERE attrelid = c.conrelid
          AND attnum = ANY(c.conkey)
      ) = ARRAY['organization_id', 'user_profile_id']::name[]
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: eco_organization_members unique membership constraint is missing.';
  END IF;

  -- 5. Verify legacy columns eco_user_profiles.organization_id and role remain
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'organization_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'role'
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: eco_user_profiles legacy organization_id or role column was altered/removed.';
  END IF;

  -- 6. Verify helper functions in private schema
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'current_profile_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'active_org_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'can_platform'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'private' AND p.proname = 'can_org'
  ) THEN
    RAISE EXCEPTION 'Postcheck FAILED: One or more private authorization helper functions (current_profile_id, active_org_id, can_platform, can_org) are missing.';
  END IF;

  -- 7. Seed Data Verification
  SELECT COUNT(*) INTO v_count FROM public.eco_capabilities;
  IF v_count < 42 THEN
    RAISE EXCEPTION 'Postcheck FAILED: Expected 42 capabilities, found %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_role_templates;
  IF v_count < 8 THEN
    RAISE EXCEPTION 'Postcheck FAILED: Expected 8 role templates, found %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_platform_role_org_capabilities;
  IF v_count < 20 THEN
    RAISE EXCEPTION 'Postcheck FAILED: ACCOUNTING_SUPERADMIN organization capability bridge missing entries (got %)', v_count;
  END IF;

  RAISE NOTICE 'Postcheck PASSED for Migration 019 (WP-A1 Capability Foundation). All tables, constraints, seeds, and helpers verified.';
END $$;
