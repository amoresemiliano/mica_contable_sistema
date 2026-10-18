-- PREPARED ONLY. NEVER EXECUTED BY THE AGENT. Run AFTER reviewing/applying 041 in DEV.
-- Synthetic fixtures only, complete transaction rollback. No emails sent.
-- Human acceptance after DB review/application and a separately authorized DEV deploy:
-- 1. Platform / empresa gestionada / Usuarios: existing email assigns; new email stays pending.
-- 2. Platform / Impuestos: create a dated version, assign/unassign; operational context stays Platform.
-- 3. Tenant / Impuestos: only assigned configuration, no global creation/edit controls.
-- 4. Empresa / eye: native drawer above sidebar, close/scroll usable at desktop and 390px.
BEGIN;
DO $test$
DECLARE root_auth UUID; actor_auth UUID:=gen_random_uuid(); actor UUID; member_auth UUID:=gen_random_uuid(); member UUID;
 org_a UUID; org_b UUID; company_role UUID; platform_role UUID; no_rate_role UUID; root_role UUID; historical UUID;
 activity UUID; definition UUID; overlap_definition UUID; result JSONB; email TEXT; count_before BIGINT; rate_count BIGINT; old_context JSONB;
BEGIN
 SELECT auth_user_id INTO STRICT root_auth FROM private.eco_platform_owner;
 SELECT role_template_id INTO STRICT root_role FROM public.eco_user_platform_role r JOIN private.eco_platform_owner o ON o.user_profile_id=r.user_profile_id;
 SELECT id INTO STRICT historical FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN';
 SELECT id INTO STRICT activity FROM public.eco_economic_activities WHERE is_active ORDER BY id LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 -- Explicit fixture setup only. Product target selection never calls this RPC.
 PERFORM public.switch_superadmin_org_context(NULL);
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(actor_auth,'041-actor-'||actor_auth||'@example.invalid',now()),
  (member_auth,'041-member-'||member_auth||'@example.invalid',now());
 SELECT id INTO STRICT actor FROM public.eco_user_profiles WHERE auth_user_id=actor_auth;
 SELECT id INTO STRICT member FROM public.eco_user_profiles WHERE auth_user_id=member_auth;
 email:='041-member-'||member_auth||'@example.invalid';
 SET LOCAL ROLE authenticated;
 org_a:=public.mica_admin_apply('organization',jsonb_build_object('name','041 company A '||actor_auth));
 org_b:=public.mica_admin_apply('organization',jsonb_build_object('name','041 company B '||actor_auth));
 company_role:=public.mica_admin_apply('preset',jsonb_build_object('name','041 company role','scope','ORGANIZATION','capabilities',jsonb_build_array('ORG_VIEW','CATALOG_ORG_VIEW'),'bridge','[]'::JSONB));
 platform_role:=public.mica_admin_apply('preset',jsonb_build_object('name','041 scoped administrator','scope','PLATFORM',
  'capabilities',jsonb_build_array('MICA_ADMIN_MANAGE','RATE_MANAGE_ANY_ORG'),
  'bridge',jsonb_build_array('ORG_VIEW','CATALOG_ORG_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN')));
 no_rate_role:=public.mica_admin_apply('preset',jsonb_build_object('name','041 without rate authority','scope','PLATFORM',
  'capabilities',jsonb_build_array('MICA_ADMIN_MANAGE'),'bridge',jsonb_build_array('ORG_VIEW','CATALOG_ORG_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN')));
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',actor,'role_template_id',platform_role));
 PERFORM public.mica_admin_apply('scope',jsonb_build_object('user_profile_id',actor,'organization_id',org_a));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',actor,'is_active',TRUE));
 PERFORM public.assign_economic_activity_to_org(activity,org_a);
 result:=public.mica_platform_iibb('create',NULL,jsonb_build_object('activity_id',activity,'jurisdiction','041 fixture','rate',3,
  'valid_from','2026-01-01','valid_to','2026-12-31'));
 definition:=(result->>'id')::UUID;
 RESET ROLE;
 SELECT count(*) INTO count_before FROM auth.users;
 PERFORM set_config('request.jwt.claim.sub',actor_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_auth,'role','authenticated')::TEXT,TRUE);
 SELECT to_jsonb(c) INTO old_context FROM public.eco_user_active_context c WHERE c.user_profile_id=actor;
 SET LOCAL ROLE authenticated;
 result:=public.mica_platform_access('options');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') o WHERE o->>'id'=org_a::TEXT)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') o WHERE o->>'id'=org_b::TEXT) THEN RAISE EXCEPTION 'Options leaked or omitted scope'; END IF;
 -- Existing user: single canonical membership, zero new auth identities, repeat-safe.
 PERFORM public.mica_platform_access('save',org_a,jsonb_build_object('email',email,'role_template_id',company_role));
 PERFORM public.mica_platform_access('save',org_a,jsonb_build_object('email',email,'role_template_id',company_role));
 result:=public.mica_platform_access('save',org_a,jsonb_build_object('email','041-new-'||member_auth||'@example.invalid','role_template_id',company_role));
 IF result->>'status'<>'PENDING_AUTHENTICATION' THEN RAISE EXCEPTION 'New user did not remain pending'; END IF;
 BEGIN
  PERFORM public.mica_platform_access('save',org_b,jsonb_build_object('email',email,'role_template_id',company_role));
  RAISE EXCEPTION 'Unscoped organization accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_access('save',org_a,jsonb_build_object('email',email,'role_template_id',platform_role));
  RAISE EXCEPTION 'Platform role used as membership'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_access('save',NULL,jsonb_build_object('email',email,'role_template_id',company_role));
  RAISE EXCEPTION 'Company role used as Platform role'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_access('save',NULL,jsonb_build_object('email',email,'role_template_id',root_role));
  RAISE EXCEPTION 'Protected role accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_access('save',NULL,jsonb_build_object('email',email,'role_template_id',historical));
  RAISE EXCEPTION 'Deprecated role accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_iibb('assign',org_b,jsonb_build_object('id',definition));
  RAISE EXCEPTION 'Unscoped rate destination accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
 PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
 result:=public.mica_platform_iibb('create',NULL,jsonb_build_object('activity_id',activity,'jurisdiction','041 fixture','rate',4,
  'valid_from','2026-06-01','valid_to','2026-10-31'));
 overlap_definition:=(result->>'id')::UUID;
 BEGIN
  PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',overlap_definition));
  RAISE EXCEPTION 'Overlapping assignment allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Conflicting active rate period' THEN RAISE; END IF; END;
 RESET ROLE;
 SELECT count(*) INTO rate_count FROM public.eco_org_activity_iibb_rates WHERE organization_id=org_a AND definition_id=definition AND is_active;
 IF rate_count<>1 THEN RAISE EXCEPTION 'Duplicate active rate assignments'; END IF;
 IF (SELECT count(*) FROM auth.users)<>count_before OR
  (SELECT count(*) FROM public.eco_organization_members WHERE organization_id=org_a AND user_profile_id=member)<>1 THEN
  RAISE EXCEPTION 'Duplicate auth or membership identity'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=member AND is_active) THEN RAISE EXCEPTION 'Pending account silently activated'; END IF;
 IF old_context IS DISTINCT FROM (SELECT to_jsonb(c) FROM public.eco_user_active_context c WHERE c.user_profile_id=actor) THEN
  RAISE EXCEPTION 'Management action changed operational context'; END IF;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_platform_iibb('unassign',org_a,jsonb_build_object('id',definition));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates WHERE organization_id=org_a AND definition_id=definition AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates WHERE organization_id=org_a AND definition_id=definition AND NOT is_active) THEN
  RAISE EXCEPTION 'Unassignment lost history or retained effective assignment'; END IF;
 -- DENY beats bridged base authority even for scoped administrators.
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',actor,'kind','platform_org','organization_id',org_a,'capability','ORG_MEMBER_INVITE','effect','DENY'));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',actor_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_platform_access('save',org_a,jsonb_build_object('email',email,'role_template_id',company_role));
  RAISE EXCEPTION 'Explicit DENY bypassed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',actor,'role_template_id',no_rate_role));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',member,'is_active',TRUE));
 PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',actor_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_platform_iibb('assign',org_a,jsonb_build_object('id',definition));
  RAISE EXCEPTION 'RATE_MANAGE_ANY_ORG not enforced'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 -- Tenant user cannot enter either Platform management contract or modify definitions.
 PERFORM set_config('request.jwt.claim.sub',member_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',member_auth,'role','authenticated')::TEXT,TRUE);
 INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(member,org_a)
  ON CONFLICT(user_profile_id) DO UPDATE SET organization_id=org_a;
 SET LOCAL ROLE authenticated;
 result:=public.get_operational_snapshot(org_a);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'rates') r WHERE r->>'jurisdiction'='041 fixture' AND r->>'activity_id'=activity::TEXT AND r->>'organization_id'=org_a::TEXT)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(result->'rates') r WHERE r->>'organization_id'<>org_a::TEXT) THEN
  RAISE EXCEPTION 'Tenant assignment view omitted assigned rate or leaked another tenant'; END IF;
 BEGIN
  PERFORM public.mica_platform_access('save',org_b,jsonb_build_object('email',email,'role_template_id',company_role));
  RAISE EXCEPTION 'Tenant invited into another tenant'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_platform_iibb('create',NULL,jsonb_build_object('activity_id',activity,'jurisdiction','041 illegal','rate',1));
  RAISE EXCEPTION 'Tenant created global definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE private.eco_iibb_rate_definitions SET rate=1 WHERE id=definition;
  RAISE EXCEPTION 'Tenant modified global definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END; $test$;
ROLLBACK;
