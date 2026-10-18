-- PREPARED ONLY, NOT EXECUTED. Requires 040; extends 039g authorization regressions.
-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; current contract AFTER 039h/039i/039j/039k.
-- All fixtures roll back. Historical ACCOUNTING_SUPERADMIN is tested only as forbidden.
BEGIN;
DO $test$
DECLARE root_id UUID; root_auth UUID; root_template UUID; staff UUID; staff_auth UUID:=gen_random_uuid();
 operational UUID; historical UUID; without_create UUID; org UUID; created UUID; cap TEXT; result JSONB; original_owner JSONB; scope_before JSONB;
BEGIN
 IF to_regclass('private.migration_039g_create') IS NULL THEN RAISE EXCEPTION 'Apply 039g first'; END IF;
 SELECT user_profile_id,auth_user_id,to_jsonb(o) INTO STRICT root_id,root_auth,original_owner FROM private.eco_platform_owner o;
 SELECT role_template_id INTO STRICT root_template FROM public.eco_user_platform_role WHERE user_profile_id=root_id;
 SELECT id INTO STRICT operational FROM public.eco_role_templates WHERE code='ADMINISTRACION_OPERATIVA_MICA' AND scope='PLATFORM' AND is_active;
 SELECT id INTO STRICT historical FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN' AND NOT is_active;
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=root_template AND code='VEGEN_PLATFORM_ADMIN' AND is_active) THEN
  RAISE EXCEPTION 'Root preset changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_CREATE' AND scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE' AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_ARCHIVE' AND delegation_class='OWNER_RESERVED' AND is_active) THEN
  RAISE EXCEPTION 'Create/archive delegation contract changed'; END IF;
 SELECT jsonb_agg(to_jsonb(s) ORDER BY s.user_profile_id,s.organization_id) INTO scope_before FROM private.eco_platform_org_scopes s;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 IF NOT private.can_platform('ORGANIZATION_CREATE') THEN RAISE EXCEPTION 'Root lost create'; END IF;
 INSERT INTO auth.users(id,email) VALUES(staff_auth,'039g-'||staff_auth||'@example.invalid');
 SELECT id INTO STRICT staff FROM public.eco_user_profiles WHERE auth_user_id=staff_auth;
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039g existing '||staff_auth));
 BEGIN
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',historical));
  RAISE EXCEPTION 'Deprecated ACCOUNTING_SUPERADMIN assignment allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',operational));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',staff,'is_active',TRUE));
 -- A scoped platform fixture without CREATE must be denied even without an explicit DENY.
 without_create:=public.mica_admin_apply('preset',jsonb_build_object('name','039g without create','scope','PLATFORM',
  'capabilities',jsonb_build_array('ORGANIZATION_UPDATE'),'bridge','[]'::JSONB));
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',without_create));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=staff) THEN RAISE EXCEPTION 'Artificial platform membership'; END IF;
 PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
 IF private.can_platform('ORGANIZATION_CREATE') THEN RAISE EXCEPTION 'Missing capability fixture unexpectedly authorized'; END IF;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','039g missing capability'));
  RAISE EXCEPTION 'Creation without capability allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',operational));
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
 created:=public.mica_admin_apply('organization',jsonb_build_object('name','040 created '||staff_auth,'phone','create-phone','email','create-email','contact_person','create-contact_person','website','create-website','address','create-address'));
 result:=public.mica_admin_read(NULL,'');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') row_json
  WHERE row_json->>'id'=created::TEXT AND row_json @> jsonb_build_object('phone','create-phone','email','create-email','contact_person','create-contact_person','website','create-website','address','create-address')) THEN
  RAISE EXCEPTION '040 create/readback mismatch'; END IF;
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'phone','update-phone','email','update-email','contact_person','update-contact_person','website','update-website','address','update-address'));
 result:=public.mica_admin_read(NULL,'');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') row_json
  WHERE row_json->>'id'=created::TEXT AND row_json @> jsonb_build_object('phone','update-phone','email','update-email','contact_person','update-contact_person','website','update-website','address','update-address')) THEN
  RAISE EXCEPTION '040 update/readback mismatch'; END IF;
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'name','040 partial'));
 result:=public.mica_admin_read(NULL,'');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') row_json
  WHERE row_json->>'id'=created::TEXT AND row_json @> jsonb_build_object('phone','update-phone','email','update-email','contact_person','update-contact_person','website','update-website','address','update-address')) THEN
  RAISE EXCEPTION '040 partial update lost fields'; END IF;
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'phone',NULL));
 result:=public.mica_admin_read(NULL,'');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') row_json
  WHERE row_json->>'id'=created::TEXT AND row_json @> jsonb_build_object('phone',NULL,'email','update-email','contact_person','update-contact_person','website','update-website','address','update-address')) THEN
  RAISE EXCEPTION '040 explicit null failed'; END IF;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'unexpected','value'));
  RAISE EXCEPTION '040 unsupported field accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'Unsupported organization field %' THEN RAISE; END IF;
 END;
 -- Remove only this fixture's scope and confirm profile-only updates cannot bypass it.
 RESET ROLE;
 DELETE FROM private.eco_platform_org_scopes WHERE user_profile_id=staff AND organization_id=created;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'email','outside'));
  RAISE EXCEPTION '040 out-of-scope update accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 result:=public.mica_admin_read(NULL,'');
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') row_json WHERE row_json->>'id'=created::TEXT) THEN
  RAISE EXCEPTION '040 hidden organization leaked'; END IF;
 RESET ROLE;
 INSERT INTO private.eco_platform_org_scopes(user_profile_id,organization_id,is_active) VALUES(staff,created,TRUE);
 INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
  SELECT staff,id,'DENY' FROM public.eco_capabilities WHERE code='ORGANIZATION_UPDATE';
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'address','denied'));
  RAISE EXCEPTION '040 denied UPDATE allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=staff
  AND capability_id IN(SELECT id FROM public.eco_capabilities WHERE code='ORGANIZATION_UPDATE');
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 without_create:=public.mica_admin_apply('preset',jsonb_build_object('name','040 create only','scope','PLATFORM',
  'capabilities',jsonb_build_array('ORGANIZATION_CREATE'),'bridge','[]'::JSONB));
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',without_create));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',created,'website','missing-update'));
  RAISE EXCEPTION '040 missing UPDATE allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',operational));
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
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
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',root_id,'role_template_id',operational));
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
 -- ACCESS_ANY_ORG is root-only and must not bypass an explicit DENY on creation.
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
  SELECT root_id,id,'DENY' FROM public.eco_capabilities WHERE code='ORGANIZATION_CREATE'
  ON CONFLICT(user_profile_id,capability_id) DO UPDATE SET effect='DENY';
 IF NOT private.can_platform('ACCESS_ANY_ORG') THEN RAISE EXCEPTION 'Root lost ACCESS_ANY_ORG'; END IF;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','039g root denied'));
  RAISE EXCEPTION 'ACCESS_ANY_ORG bypassed creation DENY';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 IF (SELECT to_jsonb(o) FROM private.eco_platform_owner o) IS DISTINCT FROM original_owner THEN RAISE EXCEPTION 'Structural root changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=root_id AND role_template_id=root_template AND is_active) THEN
  RAISE EXCEPTION 'Root assignment changed'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=historical AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=historical AND is_active) THEN
  RAISE EXCEPTION 'Deprecated preset reactivated or assigned'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(scope_before,'[]'::JSONB)) x WHERE NOT EXISTS
   (SELECT 1 FROM private.eco_platform_org_scopes s WHERE to_jsonb(s)=x)) THEN RAISE EXCEPTION 'Existing scopes changed'; END IF;
END; $test$;
ROLLBACK;
