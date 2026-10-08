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
 counters RECORD; rows_before INTEGER;
BEGIN
 SELECT auth_user_id INTO STRICT root_auth FROM private.eco_platform_owner;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(NULL);
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','043 fixture '||gen_random_uuid()));
 other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','043 isolation '||gen_random_uuid()));
 PERFORM public.switch_superadmin_org_context(org);
 FOREACH kind IN ARRAY ARRAY['FINANCIAL','PERCEPCION'] LOOP
  FOREACH n IN ARRAY ARRAY[1,499,500,501,1000,1001] LOOP
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
      -- A malformed chunk aborts its transaction and must leave chunk 0 resumable.
      BEGIN
       PERFORM public.persist_import_chunk(id,meta,bad,kind,chunk,n+1);
       RAISE EXCEPTION 'Changed manifest accepted';
      EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT IN ('Chunk manifest changed','Invalid chunk size (maximum 500)') THEN RAISE; END IF; END;
      resume:=public.get_resumable_import(hash);
      IF resume->>'import_id' IS DISTINCT FROM id::TEXT OR (resume->>'source_file_reused')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'Resume identity changed'; END IF;
      SELECT status,total_rows,accepted_rows,completed_at INTO counters FROM public.eco_source_imports WHERE eco_source_imports.id=id;
      IF counters.status<>'PROCESSING' OR counters.total_rows<>500 OR counters.accepted_rows<>500 OR counters.completed_at IS NOT NULL THEN RAISE EXCEPTION 'Partial import was completed'; END IF;
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
     SELECT count(*) INTO rows_before FROM public.eco_import_rows WHERE file_id=file;
     result:=public.persist_import_chunk(id,meta,bad,kind,chunk,n);
     IF rows_before IS DISTINCT FROM (SELECT count(*)::INTEGER FROM public.eco_import_rows WHERE file_id=file) THEN RAISE EXCEPTION 'Receipt replay duplicated rows'; END IF;
     BEGIN
      PERFORM public.persist_import_chunk(id,meta,jsonb_set(bad,'{0,rawRow}', '["changed"]'),kind,chunk,n);
      RAISE EXCEPTION 'Changed replay accepted';
     EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'Chunk replay payload changed' THEN RAISE; END IF; END;
    END LOOP;
    IF (result->>'complete')::BOOLEAN IS NOT TRUE THEN RAISE EXCEPTION 'Final chunk incomplete'; END IF;
   END IF;
   IF (result->>'accepted_rows')::INTEGER<>n OR (result->>'total_rows')::INTEGER<>n THEN RAISE EXCEPTION 'Wrong aggregate counters'; END IF;
   IF (SELECT count(*) FROM public.eco_source_files WHERE import_id=id)<>1 THEN RAISE EXCEPTION 'Multiple canonical files'; END IF;
   SELECT status,total_rows,accepted_rows,completed_at INTO counters FROM public.eco_source_imports WHERE eco_source_imports.id=id;
   IF counters.status<>'COMPLETED' OR counters.total_rows<>n OR counters.accepted_rows<>n OR counters.completed_at IS NULL THEN RAISE EXCEPTION 'Finalization failed'; END IF;
   IF public.get_resumable_import(hash) IS NOT NULL THEN RAISE EXCEPTION 'Completed import still resumable'; END IF;
  END LOOP;
 END LOOP;
 RESET ROLE;
END; $test$;
ROLLBACK;
