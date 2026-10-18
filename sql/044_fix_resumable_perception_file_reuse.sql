-- Prepared for manual DEV application after 043. Never rerun 043.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF to_regclass('private.migration_043_functions') IS NULL
  OR to_regclass('private.import_chunk_progress') IS NULL
  OR to_regclass('private.import_chunk_receipts') IS NULL THEN RAISE EXCEPTION '044 requires installed 043'; END IF;
 IF to_regclass('private.migration_044_functions') IS NOT NULL THEN RAISE EXCEPTION '044 already installed or partial installation'; END IF;
 FOR r IN SELECT * FROM (VALUES
 ('private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)','9df4e83cbdfd71cac12c49c94c151c8f'),
 ('private.persist_financial_chunk_rows(uuid,jsonb,jsonb)','b8028d83e96e47c5143936e53d545de2'),
 ('private.reuse_import_chunk_file(uuid,text)','9d256bcc9b11119e9115ee2cea63df62'),
 ('public.persist_import_chunk(uuid,jsonb,jsonb,text,integer,integer)','5f2738d947c45b099d0037da473cea6a'),
 ('public.get_resumable_import(text)','14e63a88a76f4b61658e6d7dc792ca51')
 ) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
   AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
   AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
   RAISE EXCEPTION '044 installed 043 definition drift: %',r.signature; END IF;
 END LOOP;
END; $preflight$;
CREATE TABLE private.migration_044_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed_definition TEXT);
ALTER TABLE private.migration_044_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_044_functions FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_044_functions(signature,definition)
 VALUES('private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)',pg_get_functiondef('private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)'::regprocedure));
-- Remove only the legacy unconditional import-file rejection. The later authorized
-- org/hash helper reuses the same import's file and rejects a different import.
DO $repair$
DECLARE
 before_definition TEXT; before_body TEXT; after_body TEXT; after_definition TEXT;
 before_owner OID; before_acl ACLITEM[]; before_config TEXT[];
 guard TEXT:=$guard$\mIF\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+public\.eco_source_files\s+WHERE\s+import_id\s*=\s*p_import_id\s*\)\s*THEN\s+RAISE\s+EXCEPTION\s+'File already registered for import %'\s*,\s*p_import_id\s*;\s*END\s+IF\s*;$guard$;
BEGIN
 SELECT definition INTO STRICT before_definition FROM private.migration_044_functions;
 SELECT prosrc,proowner,proacl,proconfig INTO STRICT before_body,before_owner,before_acl,before_config
 FROM pg_proc WHERE oid='private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)'::regprocedure;
 -- Primary drift protection, before any body transformation (also rejects an
 -- already repaired worker whose backup marker is missing).
 IF md5(btrim(replace(before_body,chr(13),''),' '||chr(10)||chr(9))) <> '9df4e83cbdfd71cac12c49c94c151c8f' THEN
  RAISE EXCEPTION '044 worker body drift or partial installation'; END IF;
 IF (SELECT count(*) FROM regexp_matches(before_body,guard,'g'))<>1 THEN
  RAISE EXCEPTION '044 expected exactly one legacy file guard'; END IF;
 after_body:=regexp_replace(before_body,guard,'-- 044: canonical file identity is checked by reuse_import_chunk_file below.');
 IF strpos(after_body,'File already registered for import')>0
  OR (SELECT count(*) FROM regexp_matches(after_body,'private\.reuse_import_chunk_file\s*\(','g'))<>1
  OR after_body !~ 'IF\s+v_existing_file_id\s+IS\s+NULL\s+THEN\s+INSERT\s+INTO\s+public\.eco_source_files'
 THEN RAISE EXCEPTION '044 repaired worker invariant failed'; END IF;
 -- Replace only the unchanged body within PostgreSQL's own definition. Keep
 -- the original definition byte-for-byte in the backup for rollback.
 IF (length(before_definition)-length(replace(before_definition,before_body,'')))/length(before_body)<>1 THEN
  RAISE EXCEPTION '044 expected exactly one worker body in definition'; END IF;
 after_definition:=replace(before_definition,before_body,after_body);
 EXECUTE after_definition;
 IF NOT EXISTS(SELECT 1 FROM pg_proc
  WHERE oid='private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)'::regprocedure
   AND prosrc=after_body AND prosecdef AND proconfig @> ARRAY['search_path=""']
   AND proowner=before_owner AND proacl IS NOT DISTINCT FROM before_acl
   AND proconfig IS NOT DISTINCT FROM before_config) THEN
  RAISE EXCEPTION '044 worker security, owner, grants or body changed unexpectedly'; END IF;
END; $repair$;
UPDATE private.migration_044_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
COMMIT;
