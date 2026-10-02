-- Supabase SQL Editor, complete script as postgres in isolated DEV after 036 + hotfix 037a.
-- Prepared only: never executed by Jest. All test fixtures revert at final ROLLBACK.
-- On error, roll back the failed transaction before continuing.
BEGIN;
DO $test$
DECLARE
  v_owner UUID := '9563f41e-cd57-42d9-8626-9b04bd6e5863';
  v_owner_auth UUID := 'c1e16acf-a45c-4e51-a3e5-c95208adc3c6';
  v_accounting UUID := 'f922be9a-449d-417f-8003-2143fcbeef02';
  v_legacy UUID;
  v_legacy_auth UUID;
  v_accounting_auth UUID;
  v_clone UUID := gen_random_uuid();
  v_reserved UUID;
  v_delegable UUID;
  v_platform_template UUID := '6331de19-de61-43fb-98cd-7d24f2235359';
  v_row RECORD;
  v_actor RECORD;
  v_expected BOOLEAN;
  v_sql TEXT;
  v_role TEXT;
  v_rel TEXT;
  v_count BIGINT;
  v_regression_member UUID;
  v_regression_cap UUID;
BEGIN
  SELECT p.id,p.auth_user_id INTO STRICT v_legacy,v_legacy_auth FROM public.eco_user_profiles p
    JOIN auth.users u ON u.id=p.auth_user_id
    WHERE u.email='emilianodirosa1+horeca-dev@gmail.com' AND p.is_active AND p.role='SUPERADMIN';
  SELECT auth_user_id INTO STRICT v_accounting_auth FROM public.eco_user_profiles WHERE id=v_accounting AND is_active;
  SELECT id INTO STRICT v_reserved FROM public.eco_capabilities WHERE code='ACCESS_ANY_ORG';
  SELECT id INTO STRICT v_delegable FROM public.eco_capabilities WHERE code='GLOBAL_CATALOG_VIEW';

  -- Helpers run as the SQL Editor administrator with simulated JWT; no private USAGE granted.
  FOR v_actor IN SELECT * FROM (VALUES (v_owner_auth,TRUE),(v_accounting_auth,FALSE),(v_legacy_auth,FALSE)) x(auth_id,is_owner) LOOP
    PERFORM set_config('request.jwt.claim.sub',v_actor.auth_id::TEXT,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_actor.auth_id,'role','authenticated')::TEXT,true);
    IF private.is_platform_owner() IS DISTINCT FROM v_actor.is_owner THEN RAISE EXCEPTION 'Structural owner mismatch'; END IF;
    FOR v_row IN SELECT code FROM public.eco_capabilities WHERE delegation_class='OWNER_RESERVED' LOOP
      IF private.can_platform(v_row.code) IS DISTINCT FROM v_actor.is_owner THEN
        RAISE EXCEPTION 'Reserved authority mismatch for %',v_row.code; END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  IF private.is_platform_owner() THEN RAISE EXCEPTION 'Unauthenticated owner'; END IF;

  -- All delegable PLATFORM results equal the reviewed original helper for owner/accountant.
  FOR v_actor IN SELECT id,auth_user_id FROM public.eco_user_profiles WHERE id IN (v_owner,v_accounting) LOOP
    PERFORM set_config('request.jwt.claim.sub',v_actor.auth_user_id::TEXT,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_actor.auth_user_id,'role','authenticated')::TEXT,true);
    FOR v_row IN SELECT * FROM public.eco_capabilities WHERE scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE' LOOP
      SELECT v_row.is_active AND COALESCE(o.effect<>'DENY',TRUE) AND
        (COALESCE(o.effect='ALLOW',FALSE) OR EXISTS (
          SELECT 1 FROM public.eco_user_platform_role r JOIN public.eco_role_templates t ON t.id=r.role_template_id
          JOIN public.eco_role_template_capabilities g ON g.role_template_id=t.id
          WHERE r.user_profile_id=v_actor.id AND r.is_active AND t.is_active AND t.scope='PLATFORM' AND g.capability_id=v_row.id))
      INTO v_expected FROM (SELECT 1) seed LEFT JOIN public.eco_user_platform_capability_overrides o
        ON o.user_profile_id=v_actor.id AND o.capability_id=v_row.id;
      IF private.can_platform(v_row.code) IS DISTINCT FROM v_expected THEN RAISE EXCEPTION 'Delegable regression: %',v_row.code; END IF;
    END LOOP;
  END LOOP;

  -- Clone owner presentation template and ALL remaining grants: cannot copy structural authority.
  INSERT INTO public.eco_role_templates(id,code,name,scope,is_active,is_system)
  SELECT v_clone,'TEST_036_'||v_clone::TEXT,name,scope,TRUE,FALSE FROM public.eco_role_templates WHERE id=v_platform_template;
  INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
  SELECT v_clone,capability_id FROM public.eco_role_template_capabilities WHERE role_template_id=v_platform_template;
  INSERT INTO public.eco_user_platform_role(user_profile_id,role_template_id,is_active)
  VALUES (v_legacy,v_clone,TRUE) ON CONFLICT(user_profile_id) DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=TRUE;
  PERFORM set_config('request.jwt.claim.sub',v_legacy_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_legacy_auth,'role','authenticated')::TEXT,true);
  IF private.is_platform_owner() OR private.can_platform('ACCESS_ANY_ORG') THEN RAISE EXCEPTION 'Cloned template escalated'; END IF;
  UPDATE public.eco_user_platform_role SET role_template_id=v_platform_template WHERE user_profile_id=v_legacy;
  IF private.is_platform_owner() OR private.can_platform('ACCESS_ANY_ORG') THEN RAISE EXCEPTION 'Owner template assignment escalated'; END IF;

  -- Delegable ALLOW works without a base grant, DENY beats a grant, removing it restores base.
  UPDATE public.eco_user_platform_role SET role_template_id=v_clone WHERE user_profile_id=v_legacy;
  DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=v_clone AND capability_id=v_delegable;
  INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
  VALUES(v_legacy,v_delegable,'ALLOW') ON CONFLICT(user_profile_id,capability_id) DO UPDATE SET effect='ALLOW';
  IF NOT private.can_platform('GLOBAL_CATALOG_VIEW') THEN RAISE EXCEPTION 'ALLOW regression'; END IF;
  INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES(v_clone,v_delegable);
  UPDATE public.eco_user_platform_capability_overrides SET effect='DENY' WHERE user_profile_id=v_legacy AND capability_id=v_delegable;
  IF private.can_platform('GLOBAL_CATALOG_VIEW') THEN RAISE EXCEPTION 'DENY regression'; END IF;
  DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=v_legacy AND capability_id=v_delegable;
  IF NOT private.can_platform('GLOBAL_CATALOG_VIEW') THEN RAISE EXCEPTION 'Base grant regression'; END IF;
  INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES(v_legacy,v_delegable,'ALLOW');

  -- Actual DML under administrator reaches triggers, not just table ACL denials.
  FOREACH v_sql IN ARRAY ARRAY[
    'INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES($1,$2,''ALLOW'')',
    'INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES($3,$2)',
    'INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES($3,$2)',
    'UPDATE public.eco_user_platform_capability_overrides SET capability_id=$2 WHERE user_profile_id=$1 AND capability_id=$4',
    'UPDATE public.eco_role_template_capabilities SET capability_id=$2 WHERE role_template_id=$3 AND capability_id=$4',
    'UPDATE public.eco_capabilities SET delegation_class=''PLATFORM_DELEGABLE'' WHERE id=$2',
    'UPDATE public.eco_capabilities SET scope=''ORGANIZATION'' WHERE id=$2',
    'UPDATE public.eco_role_templates SET scope=''ORGANIZATION'' WHERE id=$3'
  ] LOOP
    BEGIN
      EXECUTE v_sql USING v_legacy,v_reserved,v_clone,v_delegable;
      RAISE EXCEPTION 'Forbidden delegation accepted: %',v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  -- Regression discovered by harness 037; passes after hotfix 037a.
  -- A valid membership row has no role_template_id: INSERT/UPDATE must not raise 42703.
  SELECT id INTO v_regression_member FROM public.eco_organization_members ORDER BY id LIMIT 1;
  IF v_regression_member IS NULL THEN RAISE EXCEPTION '036 regression requires an existing membership'; END IF;
  SELECT id INTO STRICT v_regression_cap FROM public.eco_capabilities WHERE code='RECORD_VIEW' AND scope='ORGANIZATION' AND is_active;
  DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=v_regression_member AND capability_id=v_regression_cap;
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(v_regression_member,v_regression_cap,'ALLOW');
  UPDATE public.eco_membership_capability_overrides SET effect='DENY' WHERE membership_id=v_regression_member AND capability_id=v_regression_cap;
  IF NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE membership_id=v_regression_member AND capability_id=v_regression_cap AND effect='DENY') THEN RAISE EXCEPTION 'Membership DENY regression'; END IF;
  DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=v_regression_member AND capability_id=v_regression_cap;
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(v_regression_member,v_regression_cap,'DENY');
  UPDATE public.eco_membership_capability_overrides SET effect='ALLOW' WHERE membership_id=v_regression_member AND capability_id=v_regression_cap;
  IF NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE membership_id=v_regression_member AND capability_id=v_regression_cap AND effect='ALLOW') THEN RAISE EXCEPTION 'Membership ALLOW regression'; END IF;
  -- Owner also cannot delegate its core through ordinary grant tables.
  PERFORM set_config('request.jwt.claim.sub',v_owner_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner_auth,'role','authenticated')::TEXT,true);
  BEGIN
    INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES(v_platform_template,v_reserved);
    RAISE EXCEPTION 'Owner delegated reserved capability';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  FOREACH v_sql IN ARRAY ARRAY[
    'UPDATE public.eco_user_profiles SET is_active=FALSE WHERE id=$1',
    'UPDATE public.eco_user_profiles SET auth_user_id=gen_random_uuid() WHERE id=$1',
    'DELETE FROM public.eco_user_profiles WHERE id=$1',
    'UPDATE public.eco_user_platform_role SET role_template_id=$2 WHERE user_profile_id=$1',
    'DELETE FROM public.eco_user_platform_role WHERE user_profile_id=$1',
    'DELETE FROM private.eco_platform_owner',
    'UPDATE private.eco_platform_owner SET user_profile_id=$3',
    'TRUNCATE private.eco_platform_owner',
    'UPDATE public.eco_role_templates SET is_active=FALSE WHERE id=$4',
    'UPDATE public.eco_capabilities SET is_active=FALSE WHERE id=$5'
  ] LOOP
    BEGIN
      EXECUTE v_sql USING v_owner,v_clone,v_legacy,v_platform_template,v_reserved;
      RAISE EXCEPTION 'Owner protection bypass: %',v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH v_rel IN ARRAY ARRAY['private.eco_platform_owner','private.eco_owner_reserved_capabilities','private.migration_036_backup'] LOOP
      IF has_table_privilege(v_role,v_rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
        RAISE EXCEPTION 'Private table exposed to %: %',v_role,v_rel; END IF;
    END LOOP;
    FOR v_row IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='private' AND (p.proname='is_platform_owner' OR p.proname LIKE 'guard_036_%') LOOP
      IF has_function_privilege(v_role,v_row.signature,'EXECUTE') THEN RAISE EXCEPTION 'Private helper exposed: %',v_row.signature; END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('anon','public.get_capability_delegation_contract()','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.get_capability_delegation_contract()','EXECUTE') THEN
    RAISE EXCEPTION 'Delegation metadata RPC ACL mismatch'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  -- Public boundary only while restricted: metadata is not a delegation authorization.
  IF EXISTS (SELECT 1 FROM public.get_capability_delegation_contract() WHERE delegation_class='OWNER_RESERVED' AND is_delegable) THEN
    RAISE EXCEPTION 'Reserved marked delegable'; END IF;
  SELECT count(*) INTO v_count FROM public.get_capability_delegation_contract() WHERE delegation_class='OWNER_RESERVED';
  IF v_count<>11 THEN RAISE EXCEPTION 'Owner classification metadata incomplete'; END IF;
  SELECT count(*) INTO v_count FROM public.get_my_effective_capabilities(NULL) WHERE code IN
    ('PLATFORM_MANAGE','GLOBAL_USER_MANAGE','PLAN_MANAGE','ACCESS_ANY_ORG','SUPPORT_IMPERSONATE','HARD_DELETE_EXCEPTIONAL',
     'ORGANIZATION_CREATE','ORGANIZATION_ARCHIVE','PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION','PLATFORM_SYSTEM_MONITOR');
  IF v_count<>11 THEN RAISE EXCEPTION 'Owner public capabilities incomplete'; END IF;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claim.sub',v_legacy_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_legacy_auth,'role','authenticated')::TEXT,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF EXISTS (SELECT 1 FROM public.get_capability_delegation_contract() WHERE delegation_class='OWNER_RESERVED') THEN
    RAISE EXCEPTION 'Reserved metadata visible to non-owner'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(NULL) WHERE code IN
    ('PLATFORM_MANAGE','GLOBAL_USER_MANAGE','PLAN_MANAGE','ACCESS_ANY_ORG','SUPPORT_IMPERSONATE','HARD_DELETE_EXCEPTIONAL',
     'ORGANIZATION_CREATE','ORGANIZATION_ARCHIVE','PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION','PLATFORM_SYSTEM_MONITOR')) THEN
    RAISE EXCEPTION 'Public effective capabilities leaked owner authority'; END IF;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE '036 owner, delegation, compatibility and ACL tests passed; fixtures roll back';
END;
$test$;
ROLLBACK;
