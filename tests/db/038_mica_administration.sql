-- Supabase SQL Editor, MICA DEV only, AFTER manual 038 application.
-- Transaction-local fixtures. No psql variables; no SQL is executed by Jest.
BEGIN;
DO $test$
DECLARE root_auth UUID; root_profile UUID; user_auth UUID:=gen_random_uuid(); staff_auth UUID:=gen_random_uuid();
  v_user_id UUID; v_staff_id UUID; org UUID; other_org UUID; tenant_preset UUID; platform_preset UUID; manager_preset UUID;
  doc JSONB; code TEXT; root_template UUID;
BEGIN
  SELECT auth_user_id,user_profile_id INTO STRICT root_auth,root_profile FROM private.eco_platform_owner;
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  org:=public.mica_admin_apply('organization',jsonb_build_object('name','038 fixture '||user_auth));
  other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','038 other '||user_auth));
  IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=org AND tax_id_type='CUIT' AND country_code='AR'
    AND currency='ARS' AND timezone='America/Argentina/Buenos_Aires') THEN RAISE EXCEPTION 'Argentina defaults'; END IF;
  -- Auth trigger integration: new profile is inactive, unassigned and marked pending.
  INSERT INTO auth.users(id,email) VALUES(user_auth,'038-'||user_auth||'@example.invalid'),(staff_auth,'038-'||staff_auth||'@example.invalid');
  SELECT id INTO STRICT v_user_id FROM public.eco_user_profiles WHERE auth_user_id=user_auth AND NOT is_active AND organization_id IS NULL;
  SELECT id INTO STRICT v_staff_id FROM public.eco_user_profiles WHERE auth_user_id=staff_auth AND NOT is_active AND organization_id IS NULL;
  IF EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id IN(v_user_id,v_staff_id))
    OR EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id IN(v_user_id,v_staff_id)) THEN RAISE EXCEPTION 'Automatic grants'; END IF;
  PERFORM set_config('request.jwt.claim.sub',user_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_auth,'role','authenticated')::TEXT,TRUE);
  BEGIN
    PERFORM public.mica_admin_read(NULL,'');
    RAISE EXCEPTION 'Pending user obtained administration';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  tenant_preset:=public.mica_admin_apply('preset',jsonb_build_object('scope','ORGANIZATION','name','038 viewer','capabilities',jsonb_build_array('RECORD_VIEW'),'bridge','[]'::JSONB));
  platform_preset:=public.mica_admin_apply('preset',jsonb_build_object('scope','PLATFORM','name','038 staff','capabilities',jsonb_build_array('ORGANIZATION_UPDATE'),'bridge',jsonb_build_array('RECORD_VIEW')));
  manager_preset:=public.mica_admin_apply('preset',jsonb_build_object('scope','ORGANIZATION','name','038 manager',
    'capabilities',jsonb_build_array('ORG_MEMBER_VIEW','ORG_MEMBER_MANAGE','ORG_MEMBER_PERMISSION_MANAGE','ORG_MEMBER_INVITE','RECORD_VIEW'),'bridge','[]'::JSONB));
  PERFORM public.switch_superadmin_org_context(org);
  PERFORM public.mica_admin_apply('membership',jsonb_build_object('user_profile_id',v_user_id,'organization_id',org,'role_template_id',tenant_preset));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',v_user_id,'is_active',TRUE));
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',v_staff_id,'role_template_id',platform_preset));
  PERFORM public.mica_admin_apply('scope',jsonb_build_object('user_profile_id',v_staff_id,'organization_id',org));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',v_staff_id,'is_active',TRUE));
  IF EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=v_staff_id) THEN RAISE EXCEPTION 'Artificial membership'; END IF;
  doc:=public.mica_admin_read(org,'');
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(doc->'capabilities') x JOIN public.eco_capabilities c ON c.code=x->>'code'
    WHERE c.delegation_class='OWNER_RESERVED' OR NOT private.mica_capability_allowed(c.code,c.scope)) THEN RAISE EXCEPTION 'Catalog leaked foreign/reserved capability'; END IF;
  BEGIN
    PERFORM public.mica_admin_apply('preset',jsonb_build_object('scope','PLATFORM','name','invalid','capabilities',jsonb_build_array('ACCESS_ANY_ORG'),'bridge','[]'::JSONB));
    RAISE EXCEPTION 'Reserved delegation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.mica_admin_apply('preset',jsonb_build_object('scope','ORGANIZATION','name','invalid','capabilities',jsonb_build_array('ORGANIZATION_UPDATE'),'bridge','[]'::JSONB));
    RAISE EXCEPTION 'Wrong scope accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',root_profile,'is_active',FALSE));
    RAISE EXCEPTION 'Root disabled';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',root_profile,'role_template_id',platform_preset));
    RAISE EXCEPTION 'Root role changed indirectly';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Normal tenant: base works, DENY dominates it, removing override restores it.
  SELECT role_template_id INTO STRICT root_template FROM public.eco_user_platform_role WHERE user_profile_id=root_profile;
  INSERT INTO private.eco_mica_presets(role_template_id,organization_id) VALUES(root_template,NULL) ON CONFLICT DO NOTHING;
  BEGIN
    PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',root_template,'scope','PLATFORM','name','Forbidden root edit',
      'capabilities','[]'::JSONB,'bridge','[]'::JSONB,'expected_recipients',1));
    RAISE EXCEPTION 'Root preset indirectly modified';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','membership','user_profile_id',v_user_id,'organization_id',org,'capability','RECORD_VIEW','effect','DENY'));
  IF NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=v_user_id AND organization_id=org) THEN
    RAISE EXCEPTION 'Approval failed to establish initial tenant context'; END IF;
  PERFORM set_config('request.jwt.claim.sub',user_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_auth,'role','authenticated')::TEXT,TRUE);
  IF public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'DENY ignored'; END IF;
  BEGIN
    PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','Unauthorized'));
    RAISE EXCEPTION 'Unprivileged organization creation';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','membership','user_profile_id',v_user_id,'organization_id',org,'capability','RECORD_VIEW','effect','ALLOW'));
  PERFORM set_config('request.jwt.claim.sub',user_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_auth,'role','authenticated')::TEXT,TRUE);
  IF NOT public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'ALLOW failed'; END IF;
  -- Functional accountant is a delegated actor, not structural root. Fixture has no email bypass.
  PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
  PERFORM public.switch_superadmin_org_context(org);
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'name','038 permitted update'));
  IF NOT public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'Staff scope/bridge failed'; END IF;
  BEGIN
    PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',other_org,'name','Unauthorized'));
    RAISE EXCEPTION 'Staff escaped explicit scope';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Tenant manager cannot administer another org even when granted member administration.
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','platform','user_profile_id',v_staff_id,'capability','ORGANIZATION_UPDATE','effect','DENY'));
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','platform_org','user_profile_id',v_staff_id,'organization_id',org,'capability','RECORD_VIEW','effect','DENY'));
  PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
  IF public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'Platform-org DENY ignored'; END IF;
  BEGIN
    PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'name','Forbidden by DENY'));
    RAISE EXCEPTION 'Platform DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','platform','user_profile_id',v_staff_id,'capability','ORGANIZATION_UPDATE','effect','ALLOW'));
  PERFORM public.mica_admin_apply('override',jsonb_build_object('kind','platform_org','user_profile_id',v_staff_id,'organization_id',org,'capability','RECORD_VIEW','effect','INHERITED'));
  PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
  IF NOT public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'Platform-org inherited grant failed'; END IF;
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'name','Platform ALLOW restored'));
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  PERFORM public.mica_admin_apply('membership',jsonb_build_object('user_profile_id',v_user_id,'organization_id',org,'role_template_id',manager_preset));
  PERFORM set_config('request.jwt.claim.sub',user_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_auth,'role','authenticated')::TEXT,TRUE);
  BEGIN
    PERFORM public.mica_admin_apply('membership',jsonb_build_object('user_profile_id',v_staff_id,'organization_id',other_org,'role_template_id',tenant_preset));
    RAISE EXCEPTION 'Tenant manager escaped organization';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Public ACL assertions under the actual restricted role; no private calls afterwards.
  EXECUTE 'SET LOCAL ROLE authenticated';
  doc:=public.mica_admin_read(org,'');
  IF has_function_privilege('anon','public.mica_admin_read(uuid,text)','EXECUTE')
    OR has_function_privilege('anon','public.mica_admin_apply(text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Anon RPC exposed'; END IF;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE '038 administration assertions passed; transaction rolls back';
END; $test$;
ROLLBACK;
