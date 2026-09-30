-- PREPARED ONLY. Human execution AFTER 039c on ourzapkjykzlwsjunzmd.
-- Auth inserts below are isolated TEST FIXTURES, never the invitation implementation.
BEGIN;
DO $test$
DECLARE root_id UUID; root_auth UUID; org UUID; other_org UUID; envelope JSONB; retry JSONB; result JSONB;
 manual UUID; import_id UUID; file_id UUID; row_id UUID; invitation UUID; preset UUID; platform_preset UUID;
 user_auth UUID:=gen_random_uuid(); v_user_id UUID; platform_auth UUID:=gen_random_uuid(); platform_user UUID;
 mail TEXT; hash TEXT:=md5(user_auth::TEXT)||md5(user_auth::TEXT); payload JSONB;
BEGIN
 IF to_regclass('private.migration_039c_functions') IS NULL THEN RAISE EXCEPTION 'Apply 039c first'; END IF;
 SELECT user_profile_id,auth_user_id INTO STRICT root_id,root_auth FROM private.eco_platform_owner;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039c fixture '||user_auth));
 other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039c other '||user_auth));
 PERFORM public.switch_superadmin_org_context(org);
 -- Approved fiscal paths and server envelopes.
 envelope:=public.create_import('ARCA_RECIBIDOS','COMPRA');
 IF envelope->>'storage_prefix'<>org::TEXT||'/'||(envelope->>'import_id') THEN RAISE EXCEPTION 'Bad create envelope'; END IF;
 result:=public.persist_import_batch((envelope->>'import_id')::UUID,
  jsonb_build_object('original_name','fiscal.csv','storage_path',(envelope->>'storage_prefix')||'/fiscal.csv','mime_type','text/csv','size_bytes',1,'sha256_hash',md5(org::TEXT)||md5(org::TEXT)),
  '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","cuit":"20222222224","tipo_cbte":"001","pdv":"00001","nroDesde":"123","moneda":"PES","total":121,"netoGravado":100,"totalIva":21}}]');
 IF (result->>'accepted_rows')::INT<>1 THEN RAISE EXCEPTION 'Fiscal pipeline failed'; END IF;
 PERFORM public.create_import('ARCA_EMITIDOS','VENTA');
 BEGIN PERFORM public.create_import('ARCA_EMITIDOS','COMPRA'); RAISE EXCEPTION 'Unsupported pair allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 payload:='{"kind":"INTERNAL","fields":{"tipo":"Gasto","fecha":"2026-09-01","imputacion":"2026-09","importe":"25.50","descripcion":"fixture"}}';
 manual:=(public.mica_manual_records('create',org,NULL,payload)->>'id')::UUID;
 IF jsonb_array_length(public.mica_manual_records('list',org))<>1 THEN RAISE EXCEPTION 'Manual not rehydrated'; END IF;
 PERFORM public.mica_manual_records('edit',org,manual,payload);
 PERFORM public.switch_superadmin_org_context(other_org);
 BEGIN PERFORM public.mica_manual_records('edit',org,manual,payload); RAISE EXCEPTION 'Stale context accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.mica_manual_records('delete',other_org,manual); RAISE EXCEPTION 'Cross-org record accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.switch_superadmin_org_context(org);
 PERFORM public.mica_manual_records('delete',org,manual);
 IF jsonb_array_length(public.mica_manual_records('list',org))<>0 THEN RAISE EXCEPTION 'Manual soft delete failed'; END IF;
 RESET ROLE;
 IF NOT EXISTS(SELECT 1 FROM private.eco_manual_records WHERE id=manual AND created_by=root_id AND deleted_by=root_id AND deleted_at IS NOT NULL) THEN
  RAISE EXCEPTION 'Manual provenance missing'; END IF;
 INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
  SELECT root_id,org,id,'DENY' FROM public.eco_capabilities WHERE code='MANUAL_MOVEMENT_CREATE';
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.mica_manual_records('create',org,NULL,payload); RAISE EXCEPTION 'Manual bypassed DENY';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=root_id AND organization_id=org;
 -- Failed bank fixture: retry creates a fresh complete envelope, reuses original file.
 SET LOCAL ROLE authenticated;
 envelope:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
 RESET ROLE;
 import_id:=(envelope->>'import_id')::UUID;
 INSERT INTO public.eco_source_files(import_id,organization_id,original_name,storage_path,size_bytes,sha256_hash,source_type)
  VALUES(import_id,org,'039c.csv',envelope->>'storage_prefix'||'/039c.csv',1,hash,'BANK_STATEMENT_BBVA') RETURNING id INTO file_id;
 SET LOCAL ROLE authenticated;
 retry:=public.request_failed_import_retry(import_id);
 IF retry->>'organization_id'<>org::TEXT OR retry->>'storage_prefix'<>org::TEXT||'/'||(retry->>'import_id') THEN RAISE EXCEPTION 'Retry envelope incomplete'; END IF;
 IF (retry->>'source_file_reused')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'Original source file not reused'; END IF;
 result:=public.mica_import_file_status(file_id);
 IF (result->>'total_rows')::INT<>0 THEN RAISE EXCEPTION 'Expected header without movements'; END IF;
 RESET ROLE;
 IF private.reuse_039c_file((retry->>'import_id')::UUID,hash) IS DISTINCT FROM file_id THEN RAISE EXCEPTION 'Retry file mismatch'; END IF;
 SET LOCAL ROLE authenticated;
 result:=public.persist_financial_movements_batch((retry->>'import_id')::UUID,
  jsonb_build_object('original_name','039c.csv','storage_path',retry->>'storage_path','mime_type','text/csv','size_bytes',1,'sha256_hash',hash),
  '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","monto":25,"tipo":"CREDITO","referencia":"039c","descripcion":"fixture"}}]');
 IF (result->>'file_id')::UUID IS DISTINCT FROM file_id THEN RAISE EXCEPTION 'Persist did not reuse original file'; END IF;
 IF (result->>'accepted_rows')::INT<>1 THEN RAISE EXCEPTION 'Retry bank pipeline failed'; END IF;
 result:=public.check_file_importable(hash);
 IF (result->>'importable')::BOOLEAN THEN RAISE EXCEPTION 'Downstream retry rows not detected'; END IF;
 result:=public.mica_import_file_status(file_id);
 IF (result->>'active_rows')::INT<>1 THEN RAISE EXCEPTION 'Bank retry lineage not visible'; END IF;
 envelope:=public.create_import('PAYROLL_ACONPY','SUELDO');
 result:=public.persist_financial_movements_batch((envelope->>'import_id')::UUID,
  jsonb_build_object('original_name','salary.txt','storage_path',(envelope->>'storage_prefix')||'/salary.txt','mime_type','text/plain','size_bytes',1,'sha256_hash',md5(platform_auth::TEXT)||md5(platform_auth::TEXT)),
  '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"periodo":"2026-09","sueldoNeto":25}}]');
 IF (result->>'accepted_rows')::INT<>1 THEN RAISE EXCEPTION 'Salary pipeline failed'; END IF;
 result:=public.mica_import_file_status((result->>'file_id')::UUID);
 IF (result->>'active_rows')::INT<>1 THEN RAISE EXCEPTION 'Salary lineage not visible'; END IF;
 RESET ROLE;
 BEGIN PERFORM private.reuse_039c_file((retry->>'import_id')::UUID,hash); RAISE EXCEPTION 'Retry duplicated downstream records';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'FILE_ALREADY_EXISTS:%' THEN RAISE; END IF; END;
 -- Preauthorization never activates. Confirmation binds a reviewed verified identity.
 SELECT id INTO STRICT preset FROM public.eco_role_templates WHERE code='MICA_ACCOUNTANT';
 SELECT id INTO STRICT platform_preset FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN';
 mail:='039c-'||user_auth||'@example.invalid';
 SET LOCAL ROLE authenticated;
 invitation:=(public.mica_invitation('create',org,jsonb_build_object('email',mail,'role_template_id',preset))->>'id')::UUID;
 BEGIN PERFORM public.mica_invitation('create',org,jsonb_build_object('email',mail,'role_template_id',preset)); RAISE EXCEPTION 'Duplicate email accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM public.mica_invitation('create',org,jsonb_build_object('email','scope-'||mail,'role_template_id',platform_preset)); RAISE EXCEPTION 'Incompatible preset accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(user_auth,mail,now());
 SELECT id INTO STRICT v_user_id FROM public.eco_user_profiles WHERE auth_user_id=user_auth AND NOT is_active;
 IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=v_user_id) THEN RAISE EXCEPTION 'Email alone granted membership'; END IF;
 SET LOCAL ROLE authenticated;
 result:=public.mica_invitation('assign',org,jsonb_build_object('id',invitation,'user_profile_id',v_user_id));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=v_user_id AND is_active) THEN RAISE EXCEPTION 'Assignment activated user'; END IF;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',v_user_id,'organization_id',org,'is_active',TRUE));
 PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',v_user_id,'organization_id',org,'kind','membership','capability','FISCAL_DOCUMENT_IMPORT','effect','DENY'));
 BEGIN PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',root_id,'is_active',FALSE)); RAISE EXCEPTION 'Root edited';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 invitation:=(public.mica_invitation('create',NULL,jsonb_build_object('email','039c-'||platform_auth||'@example.invalid','role_template_id',platform_preset))->>'id')::UUID;
 RESET ROLE;
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(platform_auth,'039c-'||platform_auth||'@example.invalid',now());
 SELECT id INTO STRICT platform_user FROM public.eco_user_profiles WHERE auth_user_id=platform_auth AND NOT is_active;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_invitation('assign',NULL,jsonb_build_object('id',invitation,'user_profile_id',platform_user));
 PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',platform_user,'is_active',TRUE));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=platform_user) THEN RAISE EXCEPTION 'Artificial platform membership'; END IF;
 PERFORM set_config('request.jwt.claim.sub',user_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA'); RAISE EXCEPTION 'Fiscal DENY ignored';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',platform_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',platform_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(org);
 PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
 RESET ROLE;
 IF private.can_platform('ACCESS_ANY_ORG') OR private.can_platform('PLATFORM_MANAGE') THEN RAISE EXCEPTION 'Delegated user acquired reserved authority'; END IF;
END; $test$;
ROLLBACK;
