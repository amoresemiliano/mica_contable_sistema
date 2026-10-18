-- Restores the defective 043 perception worker; requires no unfinished imports.
BEGIN;
DO $rollback$
DECLARE r RECORD;
BEGIN
 IF to_regclass('private.migration_044_functions') IS NULL THEN RAISE EXCEPTION '044 not installed'; END IF;
 IF EXISTS(SELECT 1 FROM private.import_chunk_progress WHERE NOT complete) THEN
  RAISE EXCEPTION '044 rollback blocked: finish incomplete imports first'; END IF;
 FOR r IN SELECT * FROM private.migration_044_functions LOOP
  IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM r.installed_definition THEN
   RAISE EXCEPTION '044 rollback definition drift: %',r.signature; END IF;
  EXECUTE r.definition;
 END LOOP;
END; $rollback$;
DROP TABLE private.migration_044_functions;
COMMIT;
