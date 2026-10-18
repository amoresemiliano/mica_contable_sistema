-- Refuse rollback while any file still needs the resumable contract.
-- Finish/resume those imports first; never delete imported business rows.
BEGIN;
DO $$
DECLARE r RECORD;
BEGIN
 IF EXISTS(SELECT 1 FROM private.import_chunk_progress WHERE NOT complete) THEN
  RAISE EXCEPTION '043 rollback blocked: incomplete imports require this contract'; END IF;
 FOR r IN SELECT * FROM private.migration_043_functions LOOP
  IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM r.installed_definition THEN
   RAISE EXCEPTION '043 rollback drift: %',r.signature; END IF;
  EXECUTE r.definition;
 END LOOP;
END; $$;
DROP FUNCTION public.get_resumable_import(TEXT);
DROP FUNCTION public.persist_import_chunk(UUID,JSONB,JSONB,TEXT,INTEGER,INTEGER);
DROP FUNCTION private.persist_perceptions_chunk_rows(UUID,JSONB,JSONB);
DROP FUNCTION private.persist_financial_chunk_rows(UUID,JSONB,JSONB);
DROP FUNCTION private.reuse_import_chunk_file(UUID,TEXT);
-- Preserve receipts for completed files as privileged audit archives.
ALTER TABLE private.import_chunk_receipts RENAME TO import_chunk_receipts_043_archive;
ALTER TABLE private.import_chunk_progress RENAME TO import_chunk_progress_043_archive;
ALTER TABLE private.migration_043_functions RENAME TO migration_043_functions_archive;
NOTIFY pgrst,'reload schema';
COMMIT;
