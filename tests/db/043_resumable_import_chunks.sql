-- PREPARED ONLY. Run manually in DEV after 043, as privileged harness owner.
-- Runtime writes/assertions use authenticated public RPCs. No fixture rows persist.
BEGIN;
-- Privileged, rollback-only failure injection. The assertion still calls public RPCs.
CREATE TEMP TABLE _043_harness_marker(id INTEGER);
CREATE FUNCTION pg_temp.fail_043_second_chunk() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF current_setting('mica.harness_chunk_failure',TRUE)='on' AND NEW.source_row_number=504 THEN
  RAISE EXCEPTION '043 injected chunk failure'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER test_043_chunk_failure AFTER INSERT ON public.eco_import_rows
 FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_043_second_chunk();
DO $test$
#variable_conflict use_variable
DECLARE root_auth UUID; org UUID; other_org UUID; envelope JSONB; meta JSONB; result JSONB; resume JSONB;
 id UUID; file UUID; hash TEXT; kind TEXT; n INTEGER; chunk INTEGER; payload JSONB; bad JSONB;
 counters RECORD; rows_before INTEGER; rows_after INTEGER; conflicting_import UUID; conflicting_meta JSONB;
 canonical_file UUID; files_by_import INTEGER; files_by_hash INTEGER; visible_files INTEGER;
 authenticated_select BOOLEAN; import_view BOOLEAN; operational_context JSONB; duplicate_check JSONB;
 diagnostic_role TEXT;
BEGIN
 SELECT auth_user_id INTO STRICT root_auth FROM private.eco_platform_owner;
 -- Privileged catalog diagnostic: restrictive guards are not proof of direct visibility.
 RAISE NOTICE '043 SELECT policies: %', (SELECT jsonb_agg(jsonb_build_object(
  'table',tablename,'policy',policyname,'permissive',permissive,'roles',roles,'qual',qual))
  FROM pg_policies WHERE schemaname='public' AND tablename IN ('eco_source_files','eco_source_imports','eco_import_rows') AND cmd IN ('SELECT','ALL'));
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(NULL);
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','043 fixture '||gen_random_uuid()));
 other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','043 isolation '||gen_random_uuid()));
 PERFORM public.switch_superadmin_org_context(org);
 FOREACH kind IN ARRAY ARRAY['FINANCIAL','PERCEPCION'] LOOP
  FOREACH n IN ARRAY ARRAY[1,499,500,501,1000,1001] LOOP
   canonical_file:=NULL;
   operational_context:=public.get_my_operational_context();
   IF (operational_context->>'organization_id')::UUID IS DISTINCT FROM org THEN RAISE EXCEPTION '043 operational context changed: expected %, observed %',org,operational_context->>'organization_id'; END IF;
   envelope:=public.create_import(CASE WHEN kind='FINANCIAL' THEN 'BANK_STATEMENT_BBVA' ELSE 'PERCEPCIONES_IVA' END,
    CASE WHEN kind='FINANCIAL' THEN 'BANCO' ELSE 'PERCEPCION' END);
   id:=(envelope->>'import_id')::UUID; hash:=md5(id::TEXT)||md5(id::TEXT);
   meta:=jsonb_build_object('original_name','043-synthetic.csv','storage_path',(envelope->>'storage_prefix')||'/043-synthetic.csv',
    'mime_type','text/csv','size_bytes',n,'sha256_hash',hash);
   SELECT jsonb_agg(jsonb_build_object('sourceRowNumber',i+3,'rawRow',jsonb_build_array('synthetic',i),
    'errors','[]'::JSONB,'warnings','[]'::JSONB,'normalizedData',CASE WHEN kind='FINANCIAL' THEN
     jsonb_build_object('fecha','2026-07-01','referencia',id::TEXT||'-'||i,'descripcion','Synthetic','accountIdentifier','TEST','monto',i,'tipo','credit')
    ELSE jsonb_build_object('cuit','30999999991','fecha','01/07/2026','comprobante',id::TEXT||'-'||i,'monto',i,'tipo','retencion','jurisdiction','NACIONAL (IVA)','fuente','IVA') END) ORDER BY i)
    INTO payload FROM generate_series(1,n) i;
   IF n<=500 THEN
    result:=CASE WHEN kind='FINANCIAL' THEN public.persist_financial_movements_batch(id,meta,payload)
     ELSE public.persist_perceptions_batch(id,meta,payload) END;
   ELSE
    FOR chunk IN 0..((n-1)/500) LOOP
     SELECT jsonb_agg(x ORDER BY ord) INTO bad FROM jsonb_array_elements(payload) WITH ORDINALITY t(x,ord)
      WHERE ord>chunk*500 AND ord<=LEAST((chunk+1)*500,n);
     IF chunk=1 THEN
      -- Failure after entering the canonical row worker must roll back the whole chunk.
      PERFORM set_config('mica.harness_chunk_failure','on',TRUE);
      BEGIN
       PERFORM public.persist_import_chunk(id,meta,bad,kind,chunk,n);
       RAISE EXCEPTION 'Injected failure was ignored';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'043 injected chunk failure' THEN RAISE; END IF; END;
      PERFORM set_config('mica.harness_chunk_failure','off',TRUE);
      BEGIN
       PERFORM public.persist_import_chunk(id,jsonb_set(meta,'{original_name}','"changed.csv"'),bad,kind,chunk,n);
       RAISE EXCEPTION 'Changed file metadata accepted';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Chunk manifest changed' THEN RAISE; END IF; END;
      envelope:=public.create_import(CASE WHEN kind='FINANCIAL' THEN 'BANK_STATEMENT_BBVA' ELSE 'PERCEPCIONES_IVA' END,
       CASE WHEN kind='FINANCIAL' THEN 'BANCO' ELSE 'PERCEPCION' END);
      conflicting_import:=(envelope->>'import_id')::UUID;
      conflicting_meta:=jsonb_set(meta,'{storage_path}',to_jsonb((envelope->>'storage_prefix')||'/043-synthetic.csv'));
      BEGIN
       PERFORM CASE WHEN kind='FINANCIAL' THEN public.persist_financial_movements_batch(conflicting_import,conflicting_meta,bad)
        ELSE public.persist_perceptions_batch(conflicting_import,conflicting_meta,bad) END;
       RAISE EXCEPTION 'Same hash different import accepted';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'FILE_ALREADY_EXISTS:%' THEN RAISE; END IF; END;
      -- A malformed chunk aborts its transaction and must leave chunk 0 resumable.
      BEGIN
       PERFORM public.persist_import_chunk(id,meta,bad,kind,chunk,n+1);
       RAISE EXCEPTION 'Changed manifest accepted';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT IN ('Chunk manifest changed','Invalid chunk size (maximum 500)') THEN RAISE; END IF; END;
      resume:=public.get_resumable_import(hash);
      IF resume->>'import_id' IS DISTINCT FROM id::TEXT OR (resume->>'source_file_reused')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'Resume identity changed'; END IF;
      -- Internal lifecycle evidence is checked as owner, never through RLS-filtered reads.
      RESET ROLE;
      SELECT status,total_rows,accepted_rows,completed_at INTO STRICT counters FROM public.eco_source_imports WHERE eco_source_imports.id=id AND organization_id=org;
      IF counters.status<>'PROCESSING' OR counters.total_rows<>500 OR counters.accepted_rows<>500 OR counters.completed_at IS NOT NULL THEN RAISE EXCEPTION 'Partial import was completed'; END IF;
      SELECT count(*) INTO files_by_import FROM public.eco_source_files WHERE import_id=id;
      IF files_by_import<>1 THEN RAISE EXCEPTION 'Canonical file count after failed chunk: import %, expected 1, observed %',id,files_by_import; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.eco_source_files WHERE eco_source_files.id=canonical_file AND import_id=id AND organization_id=org AND sha256_hash=hash) THEN RAISE EXCEPTION 'Failed chunk changed canonical file identity'; END IF;
      SET LOCAL ROLE authenticated;
      BEGIN
       PERFORM CASE WHEN kind='FINANCIAL' THEN public.persist_financial_movements_batch(id,meta,bad)
         ELSE public.persist_perceptions_batch(id,meta,bad) END;
       RAISE EXCEPTION 'Legacy mixed with chunks';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Use persist_import_chunk for this import' THEN RAISE; END IF; END;
      PERFORM public.switch_superadmin_org_context(other_org);
      IF public.get_resumable_import(hash) IS NOT NULL THEN RAISE EXCEPTION 'Cross-org manifest leaked'; END IF;
      BEGIN PERFORM public.persist_import_chunk(id,meta,bad,kind,chunk,n); RAISE EXCEPTION 'Cross-org chunk accepted';
      EXCEPTION WHEN insufficient_privilege THEN NULL; END;
      PERFORM public.switch_superadmin_org_context(org);
     END IF;
     result:=public.persist_import_chunk(id,meta,bad,kind,chunk,n);
     file:=(result->>'file_id')::UUID;
     IF file IS NULL THEN RAISE EXCEPTION 'Chunk % returned no canonical file_id',chunk; END IF;
     IF canonical_file IS NULL THEN canonical_file:=file;
     ELSIF canonical_file IS DISTINCT FROM file THEN RAISE EXCEPTION 'Chunk % changed canonical file_id: expected %, observed %',chunk,canonical_file,file; END IF;
     RESET ROLE;
     SELECT count(*) INTO files_by_import FROM public.eco_source_files WHERE import_id=id;
     IF files_by_import<>1 THEN RAISE EXCEPTION 'Canonical file count after chunk %: import %, expected 1, observed %',chunk,id,files_by_import; END IF;
     IF NOT EXISTS(SELECT 1 FROM public.eco_source_files WHERE eco_source_files.id=file AND import_id=id AND organization_id=org AND sha256_hash=hash) THEN RAISE EXCEPTION 'Chunk file provenance mismatch'; END IF;
     SELECT count(*) INTO rows_before FROM public.eco_import_rows WHERE file_id=file AND organization_id=org;
     IF rows_before IS DISTINCT FROM LEAST(n,(chunk+1)*500) THEN RAISE EXCEPTION 'Chunk row count mismatch: file %, expected %, observed %',file,LEAST(n,(chunk+1)*500),rows_before; END IF;
     SET LOCAL ROLE authenticated;
     result:=public.persist_import_chunk(id,meta,bad,kind,chunk,n);
     IF (result->>'file_id')::UUID IS DISTINCT FROM canonical_file THEN RAISE EXCEPTION 'Receipt replay changed canonical file_id'; END IF;
     RESET ROLE;
     SELECT count(*) INTO rows_after FROM public.eco_import_rows WHERE file_id=file AND organization_id=org;
     IF rows_before IS DISTINCT FROM rows_after THEN RAISE EXCEPTION 'Receipt replay row count mismatch: file %, before %, after %',file,rows_before,rows_after; END IF;
     SELECT count(*) INTO files_by_import FROM public.eco_source_files WHERE import_id=id;
     IF files_by_import<>1 THEN RAISE EXCEPTION 'Canonical file count after replay: import %, expected 1, observed %',id,files_by_import; END IF;
     SET LOCAL ROLE authenticated;
     BEGIN
      PERFORM public.persist_import_chunk(id,meta,jsonb_set(bad,'{0,rawRow}', '["changed"]'),kind,chunk,n);
      RAISE EXCEPTION 'Changed replay accepted';
     EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Chunk replay payload changed' THEN RAISE; END IF; END;
    END LOOP;
    IF (result->>'complete')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'Final chunk incomplete'; END IF;
   END IF;
   IF (result->>'accepted_rows')::INTEGER<>n OR (result->>'total_rows')::INTEGER<>n THEN RAISE EXCEPTION 'Wrong aggregate counters'; END IF;
   operational_context:=public.get_my_operational_context();
   IF (operational_context->>'organization_id')::UUID IS DISTINCT FROM org THEN RAISE EXCEPTION '043 final operational context changed: expected %, observed %',org,operational_context->>'organization_id'; END IF;
   import_view:=public.can_operate_mica_org(org,'IMPORT_VIEW');
   diagnostic_role:=current_user;
   authenticated_select:=has_table_privilege(current_user,'public.eco_source_files','SELECT');
   visible_files:=NULL;
   -- Optional visibility diagnostic, not an assertion of the public persistence contract.
   -- Dynamic SQL avoids requiring SELECT when the privilege is absent.
   IF authenticated_select THEN
    BEGIN EXECUTE 'SELECT count(*) FROM public.eco_source_files WHERE import_id=$1' INTO visible_files USING id;
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE '043 direct file diagnostic denied: %',SQLERRM; END;
   END IF;
   duplicate_check:=public.check_file_importable(hash);
   IF (duplicate_check->>'importable')::BOOLEAN IS DISTINCT FROM FALSE OR duplicate_check->>'existing_file_id' IS NULL THEN RAISE EXCEPTION 'Canonical file not observable through authorized hash check'; END IF;
   file:=(duplicate_check->>'existing_file_id')::UUID;
   IF canonical_file IS NOT NULL AND canonical_file IS DISTINCT FROM file THEN RAISE EXCEPTION 'Public hash check changed canonical file_id'; END IF;
   IF result->>'file_id' IS NOT NULL AND (result->>'file_id')::UUID IS DISTINCT FROM file THEN RAISE EXCEPTION 'Persist result and public hash check disagree on file_id'; END IF;
   RESET ROLE;
   SELECT count(*) INTO files_by_import FROM public.eco_source_files WHERE import_id=id;
   SELECT count(*) INTO files_by_hash FROM public.eco_source_files WHERE organization_id=org AND sha256_hash=hash;
   RAISE NOTICE '043 file counts: kind %, size %, import %, active org %, role %, authenticated SELECT %, IMPORT_VIEW %, authenticated observed %, owner by import %, owner by hash %',kind,n,id,operational_context->>'organization_id',diagnostic_role,authenticated_select,import_view,visible_files,files_by_import,files_by_hash;
   IF files_by_import<>1 THEN RAISE EXCEPTION 'Canonical file count mismatch: import %, expected 1, observed % (authenticated observed %)',id,files_by_import,visible_files; END IF;
   IF files_by_hash<>1 THEN RAISE EXCEPTION 'Canonical hash count mismatch: org %, expected 1, observed %',org,files_by_hash; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.eco_source_files WHERE eco_source_files.id=file AND import_id=id AND organization_id=org AND sha256_hash=hash) THEN RAISE EXCEPTION 'Canonical file provenance mismatch'; END IF;
   SELECT count(*) INTO rows_after FROM public.eco_import_rows WHERE file_id=file AND organization_id=org;
   IF rows_after IS DISTINCT FROM n THEN RAISE EXCEPTION 'Final staged row count mismatch: import %, expected %, observed %',id,n,rows_after; END IF;
   SELECT status,total_rows,accepted_rows,completed_at INTO STRICT counters FROM public.eco_source_imports WHERE eco_source_imports.id=id AND organization_id=org;
   IF counters.status<>'COMPLETED' OR counters.total_rows<>n OR counters.accepted_rows<>n OR counters.completed_at IS NULL THEN RAISE EXCEPTION 'Finalization failed'; END IF;
   SET LOCAL ROLE authenticated;
   IF public.get_resumable_import(hash) IS NOT NULL THEN RAISE EXCEPTION 'Completed import still resumable'; END IF;
  END LOOP;
 END LOOP;
 RESET ROLE;
END; $test$;
ROLLBACK;
