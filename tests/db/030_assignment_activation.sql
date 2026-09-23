-- Manual integration test, after 030, on a disposable DEV database.
-- Uses existing active PLATFORM_SUPERADMIN and ADMIN identities.
-- All fixture changes and audit events are rolled back. Not run by Jest.
BEGIN;
DO $$
DECLARE
  v_super UUID;
  v_admin UUID;
  v_profile UUID;
  v_org UUID;
  v_other_org UUID;
  v_id UUID;
  v_foreign_id UUID;
  v_kind TEXT;
  v_table TEXT;
  v_catalog TEXT;
  v_key TEXT;
  v_assigned BOOLEAN;
  v_active BOOLEAN;
  v_count BIGINT;
  v_rpc RECORD;
  v_name TEXT;
BEGIN
  SELECT p.auth_user_id INTO STRICT v_super
  FROM public.eco_user_profiles p
  JOIN public.eco_user_platform_role r ON r.user_profile_id = p.id AND r.is_active
  JOIN public.eco_role_templates t ON t.id = r.role_template_id AND t.is_active
  WHERE t.code = 'PLATFORM_SUPERADMIN' AND p.is_active AND p.role = 'SUPERADMIN'
  LIMIT 1;

  SELECT p.auth_user_id, p.id, p.organization_id INTO STRICT v_admin, v_profile, v_org
  FROM public.eco_user_profiles p
  JOIN public.eco_organization_members m
    ON m.user_profile_id = p.id AND m.organization_id = p.organization_id AND m.is_active
  WHERE p.is_active AND p.role = 'ADMIN' LIMIT 1;
  SELECT id INTO STRICT v_other_org FROM public.eco_organizations WHERE id <> v_org LIMIT 1;

  INSERT INTO public.eco_user_active_context(user_profile_id, organization_id)
  VALUES (v_profile, v_org)
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = EXCLUDED.organization_id;

  FOREACH v_kind IN ARRAY ARRAY['economic_activity', 'tax_category'] LOOP
    v_table := CASE WHEN v_kind = 'economic_activity' THEN 'eco_org_economic_activities' ELSE 'eco_org_tax_categories' END;
    v_catalog := CASE WHEN v_kind = 'economic_activity' THEN 'eco_economic_activities' ELSE 'eco_tax_categories' END;
    v_key := CASE WHEN v_kind = 'economic_activity' THEN 'activity_id' ELSE 'category_id' END;
    v_id := gen_random_uuid();
    v_foreign_id := gen_random_uuid();
    IF v_kind = 'economic_activity' THEN
      INSERT INTO public.eco_economic_activities(id, name, arca_code)
      VALUES (v_id, '030 test', v_id::TEXT), (v_foreign_id, '030 foreign', v_foreign_id::TEXT);
    ELSE
      INSERT INTO public.eco_tax_categories(id, name, category_type)
      VALUES (v_id, '030 test', 'EXPENSE'), (v_foreign_id, '030 foreign', 'EXPENSE');
    END IF;

    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
    PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.assign_%s_to_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
    EXECUTE format('SELECT public.assign_%s_to_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_foreign_id, v_other_org;
    EXECUTE 'RESET ROLE';
    EXECUTE format('SELECT is_assigned, is_active FROM public.%I WHERE %I = $1 AND organization_id = $2', v_table, v_key)
      INTO STRICT v_assigned, v_active USING v_id, v_org;
    IF v_assigned IS DISTINCT FROM TRUE OR v_active IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION '%: new assignment must be assigned and active', v_kind;
    END IF;

    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::TEXT, true);
    PERFORM set_config('request.jwt.claim.sub', v_admin::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.deactivate_%s($1)', v_kind) USING v_id;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1 AND NOT is_active AND is_assigned', v_table, v_key)
      INTO v_count USING v_id;
    IF v_count <> 1 THEN RAISE EXCEPTION '%: inactive assignment must remain visible', v_kind; END IF;
    EXECUTE format('SELECT public.activate_%s($1)', v_kind) USING v_id;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1 AND is_active AND is_assigned', v_table, v_key)
      INTO v_count USING v_id;
    IF v_count <> 1 THEN RAISE EXCEPTION '%: reactivation failed', v_kind; END IF;

    BEGIN
      EXECUTE format('SELECT public.activate_%s($1)', v_kind) USING v_foreign_id;
      RAISE EXCEPTION '%: cross-tenant activation allowed', v_kind;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      EXECUTE format('SELECT public.assign_%s_to_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
      RAISE EXCEPTION '%: tenant assignment allowed', v_kind;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      EXECUTE format('SELECT public.unassign_%s_from_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
      RAISE EXCEPTION '%: tenant unassignment allowed', v_kind;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      EXECUTE format('UPDATE public.%I SET is_assigned = FALSE WHERE %I = $1', v_table, v_key) USING v_id;
      RAISE EXCEPTION '%: direct tenant assignment mutation allowed', v_kind;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    EXECUTE format('SELECT public.deactivate_%s($1)', v_kind) USING v_id;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
    PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.unassign_%s_from_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
    EXECUTE 'RESET ROLE';
    EXECUTE format('SELECT is_assigned, is_active FROM public.%I WHERE %I = $1 AND organization_id = $2', v_table, v_key)
      INTO STRICT v_assigned, v_active USING v_id, v_org;
    IF v_assigned IS DISTINCT FROM FALSE OR v_active IS DISTINCT FROM FALSE THEN
      RAISE EXCEPTION '%: unassignment changed activation', v_kind;
    END IF;

    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::TEXT, true);
    PERFORM set_config('request.jwt.claim.sub', v_admin::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1', v_table, v_key) INTO v_count USING v_id;
    IF v_count <> 0 THEN RAISE EXCEPTION '%: tenant can read unassigned row', v_kind; END IF;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE id = $1', v_catalog) INTO v_count USING v_id;
    IF v_count <> 1 THEN RAISE EXCEPTION '%: historical catalog reference is hidden', v_kind; END IF;
    EXECUTE format('SELECT c.name FROM (VALUES ($1::UUID)) historical(item_id) JOIN public.%I c ON c.id = historical.item_id', v_catalog)
      INTO v_name USING v_id;
    IF v_name IS DISTINCT FROM '030 test' THEN RAISE EXCEPTION '%: historical name resolution failed', v_kind; END IF;
    BEGIN
      EXECUTE format('SELECT public.activate_%s($1)', v_kind) USING v_id;
      RAISE EXCEPTION '%: tenant can reactivate unassigned row', v_kind;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    EXECUTE 'RESET ROLE';

    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
    PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.assign_%s_to_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
    EXECUTE 'RESET ROLE';
    EXECUTE format('SELECT is_assigned, is_active FROM public.%I WHERE %I = $1 AND organization_id = $2', v_table, v_key)
      INTO STRICT v_assigned, v_active USING v_id, v_org;
    IF v_assigned IS DISTINCT FROM TRUE OR v_active IS DISTINCT FROM FALSE THEN
      RAISE EXCEPTION '%: reassignment lost activation history', v_kind;
    END IF;

    -- Also preserve TRUE history, but forbid operational use after withdrawal.
    PERFORM set_config('request.jwt.claim.sub', v_admin::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.activate_%s($1)', v_kind) USING v_id;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.unassign_%s_from_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
    EXECUTE 'RESET ROLE';
    EXECUTE format('SELECT is_assigned, is_active FROM public.%I WHERE %I = $1 AND organization_id = $2', v_table, v_key)
      INTO STRICT v_assigned, v_active USING v_id, v_org;
    IF v_assigned IS DISTINCT FROM FALSE OR v_active IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION '%: withdrawal lost TRUE activation history', v_kind;
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.update_record_classification(gen_random_uuid(),
        CASE WHEN v_kind = 'tax_category' THEN v_id ELSE NULL END,
        CASE WHEN v_kind = 'economic_activity' THEN v_id ELSE NULL END);
      RAISE EXCEPTION 'Operational use of withdrawn assignment allowed';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT LIKE '%not assigned to this organization%' THEN RAISE; END IF;
    END;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    EXECUTE format('SELECT public.assign_%s_to_org(p_%s => $1, p_target_org_id => $2)', v_kind, v_key) USING v_id, v_org;
    EXECUTE 'RESET ROLE';
    EXECUTE format('SELECT is_assigned, is_active FROM public.%I WHERE %I = $1 AND organization_id = $2', v_table, v_key)
      INTO STRICT v_assigned, v_active USING v_id, v_org;
    IF v_assigned IS DISTINCT FROM TRUE OR v_active IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION '%: reassignment lost TRUE activation history', v_kind;
    END IF;
  END LOOP;
  -- Assert effective EXECUTE ACL for every public RPC touched by 030.
  FOR v_rpc IN SELECT object_name FROM private.migration_030_backup
    WHERE kind = 'function' AND object_name LIKE 'public.%' LOOP
    IF has_function_privilege('anon', v_rpc.object_name, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon has EXECUTE on %', v_rpc.object_name;
    END IF;
    IF NOT has_function_privilege('authenticated', v_rpc.object_name, 'EXECUTE') THEN
      RAISE EXCEPTION 'authenticated lacks EXECUTE on %', v_rpc.object_name;
    END IF;
  END LOOP;
  EXECUTE 'SET LOCAL ROLE anon';
  BEGIN
    PERFORM public.activate_tax_category(gen_random_uuid());
    RAISE EXCEPTION 'anon execution allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';

  -- An explicit DENY must defeat the SUPERADMIN base template.
  INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id, capability_id, effect)
  SELECT p.id, c.id, 'DENY' FROM public.eco_user_profiles p
  CROSS JOIN public.eco_capabilities c
  WHERE p.auth_user_id = v_super AND c.code = 'GLOBAL_CATALOG_MANAGE'
  ON CONFLICT (user_profile_id, capability_id) DO UPDATE SET effect = 'DENY';
  PERFORM set_config('request.jwt.claim.sub', v_super::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::TEXT, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF (SELECT global_catalog_manage FROM public.get_my_catalog_capabilities()) THEN
    RAISE EXCEPTION 'Capability read RPC ignored GLOBAL_CATALOG_MANAGE DENY';
  END IF;
  FOREACH v_name IN ARRAY ARRAY[
    'SELECT public.create_global_tax_category(''denied'', '''', ''EXPENSE'')',
    'SELECT public.update_global_tax_category(NULL, ''denied'', '''', TRUE)',
    'SELECT public.create_global_economic_activity(''denied'', ''denied'', '''')',
    'SELECT public.update_global_economic_activity(NULL, ''denied'', ''denied'', '''', TRUE)',
    'SELECT public.upsert_arca_activity_catalog(''[]''::JSONB)'
  ] LOOP
    BEGIN
      EXECUTE v_name;
      RAISE EXCEPTION 'GLOBAL_CATALOG_MANAGE DENY bypassed: %', v_name;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE '030 assignment/activation integration checks passed';
END;
$$;
ROLLBACK;
