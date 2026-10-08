-- PREPARED ONLY. Apply/review 042 in DEV separately, then run this rollback-only harness.
-- Synthetic identities only. No emails or external side effects.
BEGIN;
DO $test$
DECLARE root_auth UUID; member_auth UUID:=gen_random_uuid(); member UUID; email TEXT;
 org_a UUID; org_b UUID; org_c UUID; role_a UUID; role_b UUID; activity UUID; definition UUID; overlapping UUID;
 scoped_auth UUID:=gen_random_uuid(); scoped UUID; scoped_role UUID;
 result JSONB; initial_profile_org UUID; old_context JSONB;
BEGIN
 SELECT auth_user_id INTO STRICT root_auth FROM private.eco_platform_owner;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 PERFORM public.switch_superadmin_org_context(NULL);
 email:='042-member-'||member_auth||'@example.invalid';
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(member_auth,email,now());
 SELECT id,organization_id INTO STRICT member,initial_profile_org FROM public.eco_user_profiles WHERE auth_user_id=member_auth;
 SELECT id INTO STRICT activity FROM public.eco_economic_activities WHERE is_active ORDER BY id LIMIT 1;
 SET LOCAL ROLE authenticated;
 org_a:=public.mica_admin_apply('organization',jsonb_build_object('name','042 A '||member_auth));
 org_b:=public.mica_admin_apply('organization',jsonb_build_object('name','042 B '||member_auth));
 org_c:=public.mica_admin_apply('organization',jsonb_build_object('name','042 C '||member_auth));
 role_a:=public.mica_admin_apply('preset',jsonb_build_object('name','042 Auditor','scope','ORGANIZATION',
  'capabilities',jsonb_build_array('ORG_VIEW','CATALOG_ORG_VIEW','RECORD_VIEW'),'bridge','[]'::JSONB));
 role_b:=public.mica_admin_apply('preset',jsonb_build_object('name','042 Consulta','scope','ORGANIZATION',
  'capabilities',jsonb_build_array('ORG_VIEW','CATALOG_ORG_VIEW'),'bridge','[]'::JSONB));
 PERFORM public.mica_platform_access('save',org_a,jsonb_build_object('email',email,'role_template_id',role_a));
 PERFORM public.mica_platform_access('save',org_b,jsonb_build_object('email',email,'role_template_id',role_b));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',member,'is_active',TRUE));
 -- IIBB missing-activity diagnostic is server-side; definition creation alone never assigns it.
 result:=public.mica_platform_iibb('create',NULL,jsonb_build_object('activity_id',activity,'jurisdiction','042 fixture','rate',3,
  'valid_from','2026-01-01','valid_to','2026-12-31')); definition:=(result->>'id')::UUID;
 result:=public.mica_platform_iibb('list',org_a);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'definitions') d WHERE d->>'id'=definition::TEXT
  AND (d->>'assigned')::BOOLEAN=FALSE AND (d->>'activity_assigned')::BOOLEAN=FALSE) THEN RAISE EXCEPTION 'IIBB prerequisite not exposed'; END IF;
 BEGIN
  PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
  RAISE EXCEPTION 'Missing activity accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'Primero asigná la actividad económica % a esta empresa.' THEN RAISE; END IF; END;
 PERFORM public.assign_economic_activity_to_org(activity,org_a);
 SELECT to_jsonb(c) INTO old_context FROM public.eco_user_active_context c WHERE c.user_profile_id=private.current_profile_id();
 PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
 result:=public.mica_platform_iibb('list',org_a);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'definitions') d WHERE d->>'id'=definition::TEXT AND (d->>'assigned')::BOOLEAN)
  THEN RAISE EXCEPTION 'Assignment state stale'; END IF;
 result:=public.mica_platform_iibb('create',NULL,jsonb_build_object('activity_id',activity,'jurisdiction','042 fixture','rate',4,
  'valid_from','2026-06-01','valid_to','2026-10-31')); overlapping:=(result->>'id')::UUID;
 BEGIN
  PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',overlapping));
  RAISE EXCEPTION 'Overlapping rate accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Conflicting active rate period' THEN RAISE; END IF; END;
 PERFORM public.mica_platform_iibb('unassign',org_a,jsonb_build_object('id',definition));
 result:=public.mica_platform_iibb('list',org_a);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'definitions') d WHERE d->>'id'=definition::TEXT AND (d->>'assigned')::BOOLEAN)
  THEN RAISE EXCEPTION 'Unassignment state stale'; END IF;
 IF old_context IS DISTINCT FROM (SELECT to_jsonb(c) FROM public.eco_user_active_context c WHERE c.user_profile_id=private.current_profile_id())
  THEN RAISE EXCEPTION 'Rate assignment changed Platform context'; END IF;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',member_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',member_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 IF (SELECT count(*) FROM public.list_my_organization_contexts())<>2 OR
  NOT EXISTS(SELECT 1 FROM public.list_my_organization_contexts() WHERE organization_id=org_a AND role_template_id=role_a) OR
  NOT EXISTS(SELECT 1 FROM public.list_my_organization_contexts() WHERE organization_id=org_b AND role_template_id=role_b) THEN
  RAISE EXCEPTION 'Membership list missing roles or leaked organizations'; END IF;
 result:=public.get_my_operational_context();
 IF result->>'organization_id'<>org_a::TEXT OR (result->>'can_switch_platform_context')::BOOLEAN THEN RAISE EXCEPTION 'Unsafe initial context'; END IF;
 PERFORM public.switch_my_organization_context(org_a);
 IF NOT EXISTS(SELECT 1 FROM public.get_my_effective_capabilities(org_a) WHERE code='RECORD_VIEW') THEN RAISE EXCEPTION 'A role not effective'; END IF;
 PERFORM public.switch_my_organization_context(org_b);
 result:=public.get_my_operational_context();
 IF result->>'organization_id'<>org_b::TEXT OR result->>'profile_name'<>'042 Consulta'
  OR EXISTS(SELECT 1 FROM public.get_my_effective_capabilities(org_b) WHERE code='RECORD_VIEW') THEN RAISE EXCEPTION 'B role/context stale'; END IF;
 BEGIN
  PERFORM public.get_operational_snapshot(org_a); RAISE EXCEPTION 'A data accessible after B switch';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF public.get_my_operational_context()->>'organization_id'<>org_b::TEXT THEN RAISE EXCEPTION 'Selected B context not restored'; END IF;
 PERFORM public.switch_my_organization_context(org_a);
 BEGIN PERFORM public.switch_my_organization_context(org_c); RAISE EXCEPTION 'Unauthorized C accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.switch_my_organization_context(NULL); RAISE EXCEPTION 'Tenant Platform accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.switch_superadmin_org_context(org_b); RAISE EXCEPTION 'Platform contract weakened'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition)); RAISE EXCEPTION 'Rate authority not enforced'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 IF initial_profile_org IS DISTINCT FROM (SELECT organization_id FROM public.eco_user_profiles WHERE id=member) THEN RAISE EXCEPTION 'Memberships collapsed into profile ownership'; END IF;
 UPDATE public.eco_role_templates SET is_active=FALSE WHERE id=role_b;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.switch_my_organization_context(org_b); RAISE EXCEPTION 'Inactive role accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 UPDATE public.eco_role_templates SET is_active=TRUE WHERE id=role_b;
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_my_organization_context(org_b);
 RESET ROLE;
 UPDATE public.eco_organization_members SET is_active=FALSE WHERE user_profile_id=member AND organization_id=org_b;
 SET LOCAL ROLE authenticated;
 IF public.get_my_operational_context()->>'organization_id'<>org_a::TEXT THEN RAISE EXCEPTION 'Revoked selected membership did not resolve safely'; END IF;
 BEGIN PERFORM public.switch_my_organization_context(org_b); RAISE EXCEPTION 'Inactive membership accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 DELETE FROM public.eco_organization_members WHERE user_profile_id=member AND organization_id=org_b;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.switch_my_organization_context(org_b); RAISE EXCEPTION 'Removed membership accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 UPDATE public.eco_organizations SET is_active=FALSE WHERE id=org_a;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.switch_my_organization_context(org_a); RAISE EXCEPTION 'Inactive organization accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_my_operational_context(); RAISE EXCEPTION 'User without memberships received Platform'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 -- Platform RPC behavior is covered by the canonical 037/041 harnesses; exercise delegation too.
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_my_organization_context(org_b);
 IF public.get_my_operational_context()->>'organization_id'<>org_b::TEXT THEN RAISE EXCEPTION 'Platform scope behavior changed'; END IF;
 PERFORM public.switch_my_organization_context(NULL);
 IF public.get_my_operational_context()->>'organization_id' IS NOT NULL THEN RAISE EXCEPTION 'Platform return failed'; END IF;
 RESET ROLE;
 -- Scoped Platform session: a stale selector cannot retain revoked organization authority.
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(scoped_auth,'042-scoped-'||scoped_auth||'@example.invalid',now());
 SELECT id INTO STRICT scoped FROM public.eco_user_profiles WHERE auth_user_id=scoped_auth;
 SET LOCAL ROLE authenticated;
 scoped_role:=public.mica_admin_apply('preset',jsonb_build_object('name','042 scoped Platform','scope','PLATFORM','capabilities','[]'::JSONB,'bridge','[]'::JSONB));
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',scoped,'role_template_id',scoped_role));
 PERFORM public.mica_admin_apply('scope',jsonb_build_object('user_profile_id',scoped,'organization_id',org_b));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',scoped,'is_active',TRUE));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',scoped_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',scoped_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 IF (SELECT count(*) FROM public.list_my_organization_contexts())<>1 THEN RAISE EXCEPTION 'Platform scope list leaked'; END IF;
 PERFORM public.switch_my_organization_context(org_b);
 RESET ROLE;
 UPDATE private.eco_platform_org_scopes SET is_active=FALSE WHERE user_profile_id=scoped AND organization_id=org_b;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.switch_my_organization_context(org_b); RAISE EXCEPTION 'Revoked Platform scope accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF public.get_my_operational_context()->>'organization_id' IS NOT NULL OR EXISTS(SELECT 1 FROM public.list_my_organization_contexts()) THEN
  RAISE EXCEPTION 'Revoked scope retained tenant context/list'; END IF;
 RESET ROLE;
END; $test$;
ROLLBACK;
