-- SQL Editor after 037 as postgres. Prepared only, NOT executed by Jest.
-- Existing DEV identities; every fixture and context change is rolled back.
BEGIN;
DO $test$
DECLARE
  v_root UUID := '9563f41e-cd57-42d9-8626-9b04bd6e5863';
  v_root_auth UUID := 'c1e16acf-a45c-4e51-a3e5-c95208adc3c6';
  v_account UUID := 'f922be9a-449d-417f-8003-2143fcbeef02';
  v_account_auth UUID;
  v_north UUID := '38419581-8163-482c-9813-616fa6214d71';
  v_south UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979';
  v_cap UUID;
  v_template UUID;
  v_account_template UUID;
  v_member UUID;
  v_tenant_profile UUID;
  v_tenant_auth UUID;
  v_tenant_org UUID;
  v_expected BOOLEAN;
  v_allowed_count INTEGER := 0;
  v_row RECORD;
  v_role TEXT;
  v_relation TEXT;
BEGIN
  SELECT auth_user_id INTO STRICT v_account_auth FROM public.eco_user_profiles WHERE id=v_account AND is_active;
  SELECT id INTO STRICT v_cap FROM public.eco_capabilities WHERE code='RECORD_VIEW' AND scope='ORGANIZATION' AND is_active;
  SELECT role_template_id INTO STRICT v_template FROM public.eco_user_platform_role WHERE user_profile_id=v_root AND is_active;
  SELECT role_template_id INTO STRICT v_account_template FROM public.eco_user_platform_role WHERE user_profile_id=v_account AND is_active;
  IF (SELECT count(*) FROM public.eco_organizations WHERE id IN(v_north,v_south) AND is_active)<>2 THEN
    RAISE EXCEPTION '037 fixture requires active NORTE and SUR'; END IF;
  -- Remove only transaction-local authority that could mask the negative cases.
  DELETE FROM public.eco_organization_members WHERE user_profile_id=v_root AND organization_id IN(v_north,v_south);
  SELECT id INTO v_member FROM public.eco_organization_members WHERE user_profile_id=v_account AND organization_id=v_north;
  IF v_member IS NULL THEN RAISE EXCEPTION '037 fixture requires existing accounting NORTE membership for DENY test'; END IF;
  UPDATE public.eco_organization_members SET is_active=FALSE WHERE user_profile_id=v_account AND organization_id IN(v_north,v_south);
  DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id IN(v_root,v_account) AND organization_id IN(v_north,v_south);
  DELETE FROM private.eco_platform_org_scopes WHERE user_profile_id IN(v_root,v_account) AND organization_id IN(v_north,v_south);
  DELETE FROM public.eco_platform_role_org_capabilities WHERE role_template_id IN(v_template,v_account_template) AND capability_id=v_cap;

  PERFORM set_config('request.jwt.claim.sub',v_root_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_root_auth,'role','authenticated')::TEXT,true);
  PERFORM public.switch_superadmin_org_context(NULL);
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Platform/null authorized tenant action'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.list_operational_org_targets() WHERE organization_id=v_south) THEN RAISE EXCEPTION 'Root scope missing active org'; END IF;
  PERFORM public.switch_superadmin_org_context(v_north);
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'ACCESS_ANY_ORG granted action'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_operational_records_page(v_north,NULL,10)) THEN RAISE EXCEPTION 'Scope-only root reader bypass'; END IF;
  INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES(v_template,v_cap);
  IF NOT public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Root concrete bridge grant denied'; END IF;
  IF private.can_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'can_org expanded without membership'; END IF;
  IF public.can_operate_mica_org(v_south,'RECORD_VIEW') THEN RAISE EXCEPTION 'Other-context action allowed'; END IF;
  BEGIN
    PERFORM public.get_operational_records_page(v_south,NULL,10);
    RAISE EXCEPTION 'Reader accepted unconfirmed organization';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT v_root,v_north,id,'ALLOW' FROM public.eco_capabilities WHERE code='ACCESS_ANY_ORG';
    RAISE EXCEPTION 'Reserved PLATFORM override accepted as tenant action';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect) VALUES(v_root,v_north,v_cap,'DENY');
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Root DENY bypass'; END IF;
  UPDATE private.eco_platform_org_overrides SET effect='ALLOW' WHERE user_profile_id=v_root AND organization_id=v_north AND capability_id=v_cap;
  DELETE FROM public.eco_platform_role_org_capabilities WHERE role_template_id=v_template AND capability_id=v_cap;
  IF NOT public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Scoped root ALLOW denied'; END IF;
  PERFORM public.switch_superadmin_org_context(v_south);
  IF public.can_operate_mica_org(v_south,'RECORD_VIEW') THEN RAISE EXCEPTION 'NORTE override leaked to SUR'; END IF;
  PERFORM public.switch_superadmin_org_context(NULL);

  PERFORM set_config('request.jwt.claim.sub',v_account_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_account_auth,'role','authenticated')::TEXT,true);
  PERFORM public.switch_superadmin_org_context(NULL);
  INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES(v_account_template,v_cap);
  BEGIN
    PERFORM public.switch_superadmin_org_context(v_north);
    RAISE EXCEPTION 'Bridge grant created scope';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF (public.get_my_operational_context()->>'organization_id') IS NOT NULL THEN RAISE EXCEPTION 'Rejected switch changed context'; END IF;
  INSERT INTO private.eco_platform_org_scopes(user_profile_id,organization_id) VALUES(v_account,v_north);
  PERFORM public.switch_superadmin_org_context(v_north);
  IF NOT public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Scoped platform operation requires artificial membership'; END IF;
  IF private.can_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Inactive membership unexpectedly authorized'; END IF;
  IF EXISTS (SELECT 1 FROM public.list_operational_org_targets() WHERE organization_id=v_south) THEN RAISE EXCEPTION 'Unassigned target exposed'; END IF;
  IF public.can_operate_mica_org(v_north,'ACCESS_ANY_ORG') OR public.can_operate_mica_org(v_north,'RECIPES_VIEW')
    OR public.can_operate_mica_org(v_north,'SUPPLIERS_MANAGE') THEN RAISE EXCEPTION 'Wrong product/scope accepted'; END IF;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect) VALUES(v_account,v_north,v_cap,'ALLOW');
  UPDATE public.eco_organization_members SET is_active=TRUE WHERE id=v_member;
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(v_member,v_cap,'DENY')
    ON CONFLICT(membership_id,capability_id) DO UPDATE SET effect='DENY';
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Platform ALLOW bypassed membership DENY'; END IF;
  UPDATE public.eco_membership_capability_overrides SET effect='ALLOW' WHERE membership_id=v_member AND capability_id=v_cap;
  UPDATE private.eco_platform_org_overrides SET effect='DENY' WHERE user_profile_id=v_account AND organization_id=v_north AND capability_id=v_cap;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Membership ALLOW bypassed platform DENY'; END IF;
  DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=v_account AND organization_id=v_north AND capability_id=v_cap;
  IF NOT public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Membership compatibility broken'; END IF;
  UPDATE public.eco_organization_members SET is_active=FALSE WHERE id=v_member;
  UPDATE private.eco_platform_org_scopes SET is_active=FALSE WHERE user_profile_id=v_account AND organization_id=v_north;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Revoked scope still effective'; END IF;
  UPDATE private.eco_platform_org_scopes SET is_active=TRUE WHERE user_profile_id=v_account AND organization_id=v_north;
  UPDATE public.eco_organizations SET is_active=FALSE WHERE id=v_north;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Inactive organization allowed'; END IF;
  UPDATE public.eco_organizations SET is_active=TRUE WHERE id=v_north;
  UPDATE public.eco_user_platform_role SET is_active=FALSE WHERE user_profile_id=v_account;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Inactive platform role allowed'; END IF;
  UPDATE public.eco_user_platform_role SET is_active=TRUE WHERE user_profile_id=v_account;
  UPDATE public.eco_capabilities SET is_active=FALSE WHERE id=v_cap;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Inactive capability allowed'; END IF;
  UPDATE public.eco_capabilities SET is_active=TRUE WHERE id=v_cap;
  UPDATE public.eco_user_profiles SET is_active=FALSE WHERE id=v_account;
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Inactive profile allowed'; END IF;
  UPDATE public.eco_user_profiles SET is_active=TRUE WHERE id=v_account;

  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    FOREACH v_relation IN ARRAY ARRAY['private.eco_platform_org_scopes','private.eco_platform_org_overrides','private.migration_037_functions'] LOOP
      IF has_table_privilege(v_role,v_relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN RAISE EXCEPTION '037 private table exposed'; END IF;
    END LOOP;
    FOR v_row IN SELECT oid FROM pg_proc WHERE oid IN ('private.can_operate_mica_org(uuid,text)'::regprocedure,
      'private.platform_org_in_scope(uuid)'::regprocedure,'private.has_mica_platform_role()'::regprocedure,
      'private.mica_capability_allowed(text,text)'::regprocedure,'private.guard_037_platform_override()'::regprocedure) LOOP
      IF has_function_privilege(v_role,v_row.oid,'EXECUTE') THEN RAISE EXCEPTION '037 private helper exposed'; END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('anon','public.can_operate_mica_org(uuid,text)','EXECUTE') THEN RAISE EXCEPTION '037 public RPC exposed to anon'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF NOT public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Public contract failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_north) WHERE code='RECORD_VIEW' AND organization_id=v_north) THEN
    RAISE EXCEPTION 'Effective permissions differ from operation contract'; END IF;
  FOR v_row IN SELECT * FROM public.get_operational_records_page(v_north,NULL,10) LOOP
    IF v_row.get_operational_records_page->>'organization_id' IS DISTINCT FROM v_north::TEXT THEN RAISE EXCEPTION 'Reader isolation failed'; END IF;
  END LOOP;
  EXECUTE 'RESET ROLE';
  -- A conventional tenant: real active membership, no active platform role.
  -- Resolve LIVE fixtures rather than inventing a membership or relying on a role string.
  SELECT p.id,p.auth_user_id,m.organization_id INTO v_tenant_profile,v_tenant_auth,v_tenant_org
  FROM public.eco_user_profiles p
  JOIN public.eco_organization_members m ON m.user_profile_id=p.id AND m.is_active
  JOIN public.eco_organizations o ON o.id=m.organization_id AND o.is_active
  JOIN public.eco_role_templates t ON t.id=m.role_template_id AND t.is_active AND t.scope='ORGANIZATION'
  WHERE p.is_active AND p.auth_user_id IS NOT NULL AND p.id NOT IN(v_root,v_account)
    AND NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role r WHERE r.user_profile_id=p.id AND r.is_active)
    AND EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
      JOIN public.eco_capabilities c ON c.id=g.capability_id
      WHERE g.role_template_id=t.id AND c.is_active AND private.mica_capability_allowed(c.code,c.scope)
        AND c.scope='ORGANIZATION' AND NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides mo
          WHERE mo.membership_id=m.id AND mo.capability_id=c.id AND mo.effect='DENY'))
  ORDER BY p.id,m.organization_id LIMIT 1;
  IF v_tenant_profile IS NULL THEN RAISE EXCEPTION '037 fixture requires a conventional active tenant with an approved grant'; END IF;
  INSERT INTO public.eco_user_active_context(user_profile_id,organization_id,updated_at)
  VALUES(v_tenant_profile,v_tenant_org,clock_timestamp()) ON CONFLICT(user_profile_id)
    DO UPDATE SET organization_id=EXCLUDED.organization_id,updated_at=EXCLUDED.updated_at;
  PERFORM set_config('request.jwt.claim.sub',v_tenant_auth::TEXT,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_tenant_auth,'role','authenticated')::TEXT,true);
  IF private.has_mica_platform_role() THEN RAISE EXCEPTION 'Conventional tenant fixture has platform authority'; END IF;
  FOR v_row IN SELECT code FROM public.eco_capabilities WHERE is_active AND scope='ORGANIZATION'
    AND private.mica_capability_allowed(code,scope) LOOP
    v_expected := private.can_org(v_tenant_org,v_row.code);
    EXECUTE 'SET LOCAL ROLE authenticated';
    IF public.can_operate_mica_org(v_tenant_org,v_row.code) IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'Conventional tenant behavior differs from can_org: %',v_row.code; END IF;
    EXECUTE 'RESET ROLE';
    IF v_expected THEN v_allowed_count := v_allowed_count+1; END IF;
  END LOOP;
  IF v_allowed_count=0 THEN RAISE EXCEPTION 'Conventional tenant positive case not exercised'; END IF;
  -- Verify every public RPC covered by 037, including replaced functions with preserved ACL.
  FOR v_row IN SELECT signature FROM private.migration_037_functions WHERE signature LIKE 'public.%'
    UNION ALL SELECT 'public.can_operate_mica_org(uuid,text)' LOOP
    IF has_function_privilege('anon',v_row.signature,'EXECUTE')
      OR NOT has_function_privilege('authenticated',v_row.signature,'EXECUTE') THEN
      RAISE EXCEPTION '037 public RPC ACL mismatch: %',v_row.signature; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  IF public.can_operate_mica_org(v_north,'RECORD_VIEW') THEN RAISE EXCEPTION 'Unauthenticated action'; END IF;
  RAISE NOTICE '037 scope, action, DENY, context, reader and ACL tests passed; rollback follows';
END;
$test$;
ROLLBACK;
