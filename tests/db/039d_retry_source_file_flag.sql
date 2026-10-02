-- PREPARED ONLY. Human execution AFTER 039d on MICA ourzapkjykzlwsjunzmd.
-- Isolated fixtures; no upload, all changes rolled back.
BEGIN;
DO $test$
DECLARE root_auth UUID; org UUID; other_org UUID; original UUID; source_id UUID;
 retry_id UUID; unrelated UUID; envelope JSONB; retry JSONB; result JSONB;
 marker UUID:=gen_random_uuid(); hash TEXT:=md5(marker::TEXT)||md5(marker::TEXT);
 original_path TEXT; file_before JSONB;
BEGIN
 IF to_regclass('private.migration_039d_retry') IS NULL THEN RAISE EXCEPTION 'Apply 039d first'; END IF;
 SELECT auth_user_id INTO STRICT root_auth FROM private.eco_platform_owner;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039d fixture '||marker));
 other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039d other '||marker));
 PERFORM public.switch_superadmin_org_context(org);
 envelope:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
 original:=(envelope->>'import_id')::UUID;
 original_path:=(envelope->>'storage_prefix')||'/039d.csv';
 RESET ROLE;
 INSERT INTO public.eco_source_files(import_id,organization_id,original_name,storage_path,mime_type,size_bytes,sha256_hash,source_type)
 VALUES(original,org,'039d.csv',original_path,NULL,1,hash,'BANK_STATEMENT_BBVA') RETURNING id INTO source_id;
 SELECT to_jsonb(f) INTO STRICT file_before FROM public.eco_source_files f WHERE id=source_id;
 IF NOT EXISTS(SELECT 1 FROM public.eco_source_imports WHERE id=original AND accepted_rows=0)
  OR EXISTS(SELECT 1 FROM public.eco_import_rows WHERE file_id=source_id) THEN
  RAISE EXCEPTION 'Invalid empty-import fixture'; END IF;
 SET LOCAL ROLE authenticated;
 retry:=public.request_failed_import_retry(original);
 RESET ROLE;
 retry_id:=(retry->>'import_id')::UUID;
 IF retry_id IS NULL OR retry_id=original OR (retry->>'new_import_id')::UUID IS DISTINCT FROM retry_id
  OR (retry->>'original_import_id')::UUID IS DISTINCT FROM original
  OR (retry->>'organization_id')::UUID IS DISTINCT FROM org
  OR retry->>'storage_prefix' IS DISTINCT FROM org::TEXT||'/'||retry_id::TEXT THEN
  RAISE EXCEPTION 'Retry envelope/identity mismatch'; END IF;
 IF (retry->>'source_file_reused')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'NULL mime_type lost reuse flag'; END IF;
 IF retry->>'storage_path' IS DISTINCT FROM original_path THEN RAISE EXCEPTION 'Original path changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_source_imports WHERE id=retry_id
  AND retry_of_import_id=original AND organization_id=org AND accepted_rows=0) THEN
  RAISE EXCEPTION 'Retry lineage mismatch'; END IF;
 IF private.reuse_039c_file(retry_id,hash) IS DISTINCT FROM source_id THEN RAISE EXCEPTION 'Original file identity lost'; END IF;
 -- A normal import without this parent cannot adopt the existing hash.
 SET LOCAL ROLE authenticated;
 envelope:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
 RESET ROLE;
 unrelated:=(envelope->>'import_id')::UUID;
 BEGIN
  PERFORM private.reuse_039c_file(unrelated,hash);
  RAISE EXCEPTION 'Unrelated import reused file';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'FILE_ALREADY_EXISTS:%' THEN RAISE; END IF; END;
 -- An actual retry of another parent must also fail.
 SET LOCAL ROLE authenticated;
 result:=public.request_failed_import_retry(unrelated);
 RESET ROLE;
 IF (result->>'source_file_reused')::BOOLEAN IS DISTINCT FROM FALSE THEN RAISE EXCEPTION 'Missing file reported reused'; END IF;
 BEGIN
  PERFORM private.reuse_039c_file((result->>'import_id')::UUID,hash);
  RAISE EXCEPTION 'Wrong retry parent reused file';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'FILE_ALREADY_EXISTS:%' THEN RAISE; END IF; END;
 -- Reject cross-organization access through the authenticated public endpoint.
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(other_org);
 BEGIN
  PERFORM public.request_failed_import_retry(original);
  RAISE EXCEPTION 'Cross-organization retry accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.switch_superadmin_org_context(org);
 result:=public.persist_financial_movements_batch(retry_id,
  jsonb_build_object('original_name','039d.csv','storage_path',retry->>'storage_path',
   'mime_type','text/csv','size_bytes',1,'sha256_hash',hash),
  '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","monto":25,"tipo":"CREDITO","referencia":"039d","descripcion":"fixture"}}]');
 IF (result->>'accepted_rows')::INT IS DISTINCT FROM 1 OR (result->>'file_id')::UUID IS DISTINCT FROM source_id THEN
  RAISE EXCEPTION 'Persistence did not reuse same file'; END IF;
 RESET ROLE;
 IF (SELECT to_jsonb(f) FROM public.eco_source_files f WHERE id=source_id) IS DISTINCT FROM file_before
  OR (SELECT count(*) FROM public.eco_source_files WHERE organization_id=org AND sha256_hash=hash)<>1 THEN
  RAISE EXCEPTION 'Source metadata/hash/path changed or duplicated'; END IF;
 -- Reset counters ONLY in this rolled-back fixture to prove business rows independently block reuse.
 UPDATE public.eco_source_imports SET accepted_rows=0 WHERE id IN(original,retry_id);
 IF NOT EXISTS(SELECT 1 FROM public.eco_financial_movements fm
  JOIN public.eco_import_rows ir ON ir.id=fm.row_id WHERE ir.file_id=source_id) THEN
  RAISE EXCEPTION 'Expected business row missing'; END IF;
 BEGIN
  PERFORM private.reuse_039c_file(retry_id,hash);
  RAISE EXCEPTION 'Business rows allowed reuse';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'FILE_ALREADY_EXISTS:%' THEN RAISE; END IF; END;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.request_failed_import_retry(original);
  RAISE EXCEPTION 'Business rows allowed retry';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CANNOT_REPROCESS:%' THEN RAISE; END IF; END;
 RESET ROLE;
END; $test$;
ROLLBACK;
