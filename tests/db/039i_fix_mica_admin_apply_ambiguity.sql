-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; run manually AFTER 039i. Never executed by agent.
-- Runs the complete 039h harness unchanged, then 039g checks with the current operational preset.
-- 039g originally assigned ACCOUNTING_SUPERADMIN: that assignment must stay blocked after 039h.
BEGIN;
DO $installed$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.migration_039i_function saved_function JOIN pg_proc proc_row
  ON proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  WHERE pg_get_functiondef(proc_row.oid)=saved_function.installed
   AND pg_get_userbyid(proc_row.proowner)=saved_function.owner_name
   AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
   AND proc_row.proconfig IS NOT DISTINCT FROM saved_function.settings AND proc_row.prosecdef=saved_function.security_definer) THEN
  RAISE EXCEPTION '039i function or security drift'; END IF;
END; $installed$;
SAVEPOINT harness_039h;
DO $test$
DECLARE actor UUID; actor_auth UUID; root_id UUID; root_auth UUID; root_preset UUID; org UUID;
 tenant_auth UUID:=gen_random_uuid(); tenant UUID; invitation JSONB; result JSONB; cap TEXT; action TEXT; kind TEXT;
 reader UUID; accountant UUID; operational UUID; historical UUID; root_before JSONB; scopes_before JSONB; rowdata RECORD; v_scope RECORD;
BEGIN
 SELECT target,preset INTO STRICT actor,operational FROM private.migration_039h_state;
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_template_capabilities tenant_grant
   JOIN public.eco_role_templates tenant_template ON tenant_template.id=tenant_grant.role_template_id
   JOIN public.eco_capabilities tenant_capability ON tenant_capability.id=tenant_grant.capability_id
   WHERE tenant_template.code='MICA_ORG_ADMIN' AND tenant_template.scope='ORGANIZATION' AND tenant_capability.code='ORG_MEMBER_PRESET_ASSIGN') THEN
  RAISE EXCEPTION 'MICA_ORG_ADMIN assignment grant missing'; END IF;
 IF (SELECT count(*) FROM public.eco_platform_role_org_capabilities platform_grant
   JOIN public.eco_role_templates platform_template ON platform_template.id=platform_grant.role_template_id
   JOIN public.eco_capabilities bridge_capability ON bridge_capability.id=platform_grant.capability_id
   WHERE platform_template.code IN('VEGEN_PLATFORM_ADMIN','ADMINISTRACION_OPERATIVA_MICA') AND platform_template.scope='PLATFORM'
    AND bridge_capability.code='ORG_MEMBER_PRESET_ASSIGN')<>2 THEN RAISE EXCEPTION 'Root/operational assignment bridge missing'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_templates legacy_template
   JOIN public.eco_role_template_capabilities legacy_grant ON legacy_grant.role_template_id=legacy_template.id
   JOIN public.eco_capabilities legacy_capability ON legacy_capability.id=legacy_grant.capability_id
   WHERE legacy_template.scope IS NULL AND legacy_capability.code='ORG_MEMBER_PRESET_ASSIGN')
  OR EXISTS(SELECT 1 FROM public.eco_role_templates legacy_template
   JOIN public.eco_platform_role_org_capabilities legacy_grant ON legacy_grant.role_template_id=legacy_template.id
   JOIN public.eco_capabilities legacy_capability ON legacy_capability.id=legacy_grant.capability_id
   WHERE legacy_template.scope IS NULL AND legacy_capability.code='ORG_MEMBER_PRESET_ASSIGN') THEN
  RAISE EXCEPTION 'OWNER or other NULL-scope legacy received assignment capability'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgname='guard_036_grant' AND tgenabled='O'
   AND tgfoid=to_regprocedure('private.guard_036_grant()') AND tgrelid IN('public.eco_role_template_capabilities'::regclass,
    'public.eco_platform_role_org_capabilities'::regclass))<>2 THEN RAISE EXCEPTION 'Grant guards are not active'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state saved_state WHERE saved_state.legacy_before IS DISTINCT FROM jsonb_build_object(
   'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
   'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
    JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
   'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
    JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL))) THEN
  RAISE EXCEPTION 'Legacy templates/grants snapshot differs'; END IF;
 SELECT auth_user_id INTO STRICT actor_auth FROM public.eco_user_profiles WHERE id=actor;
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=actor)<>3
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=actor AND is_active) THEN
  RAISE EXCEPTION 'Historical memberships missing or still active'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state saved_state WHERE saved_state.memberships_installed IS DISTINCT FROM
   (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=actor)
   OR saved_state.scopes IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=actor)) THEN
  RAISE EXCEPTION 'Historical memberships or seven scopes changed'; END IF;
 SELECT user_profile_id,auth_user_id INTO STRICT root_id,root_auth FROM private.eco_platform_owner;
 SELECT role_template_id INTO STRICT root_preset FROM public.eco_user_platform_role WHERE user_profile_id=root_id;
 SELECT id INTO STRICT historical FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN';
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
   WHERE a.user_profile_id=actor AND a.is_active AND t.id=operational AND t.code='ADMINISTRACION_OPERATIVA_MICA' AND t.is_active) THEN
  RAISE EXCEPTION 'Marianela operational assignment missing'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=historical AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=historical AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=historical AND is_active) THEN
  RAISE EXCEPTION 'Accounting is reusable or has active recipients'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=root_preset AND code='VEGEN_PLATFORM_ADMIN' AND is_active) THEN
  RAISE EXCEPTION 'Root preset changed'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities g JOIN public.eco_role_templates t ON t.id=g.role_template_id
   JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code='ORGANIZATION_CREATE' AND t.is_active AND t.id NOT IN(root_preset,operational))
  OR NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_ARCHIVE' AND delegation_class='OWNER_RESERVED' AND is_active) THEN
  RAISE EXCEPTION 'Create/archive boundary changed'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state b WHERE
   b.historical_grants IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=historical)
   OR b.historical_bridge IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=historical)) THEN
  RAISE EXCEPTION 'Historical grants changed'; END IF;
 SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(a)) INTO root_before
 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
 JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id;
 SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY organization_id),'[]') INTO scopes_before FROM private.eco_platform_org_scopes s WHERE user_profile_id=actor;
 SELECT id INTO STRICT reader FROM public.eco_role_templates WHERE code='MICA_READ_ONLY';
 SELECT id INTO STRICT accountant FROM public.eco_role_templates WHERE code='MICA_ACCOUNTANT';
 PERFORM set_config('request.jwt.claim.sub',actor_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_auth,'role','authenticated')::TEXT,TRUE);
 -- Exercise ALL seven reviewed organizations, including the three historical tenant organizations,
 -- and MICA / Nueva ORG / Una de prueba / Vanina. Only platform scopes and bridge authorize now.
 FOR v_scope IN SELECT organization_id FROM private.eco_platform_org_scopes WHERE user_profile_id=actor AND is_active LOOP
  SET LOCAL ROLE authenticated;
  PERFORM public.switch_superadmin_org_context(v_scope.organization_id);
  IF NOT public.can_operate_mica_org(v_scope.organization_id,'RECORD_VIEW')
   OR NOT public.can_operate_mica_org(v_scope.organization_id,'RECORD_CLASSIFY') THEN
   RAISE EXCEPTION 'Scope-only operation failed in %',v_scope.organization_id; END IF;
  RESET ROLE;
 END LOOP;
 FOREACH cap IN ARRAY ARRAY['MICA_ADMIN_MANAGE','AUDIT_PLATFORM_VIEW','SAAS_ANALYTICS_VIEW','PLATFORM_MANAGE','GLOBAL_USER_MANAGE',
 'PLAN_MANAGE','ACCESS_ANY_ORG','SUPPORT_IMPERSONATE','HARD_DELETE_EXCEPTIONAL','ORGANIZATION_ARCHIVE',
 'PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION','PLATFORM_SYSTEM_MONITOR'] LOOP
  IF private.can_platform(cap) THEN RAISE EXCEPTION 'Forbidden platform capability: %',cap; END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039h company '||tenant_auth));
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'name','039h edited','legal_name','039h Legal SA',
  'trade_name','039h Comercial','tax_id','30712345678'));
 PERFORM public.switch_superadmin_org_context(org);
 result:=public.mica_admin_read(org,'');
 IF NOT (result->'rights'->>'operational_admin')::BOOLEAN OR (result->'rights'->>'presets')::BOOLEAN
  OR (result->'rights'->>'assignments')::BOOLEAN OR result->'capabilities'<>'[]'::JSONB OR result->'overrides'<>'[]'::JSONB THEN
  RAISE EXCEPTION 'Operational UI exposed structural tools'; END IF;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'is_active',FALSE));
  RAISE EXCEPTION 'Archive allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
 PERFORM public.create_import('ARCA_EMITIDOS','VENTA');
 PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
 PERFORM public.create_import('PERCEPCIONES_ARBA','PERCEPCION');
 PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
 PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
 invitation:=public.mica_invitation('create',org,jsonb_build_object('email','039h-'||tenant_auth||'@example.invalid','role_template_id',reader));
 RESET ROLE;
 SELECT * INTO STRICT rowdata FROM public.eco_organizations WHERE id=org;
 IF rowdata.name<>'039h edited' OR rowdata.legal_name<>'039h Legal SA' OR rowdata.trade_name<>'039h Comercial'
  OR rowdata.tax_id<>'30712345678' OR NOT rowdata.is_active THEN RAISE EXCEPTION 'Company update failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=actor AND organization_id=org AND is_active) THEN
  RAISE EXCEPTION 'New organization missing explicit scope'; END IF;
 IF private.can_operate_mica_org(org,'ORG_MEMBER_PERMISSION_MANAGE') THEN RAISE EXCEPTION 'Permission editing leaked'; END IF;
 FOREACH cap IN ARRAY ARRAY['ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN',
 'CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','RECORD_CLASSIFY','FINANCIAL_ALLOCATION_EDIT','MANUAL_MOVEMENT_CREATE',
 'MANUAL_MOVEMENT_EDIT','RECORD_SOFT_DELETE','RECORD_RESTORE'] LOOP
  IF NOT private.can_operate_mica_org(org,cap) THEN RAISE EXCEPTION 'Operational grant missing: %',cap; END IF;
 END LOOP;
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(tenant_auth,'039h-'||tenant_auth||'@example.invalid',now());
 SELECT id INTO STRICT tenant FROM public.eco_user_profiles WHERE auth_user_id=tenant_auth;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_invitation('assign',org,jsonb_build_object('id',invitation->>'id','user_profile_id',tenant));
 PERFORM public.mica_admin_apply('tenant_activate',jsonb_build_object('organization_id',org,'user_profile_id',tenant));
 PERFORM public.mica_admin_apply('membership',jsonb_build_object('organization_id',org,'user_profile_id',tenant,'role_template_id',accountant,'is_active',TRUE));
 RESET ROLE;
 IF NOT EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=tenant AND organization_id=org AND role_template_id=accountant AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=tenant AND is_active) THEN RAISE EXCEPTION 'Tenant assignment/activation failed'; END IF;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('membership',jsonb_build_object('organization_id',org,'user_profile_id',tenant,'role_template_id',reader,'is_active',FALSE));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=tenant AND organization_id=org AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=tenant AND is_active) THEN RAISE EXCEPTION 'Tenant deactivation altered global account'; END IF;
 SET LOCAL ROLE authenticated;
 FOREACH action IN ARRAY ARRAY['user','platform_role','scope'] LOOP
  BEGIN
   PERFORM public.mica_admin_apply(action,jsonb_build_object('user_profile_id',tenant,'role_template_id',operational,
    'organization_id',CASE WHEN action='scope' THEN org ELSE NULL END,'is_active',FALSE));
   RAISE EXCEPTION 'Forbidden action allowed: %',action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 FOREACH kind IN ARRAY ARRAY['platform','platform_org','membership'] LOOP
  FOREACH action IN ARRAY ARRAY['ALLOW','DENY'] LOOP
   BEGIN
    PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',tenant,'organization_id',CASE WHEN kind='platform' THEN NULL ELSE org END,
      'kind',kind,'effect',action,'capability',CASE WHEN kind='platform' THEN 'ORGANIZATION_CREATE' ELSE 'RECORD_VIEW' END));
    RAISE EXCEPTION 'Override allowed: % %',kind,action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
 END LOOP;
 BEGIN
  PERFORM public.mica_invitation('create',NULL,jsonb_build_object('email','platform-'||tenant_auth||'@example.invalid','role_template_id',operational));
  RAISE EXCEPTION 'Platform invitation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('name','Forbidden','scope','ORGANIZATION','organization_id',org,'capabilities','[]'::JSONB,'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Preset creation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE public.eco_capabilities SET description='forbidden' WHERE code='ORGANIZATION_CREATE';
  RAISE EXCEPTION 'Capability edit allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM private.eco_platform_owner WHERE user_profile_id=root_id;
  RAISE EXCEPTION 'Structural owner deletion allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=root_preset;
  RAISE EXCEPTION 'Root grants deletion allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH action IN ARRAY ARRAY['user','platform_role','scope','membership','override'] LOOP
  BEGIN
   PERFORM public.mica_admin_apply(action,jsonb_build_object('user_profile_id',root_id,'role_template_id',reader,'organization_id',org,'is_active',FALSE,
    'kind','membership','effect','DENY','capability','RECORD_VIEW'));
   RAISE EXCEPTION 'Root administration allowed: %',action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',root_preset,'name','Forbidden','scope','PLATFORM','capabilities','[]'::JSONB,'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Root preset edit allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
 SELECT actor,id,'DENY' FROM public.eco_capabilities WHERE code='ORGANIZATION_CREATE';
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','Denied'));
  RAISE EXCEPTION 'DENY bypassed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(scopes_before) old WHERE NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes s WHERE to_jsonb(s)=old)) THEN
  RAISE EXCEPTION 'Existing scope changed'; END IF;
 IF root_before IS DISTINCT FROM (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(a))
 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
 JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id) THEN RAISE EXCEPTION 'Root state changed'; END IF;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 FOR cap IN SELECT code FROM public.eco_capabilities WHERE delegation_class='OWNER_RESERVED' LOOP
  IF NOT private.can_platform(cap) THEN RAISE EXCEPTION 'Root reserved authority lost: %',cap; END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 result:=public.mica_admin_read(NULL,'');
 IF NOT (result->'rights'->>'global_users')::BOOLEAN OR NOT (result->'rights'->>'global_presets')::BOOLEAN THEN RAISE EXCEPTION 'Root UI authority lost'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'presets') p WHERE p->>'code'='ACCOUNTING_SUPERADMIN' AND (p->>'is_active')::BOOLEAN) THEN
  RAISE EXCEPTION 'Deprecated preset exposed as assignable'; END IF;
 BEGIN
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',tenant,'role_template_id',historical));
  RAISE EXCEPTION 'Deprecated preset assignment allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',historical,'is_active',TRUE));
  RAISE EXCEPTION 'Deprecated preset reactivation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END; $test$;
ROLLBACK TO SAVEPOINT harness_039h;
SAVEPOINT harness_039g_current_preset;
DO $test$
DECLARE root_id UUID; root_auth UUID; root_template UUID; staff UUID; staff_auth UUID:=gen_random_uuid();
 accounting UUID; org UUID; created UUID; cap TEXT; result JSONB; original_owner JSONB; scope_before JSONB;
BEGIN
 IF to_regclass('private.migration_039g_create') IS NULL THEN RAISE EXCEPTION 'Apply 039g first'; END IF;
 SELECT user_profile_id,auth_user_id,to_jsonb(o) INTO STRICT root_id,root_auth,original_owner FROM private.eco_platform_owner o;
 SELECT role_template_id INTO STRICT root_template FROM public.eco_user_platform_role WHERE user_profile_id=root_id;
 SELECT id INTO STRICT accounting FROM public.eco_role_templates WHERE code='ADMINISTRACION_OPERATIVA_MICA';
 SELECT jsonb_agg(to_jsonb(s) ORDER BY s.user_profile_id,s.organization_id) INTO scope_before FROM private.eco_platform_org_scopes s;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 IF NOT private.can_platform('ORGANIZATION_CREATE') THEN RAISE EXCEPTION 'Root lost create'; END IF;
 INSERT INTO auth.users(id,email) VALUES(staff_auth,'039g-'||staff_auth||'@example.invalid');
 SELECT id INTO STRICT staff FROM public.eco_user_profiles WHERE auth_user_id=staff_auth;
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039g existing '||staff_auth));
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',accounting));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',staff,'is_active',TRUE));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
 FOREACH cap IN ARRAY ARRAY['ACCESS_ANY_ORG','ORGANIZATION_ARCHIVE','HARD_DELETE_EXCEPTIONAL','PLATFORM_MANAGE',
  'GLOBAL_USER_MANAGE','PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION','SUPPORT_IMPERSONATE'] LOOP
  IF private.can_platform(cap) THEN RAISE EXCEPTION 'Structural privilege leaked: %',cap; END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 result:=public.mica_admin_read(NULL,'');
 IF (result->'rights'->>'create_organization')::BOOLEAN IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'Create UI right missing'; END IF;
 created:=public.mica_admin_apply('organization',jsonb_build_object('name','039g created '||staff_auth));
 PERFORM public.switch_superadmin_org_context(created);
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'name','039g edited '||staff_auth));
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'is_active',FALSE));
  RAISE EXCEPTION 'Archive allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',root_id,'is_active',FALSE));
  RAISE EXCEPTION 'Root deactivation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',root_id,'role_template_id',accounting));
  RAISE EXCEPTION 'Root reassignment allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',root_id,'kind','platform','capability','ORGANIZATION_CREATE','effect','DENY'));
  RAISE EXCEPTION 'Root override allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',root_template,'name','tampered','scope','PLATFORM','is_active',FALSE,'capabilities','[]'::JSONB,'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Root preset modification allowed';
 EXCEPTION WHEN insufficient_privilege OR no_data_found THEN NULL; END;
 -- Historical root presets may not be registered in the editable MICA registry.
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('name','039g forbidden','scope','PLATFORM',
   'capabilities',jsonb_build_array('ACCESS_ANY_ORG'),'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Reserved capability delegated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH cap IN ARRAY ARRAY['ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','RECORD_CLASSIFY',
  'FINANCIAL_ALLOCATION_EDIT','MANUAL_MOVEMENT_CREATE','BANK_IMPORT','PAYROLL_IMPORT','PERCEPTION_IMPORT','FISCAL_DOCUMENT_IMPORT'] LOOP
  IF NOT public.can_operate_mica_org(created,cap) THEN RAISE EXCEPTION 'Functional authority missing: %',cap; END IF;
 END LOOP;
 PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
 PERFORM public.create_import('ARCA_EMITIDOS','VENTA');
 PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
 PERFORM public.create_import('PERCEPCIONES_ARBA','PERCEPCION');
 PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
 PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
 RESET ROLE;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=staff AND organization_id=created AND is_active)
  OR NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=staff AND organization_id=org AND is_active) THEN
  RAISE EXCEPTION 'Explicit scopes missing'; END IF;
 INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
  SELECT staff,id,'DENY' FROM public.eco_capabilities WHERE code='ORGANIZATION_CREATE';
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','039g denied'));
  RAISE EXCEPTION 'DENY failed to override base';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 IF (SELECT to_jsonb(o) FROM private.eco_platform_owner o) IS DISTINCT FROM original_owner THEN RAISE EXCEPTION 'Structural root changed'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(scope_before,'[]'::JSONB)) x WHERE NOT EXISTS
   (SELECT 1 FROM private.eco_platform_org_scopes s WHERE to_jsonb(s)=x)) THEN RAISE EXCEPTION 'Existing scopes changed'; END IF;
END; $test$;
ROLLBACK TO SAVEPOINT harness_039g_current_preset;
-- Exercise the actual DOWN and verify restoration without leaving the defective function installed.
SAVEPOINT harness_039i_down;
-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restores the exact defective 039h definition.
-- Roll back 039i BEFORE 039h. This deliberately restores the known ambiguity.
SELECT pg_advisory_xact_lock(380038);
DO $restore$
DECLARE v_saved RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039i DOWN requires postgres'; END IF;
 IF to_regclass('private.migration_039i_function') IS NULL THEN RAISE EXCEPTION '039i not installed'; END IF;
 SELECT * INTO STRICT v_saved FROM private.migration_039i_function;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.installed
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer
  AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='a3fbc3e14522dc603f5ba9010cebd9bf') THEN
  RAISE EXCEPTION '039i DOWN definition/owner/ACL/security drift'; END IF;
 EXECUTE v_saved.definition;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.definition
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer) THEN
  RAISE EXCEPTION '039i DOWN exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039i_function;

DO $restored$
BEGIN
 IF (SELECT pg_get_functiondef(to_regprocedure('public.mica_admin_apply(text,jsonb)')))
   IS DISTINCT FROM (SELECT saved_function.installed FROM private.migration_039h_functions saved_function
    WHERE saved_function.signature='public.mica_admin_apply(text,jsonb)') THEN
  RAISE EXCEPTION '039i DOWN did not restore exact 039h definition'; END IF;
END; $restored$;
ROLLBACK TO SAVEPOINT harness_039i_down;
ROLLBACK;
