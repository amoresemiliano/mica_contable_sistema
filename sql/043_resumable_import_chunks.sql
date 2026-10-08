-- DEV-IMPORT-COMPATIBILITY-01. Prepared for manual DEV application; not executed.
-- Add receipts around the pinned canonical row validators, without raising 500.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF to_regclass('private.import_chunk_progress') IS NOT NULL THEN RAISE EXCEPTION '043 already installed'; END IF;
 IF to_regclass('private.import_chunk_progress_043_archive') IS NOT NULL THEN RAISE EXCEPTION '043 archives exist: review reinstallation explicitly'; END IF;
 IF to_regclass('private.migration_042_functions') IS NULL THEN RAISE EXCEPTION '042 required'; END IF;
 FOR r IN SELECT * FROM (VALUES
  ('public.persist_perceptions_batch(uuid,jsonb,jsonb)','40dbadc3ae53eae13a0b114e025d50d0'),
  ('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','cb4d7d4346e6d85dc965aaa7ffa7a488')
 ) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
   AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
   AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
   RAISE EXCEPTION '043 canonical function drift: %',r.signature; END IF;
 END LOOP;
 IF to_regprocedure('public.persist_import_chunk(uuid,jsonb,jsonb,text,integer,integer)') IS NOT NULL
  OR to_regprocedure('public.get_resumable_import(text)') IS NOT NULL THEN RAISE EXCEPTION '043 RPC collision'; END IF;
END; $preflight$;

CREATE TABLE private.migration_043_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed_definition TEXT);
CREATE TABLE private.import_chunk_progress(
 import_id UUID PRIMARY KEY REFERENCES public.eco_source_imports(id),
 organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
 sha256_hash TEXT NOT NULL CHECK(sha256_hash ~ '^[0-9a-f]{64}$'),
 kind TEXT NOT NULL CHECK(kind IN ('FINANCIAL','PERCEPCION')),
 file_info JSONB NOT NULL, expected_rows INTEGER NOT NULL CHECK(expected_rows>500),
 next_chunk_index INTEGER NOT NULL DEFAULT 0, last_source_row INTEGER NOT NULL DEFAULT 0,
 total_rows INTEGER NOT NULL DEFAULT 0, accepted_rows INTEGER NOT NULL DEFAULT 0,
 invalid_rows INTEGER NOT NULL DEFAULT 0, duplicate_rows INTEGER NOT NULL DEFAULT 0,
 has_issues BOOLEAN NOT NULL DEFAULT FALSE, complete BOOLEAN NOT NULL DEFAULT FALSE,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(organization_id,sha256_hash));
CREATE TABLE private.import_chunk_receipts(
 import_id UUID NOT NULL REFERENCES private.import_chunk_progress(import_id),
 chunk_index INTEGER NOT NULL CHECK(chunk_index>=0), payload_hash TEXT NOT NULL,
 result JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(import_id,chunk_index));
ALTER TABLE private.migration_043_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.import_chunk_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.import_chunk_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_043_functions,private.import_chunk_progress,private.import_chunk_receipts FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_043_functions(signature,definition)
 SELECT s,pg_get_functiondef(to_regprocedure(s)) FROM (VALUES
 ('public.persist_perceptions_batch(uuid,jsonb,jsonb)'),('public.persist_financial_movements_batch(uuid,jsonb,jsonb)')) x(s);

CREATE FUNCTION private.reuse_import_chunk_file(p_import UUID,p_hash TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.eco_source_files%ROWTYPE; org UUID:=private.active_org_id();
BEGIN
 PERFORM private.require_039_batch(p_import,ARRAY['BANCO','SUELDO','PERCEPCION']);
 IF NOT EXISTS(SELECT 1 FROM private.import_chunk_progress WHERE import_id=p_import AND organization_id=org
   AND sha256_hash=p_hash AND NOT complete) THEN RAISE EXCEPTION 'No authorized chunk manifest'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::TEXT||p_hash,39));
 SELECT * INTO f FROM public.eco_source_files WHERE organization_id=org AND sha256_hash=p_hash FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF f.import_id IS DISTINCT FROM p_import THEN RAISE EXCEPTION 'FILE_ALREADY_EXISTS: another canonical import'; END IF;
 RETURN f.id;
END; $$;

-- Private workers preserve every canonical row/auth check and the 500-row cap.
-- Pinning the bodies above makes these explicit substitutions fail closed on drift.
DO $workers$
DECLARE r RECORD; worker TEXT; definition TEXT; guarded TEXT;
BEGIN
 FOR r IN SELECT * FROM private.migration_043_functions LOOP
  worker:=CASE WHEN r.signature LIKE '%perceptions%' THEN 'persist_perceptions_chunk_rows' ELSE 'persist_financial_chunk_rows' END;
  definition:=replace(replace(r.definition,chr(13),''),
   CASE WHEN r.signature LIKE '%perceptions%' THEN 'FUNCTION public.persist_perceptions_batch' ELSE 'FUNCTION public.persist_financial_movements_batch' END,
   'FUNCTION private.'||worker);
  definition:=replace(definition,'private.reuse_039c_file(','private.reuse_import_chunk_file(');
  definition:=replace(definition,'''IMPORT_COMPLETED''','''IMPORT_CHUNK_APPLIED''');
  -- Perception worker accepts PROCESSING; its public endpoint keeps PENDING-only.
  definition:=replace(definition,'v_import_record.status != ''PENDING''','v_import_record.status NOT IN (''PENDING'', ''PROCESSING'')');
  EXECUTE definition;
  -- Prevent mixing a legacy batch endpoint with the resumable receipt protocol.
  guarded:=regexp_replace(replace(r.definition,chr(13),''),E'BEGIN\n',E'BEGIN\n  IF EXISTS(SELECT 1 FROM private.import_chunk_progress WHERE import_id=p_import_id) THEN\n    RAISE EXCEPTION ''Use persist_import_chunk for this import'';\n  END IF;\n');
  IF guarded=replace(r.definition,chr(13),'') THEN RAISE EXCEPTION '043 guard insertion failed'; END IF;
  EXECUTE guarded;
 END LOOP;
END; $workers$;

CREATE FUNCTION public.persist_import_chunk(
 p_import_id UUID,p_file_info JSONB,p_staged_rows JSONB,p_kind TEXT,p_chunk_index INTEGER,p_total_rows INTEGER)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.active_org_id(); imp public.eco_source_imports%ROWTYPE;
 progress private.import_chunk_progress%ROWTYPE; receipt private.import_chunk_receipts%ROWTYPE;
 result JSONB; digest TEXT; file UUID; n INTEGER; last_row INTEGER; worker_has_issues BOOLEAN;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN ('FINANCIAL','PERCEPCION') THEN RAISE EXCEPTION 'Invalid chunk kind'; END IF;
 PERFORM private.require_039_batch(p_import_id,CASE WHEN p_kind='PERCEPCION' THEN ARRAY['PERCEPCION'] ELSE ARRAY['BANCO','SUELDO'] END);
 SELECT * INTO STRICT imp FROM public.eco_source_imports WHERE id=p_import_id AND organization_id=org FOR UPDATE;
 IF imp.created_by IS DISTINCT FROM private.current_profile_id() THEN RAISE EXCEPTION 'Only import creator may resume' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(p_file_info) IS DISTINCT FROM 'object' OR jsonb_typeof(p_staged_rows) IS DISTINCT FROM 'array'
  OR p_chunk_index IS NULL OR p_chunk_index<0 OR p_total_rows IS NULL OR p_total_rows<=500
  OR p_chunk_index::BIGINT*500>=p_total_rows THEN RAISE EXCEPTION 'Invalid chunk envelope'; END IF;
 n:=jsonb_array_length(p_staged_rows);
 IF n<1 OR n>500 OR n<>LEAST(500,p_total_rows-p_chunk_index*500) THEN RAISE EXCEPTION 'Invalid chunk size (maximum 500)'; END IF;
 IF COALESCE(p_file_info->>'sha256_hash','') !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid source hash'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_staged_rows) x WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
   OR COALESCE(x->>'sourceRowNumber','') !~ '^[1-9][0-9]{0,8}$') THEN RAISE EXCEPTION 'Invalid source row trace'; END IF;
 IF EXISTS(SELECT 1 FROM (SELECT (x->>'sourceRowNumber')::INTEGER row_number,
   lag((x->>'sourceRowNumber')::INTEGER) OVER(ORDER BY ordinal) previous
   FROM jsonb_array_elements(p_staged_rows) WITH ORDINALITY t(x,ordinal)) q WHERE row_number<=previous) THEN
   RAISE EXCEPTION 'Source row numbers must increase'; END IF;
 SELECT * INTO progress FROM private.import_chunk_progress WHERE import_id=p_import_id FOR UPDATE;
 IF NOT FOUND THEN
  IF p_chunk_index<>0 OR imp.status<>'PENDING' OR COALESCE(imp.total_rows,0)<>0
    OR EXISTS(SELECT 1 FROM public.eco_source_files WHERE import_id=p_import_id) THEN RAISE EXCEPTION 'Cannot start chunk import'; END IF;
  INSERT INTO private.import_chunk_progress(import_id,organization_id,sha256_hash,kind,file_info,expected_rows)
   VALUES(p_import_id,org,p_file_info->>'sha256_hash',p_kind,p_file_info,p_total_rows) RETURNING * INTO progress;
 END IF;
 IF progress.organization_id IS DISTINCT FROM org OR progress.kind IS DISTINCT FROM p_kind
  OR progress.file_info IS DISTINCT FROM p_file_info OR progress.expected_rows IS DISTINCT FROM p_total_rows THEN
   RAISE EXCEPTION 'Chunk manifest changed'; END IF;
 digest:=encode(extensions.digest(p_staged_rows::TEXT,'sha256'),'hex');
 SELECT * INTO receipt FROM private.import_chunk_receipts WHERE import_id=p_import_id AND chunk_index=p_chunk_index;
 IF FOUND THEN
  IF receipt.payload_hash IS DISTINCT FROM digest THEN RAISE EXCEPTION 'Chunk replay payload changed'; END IF;
  -- Return current aggregate; replay cannot insert rows or finalize a partial file.
 ELSE
  IF progress.complete OR imp.status NOT IN ('PENDING','PROCESSING') OR p_chunk_index<>progress.next_chunk_index THEN
   RAISE EXCEPTION 'Chunk out of sequence or import already completed'; END IF;
  IF (p_staged_rows->0->>'sourceRowNumber')::INTEGER<=progress.last_source_row THEN RAISE EXCEPTION 'Source trace overlaps earlier chunk'; END IF;
  result:=CASE WHEN p_kind='PERCEPCION' THEN private.persist_perceptions_chunk_rows(p_import_id,p_file_info,p_staged_rows)
    ELSE private.persist_financial_chunk_rows(p_import_id,p_file_info,p_staged_rows) END;
  IF (result->>'total_rows')::INTEGER IS DISTINCT FROM n THEN RAISE EXCEPTION 'Canonical worker counter mismatch'; END IF;
  SELECT status='COMPLETED_WITH_ISSUES' INTO worker_has_issues FROM public.eco_source_imports WHERE id=p_import_id;
  last_row:=(p_staged_rows->(n-1)->>'sourceRowNumber')::INTEGER;
  UPDATE private.import_chunk_progress SET next_chunk_index=next_chunk_index+1,last_source_row=last_row,
    total_rows=total_rows+n,accepted_rows=accepted_rows+(result->>'accepted_rows')::INTEGER,
    invalid_rows=invalid_rows+(result->>'invalid_rows')::INTEGER,duplicate_rows=duplicate_rows+(result->>'duplicate_rows')::INTEGER,
    has_issues=import_chunk_progress.has_issues OR worker_has_issues,complete=total_rows+n=expected_rows,updated_at=now()
    WHERE import_id=p_import_id RETURNING * INTO progress;
  -- Workers finalize one batch; overwrite within this same transaction, before visibility.
  UPDATE public.eco_source_imports SET status=CASE WHEN NOT progress.complete THEN 'PROCESSING'
    WHEN progress.has_issues THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
    total_rows=progress.total_rows,accepted_rows=progress.accepted_rows,invalid_rows=progress.invalid_rows,
    duplicate_rows=progress.duplicate_rows,completed_at=CASE WHEN progress.complete THEN now() ELSE NULL END WHERE id=p_import_id;
  INSERT INTO private.import_chunk_receipts(import_id,chunk_index,payload_hash,result) VALUES(p_import_id,p_chunk_index,digest,result);
  INSERT INTO public.eco_audit_events(organization_id,event_type) VALUES(org,CASE WHEN progress.complete THEN 'IMPORT_COMPLETED' ELSE 'IMPORT_CHUNK_SAVED' END);
 END IF;
 SELECT id INTO STRICT file FROM public.eco_source_files WHERE import_id=p_import_id AND organization_id=org AND sha256_hash=progress.sha256_hash;
 RETURN jsonb_build_object('import_id',p_import_id,'file_id',file,'total_rows',progress.total_rows,'accepted_rows',progress.accepted_rows,
  'invalid_rows',progress.invalid_rows,'duplicate_rows',progress.duplicate_rows,'next_chunk_index',progress.next_chunk_index,'complete',progress.complete);
END; $$;

CREATE FUNCTION public.get_resumable_import(p_sha256_hash TEXT) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.active_org_id(); p private.import_chunk_progress%ROWTYPE; imp public.eco_source_imports%ROWTYPE; f public.eco_source_files%ROWTYPE;
BEGIN
 PERFORM private.require_039_action('IMPORT_VIEW');
 IF COALESCE(p_sha256_hash,'') !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid source hash'; END IF;
 SELECT * INTO p FROM private.import_chunk_progress WHERE organization_id=org AND sha256_hash=p_sha256_hash AND NOT complete;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM private.require_039_batch(p.import_id,CASE WHEN p.kind='PERCEPCION' THEN ARRAY['PERCEPCION'] ELSE ARRAY['BANCO','SUELDO'] END);
 SELECT * INTO STRICT imp FROM public.eco_source_imports WHERE id=p.import_id AND organization_id=org;
 IF imp.created_by IS DISTINCT FROM private.current_profile_id() OR imp.status<>'PROCESSING' THEN
  RAISE EXCEPTION 'Import is not resumable by caller' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT f FROM public.eco_source_files WHERE import_id=p.import_id AND organization_id=org AND sha256_hash=p.sha256_hash;
 RETURN jsonb_build_object('import_id',p.import_id,'organization_id',org,'storage_prefix',org::TEXT||'/'||p.import_id::TEXT,
  'source_file_reused',TRUE,'storage_path',f.storage_path,'file_info',p.file_info,'expected_rows',p.expected_rows,'next_chunk_index',p.next_chunk_index);
END; $$;

REVOKE ALL ON FUNCTION private.reuse_import_chunk_file(UUID,TEXT),private.persist_perceptions_chunk_rows(UUID,JSONB,JSONB),
 private.persist_financial_chunk_rows(UUID,JSONB,JSONB) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.persist_import_chunk(UUID,JSONB,JSONB,TEXT,INTEGER,INTEGER),public.get_resumable_import(TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.persist_import_chunk(UUID,JSONB,JSONB,TEXT,INTEGER,INTEGER),public.get_resumable_import(TEXT) TO authenticated;
UPDATE private.migration_043_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
NOTIFY pgrst,'reload schema';
COMMIT;
