-- Manual integration test after the complete capability block, on disposable DEV.
-- Requires 031 -> 032 -> 033. Execute manually as postgres on isolated DEV.
-- Selects platform actors by effective capabilities; verifies the confirmed CONSULTANT tenant preset.
-- All fixture changes and audit events are rolled back. Not run by Jest.
BEGIN;
DO $$
DECLARE
  v_super UUID;
  v_owner UUID;
  v_accounting UUID;
  v_unprivileged UUID;
  candidate RECORD;
  v_admin UUID;
  v_profile UUID;
  v_org UUID;
  v_other_org UUID;
  v_inactive_org UUID;
  v_cap_code TEXT;
  v_membership UUID;
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
  FOR candidate IN SELECT p.* FROM public.eco_user_profiles p WHERE p.is_active LOOP
    PERFORM set_config('request.jwt.claim.sub', candidate.auth_user_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', candidate.auth_user_id, 'role', 'authenticated')::TEXT, true);
    IF private.can_platform('CATALOG_ASSIGN_ANY_ORG') OR private.can_platform('GLOBAL_CATALOG_MANAGE') THEN CONTINUE; END IF;
    FOR v_org IN SELECT m.organization_id FROM public.eco_organization_members m
      JOIN public.eco_role_templates t ON t.id = m.role_template_id
      JOIN public.eco_organizations o ON o.id = m.organization_id
      WHERE m.user_profile_id = candidate.id AND m.is_active AND o.is_active IS TRUE
        AND t.code = 'CONSULTANT' AND t.scope = 'ORGANIZATION' AND t.is_active LOOP
      IF private.can_org(v_org, 'CATALOG_ACTIVITY_MANAGE') AND private.can_org(v_org, 'CATALOG_CATEGORY_MANAGE')
        AND private.can_org(v_org, 'ORG_VIEW') THEN
        v_admin := candidate.auth_user_id;
        v_profile := candidate.id;
        EXIT;
      END IF;
    END LOOP;
    IF v_admin IS NOT NULL THEN EXIT; END IF;
  END LOOP;
  -- Find platform actors independently: do not stop discovery at the tenant actor.
  FOR candidate IN SELECT p.* FROM public.eco_user_profiles p WHERE p.is_active LOOP
    PERFORM set_config('request.jwt.claim.sub', candidate.auth_user_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', candidate.auth_user_id, 'role', 'authenticated')::TEXT, true);
    IF private.can_platform('GLOBAL_CATALOG_MANAGE') AND private.can_platform('CATALOG_ASSIGN_ANY_ORG') THEN
      IF private.can_platform('ACCESS_ANY_ORG') THEN v_owner := candidate.auth_user_id;
      ELSIF private.can_platform('GLOBAL_CATALOG_VIEW') THEN v_accounting := candidate.auth_user_id; END IF;
    END IF;
  END LOOP;
  IF v_owner IS NULL OR v_accounting IS NULL OR v_admin IS NULL THEN
    RAISE EXCEPTION 'Missing effective owner/accounting/CONSULTANT tenant actors; do not grant permissions silently';
  END IF;
  -- Reuse the tenant for a temporary compatibility-role-only test.
  v_unprivileged := v_admin;
  IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id = v_profile) THEN
    RAISE EXCEPTION 'Tenant fixture must have no platform role';
  END IF;
  SELECT id INTO STRICT v_membership FROM public.eco_organization_members
    WHERE user_profile_id = v_profile AND organization_id = v_org AND is_active;
  v_other_org := gen_random_uuid();
  v_inactive_org := gen_random_uuid();
  INSERT INTO public.eco_organizations(id, name, is_active) VALUES
    (v_other_org, '033 active catalog-only target', TRUE),
    (v_inactive_org, '033 inactive target', FALSE);

  IF NOT EXISTS (SELECT 1 FROM public.eco_role_templates
    WHERE code = 'VEGEN_PLATFORM_ADMIN' AND scope = 'PLATFORM' AND is_active) THEN
    RAISE EXCEPTION '031 did not normalize the active owner scope';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_owner::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_owner, 'role', 'authenticated')::TEXT, true);
  IF NOT private.can_platform('ACCESS_ANY_ORG') THEN RAISE EXCEPTION 'Owner lacks ACCESS_ANY_ORG'; END IF;
  FOR v_cap_code IN SELECT c.code FROM private.migration_031_preset_backup b
    JOIN public.eco_capabilities c ON c.id = ANY(b.existing_grants) WHERE c.is_active LOOP
    IF NOT private.can_platform(v_cap_code) THEN RAISE EXCEPTION 'Owner lost existing capability %', v_cap_code; END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.eco_role_templates WHERE code = 'ACCOUNTING_SUPERADMIN' AND is_active) THEN
    RAISE EXCEPTION 'Accounting template is inactive';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_accounting::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_accounting, 'role', 'authenticated')::TEXT, true);
  FOREACH v_cap_code IN ARRAY ARRAY['GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG'] LOOP
    IF NOT private.can_platform(v_cap_code) THEN RAISE EXCEPTION 'Accounting lacks %', v_cap_code; END IF;
  END LOOP;
  IF private.can_platform('ACCESS_ANY_ORG') OR private.can_org(v_other_org, 'ORG_VIEW') THEN
    RAISE EXCEPTION 'Accounting unexpectedly has operational target access';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT EXISTS (SELECT 1 FROM public.list_catalog_assignment_targets() WHERE organization_id = v_other_org)
    OR EXISTS (SELECT 1 FROM public.list_catalog_assignment_targets() WHERE organization_id = v_inactive_org) THEN
    RAISE EXCEPTION 'Catalog target listing does not enforce organization activation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = v_other_org) THEN
    RAISE EXCEPTION 'Catalog permission exposed operational organization SELECT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_other_org) WHERE scope = 'ORGANIZATION') THEN
    RAISE EXCEPTION 'Catalog permission conferred operational organization capabilities';
  END IF;
  EXECUTE 'RESET ROLE';

  UPDATE public.eco_user_profiles SET role = 'USER' WHERE id = v_profile;

  INSERT INTO public.eco_user_active_context(user_profile_id, organization_id)
  VALUES (v_profile, v_org)
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = EXCLUDED.organization_id;

  FOREACH v_super IN ARRAY ARRAY[v_owner, v_accounting] LOOP
  FOREACH v_kind IN ARRAY ARRAY['economic_activity', 'tax_category'] LOOP
    v_table := CASE WHEN v_kind = 'economic_activity' THEN 'eco_org_economic_activities' ELSE 'eco_org_tax_categories' END;
    v_catalog := CASE WHEN v_kind = 'economic_activity' THEN 'eco_economic_activities' ELSE 'eco_tax_categories' END;
    v_key := CASE WHEN v_kind = 'economic_activity' THEN 'activity_id' ELSE 'category_id' END;
    v_cap_code := CASE WHEN v_kind = 'economic_activity' THEN 'CATALOG_ACTIVITY_MANAGE' ELSE 'CATALOG_CATEGORY_MANAGE' END;
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
    IF NOT EXISTS (SELECT 1 FROM public.list_catalog_assignment_state(
      CASE WHEN v_kind = 'economic_activity' THEN 'activity' ELSE 'category' END)
      WHERE organization_id = v_other_org AND item_id = v_foreign_id AND is_assigned AND is_active) THEN
      RAISE EXCEPTION 'Dedicated catalog status RPC omitted assigned target';
    END IF;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE organization_id = $1', v_table) INTO v_count USING v_other_org;
    IF v_count <> 0 THEN RAISE EXCEPTION 'Platform catalog permission bypassed tenant assignment RLS'; END IF;
    FOREACH v_name IN ARRAY ARRAY['assign', 'unassign'] LOOP
      BEGIN
        EXECUTE format('SELECT public.%s_%s_%s_org(p_%s => $1, p_target_org_id => $2)',
          v_name, v_kind, CASE WHEN v_name = 'assign' THEN 'to' ELSE 'from' END, v_key) USING v_id, v_inactive_org;
        RAISE EXCEPTION 'Inactive organization accepted %', v_name;
      EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    END LOOP;
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
    -- Roll back this temporary DENY locally, preserving any original override.
    BEGIN
      INSERT INTO public.eco_membership_capability_overrides(membership_id, capability_id, effect)
      SELECT v_membership, id, 'DENY' FROM public.eco_capabilities WHERE code = v_cap_code
      ON CONFLICT (membership_id, capability_id) DO UPDATE SET effect = 'DENY';
      EXECUTE 'SET LOCAL ROLE authenticated';
      IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_org) WHERE code = v_cap_code) THEN
        RAISE EXCEPTION 'Effective capability RPC ignored membership DENY';
      END IF;
      FOREACH v_name IN ARRAY ARRAY['activate', 'deactivate'] LOOP
        BEGIN
          EXECUTE format('SELECT public.%s_%s($1)', v_name, v_kind) USING v_id;
          RAISE EXCEPTION 'Tenant without manage capability executed %', v_name;
        EXCEPTION WHEN insufficient_privilege THEN NULL; END;
      END LOOP;
      EXECUTE 'RESET ROLE';
      RAISE EXCEPTION 'Restore temporary override' USING ERRCODE = 'Z0033';
    EXCEPTION WHEN SQLSTATE 'Z0033' THEN NULL; END;

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
    -- Operational classification still has its preexisting role gate (outside 033).
    -- Temporarily satisfy it so this assertion reaches the is_assigned check.
    UPDATE public.eco_user_profiles SET role = 'ADMIN' WHERE id = v_profile;
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
    UPDATE public.eco_user_profiles SET role = 'USER' WHERE id = v_profile;
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
  END LOOP; -- owner and accounting actor
  -- Assert effective EXECUTE ACL for every public RPC touched by 030 and 033.
  FOR v_rpc IN SELECT object_name FROM private.migration_030_backup
    WHERE kind = 'function' AND object_name LIKE 'public.%'
    UNION SELECT object_name FROM private.migration_033_backup
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
  UPDATE public.eco_user_profiles SET role = 'SUPERADMIN' WHERE id = v_profile;
  PERFORM set_config('request.jwt.claim.sub', v_unprivileged::TEXT, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_unprivileged, 'role', 'authenticated')::TEXT, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(NULL) WHERE scope = 'PLATFORM') THEN
    RAISE EXCEPTION 'Compatibility SUPERADMIN acquired platform capabilities';
  END IF;
  BEGIN
    PERFORM public.list_catalog_assignment_targets();
    RAISE EXCEPTION 'Compatibility SUPERADMIN obtained catalog targets';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.assign_tax_category_to_org(v_id, NULL::text, v_other_org);
    RAISE EXCEPTION 'Compatibility SUPERADMIN obtained assignment authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.create_global_tax_category('forbidden', '', 'EXPENSE');
    RAISE EXCEPTION 'Compatibility SUPERADMIN granted catalog authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE 'Capability assignment/activation integration checks passed';
END;
$$;
ROLLBACK;
