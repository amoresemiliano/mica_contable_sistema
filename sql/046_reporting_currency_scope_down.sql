-- Restore the exact pre-046 reporting projection; no source/history deletion.
BEGIN;
SET LOCAL search_path='';
SELECT pg_advisory_xact_lock(450045);
DO $rollback$
DECLARE b RECORD;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.migration_046_reporting') IS NULL THEN RAISE EXCEPTION '046 not installed or wrong owner'; END IF;
 SELECT * INTO STRICT b FROM private.migration_046_reporting;
 IF b.installed_definition IS NULL OR pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM b.installed_definition
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=b.view_oid AND relowner=b.owner_oid
   AND relacl IS NOT DISTINCT FROM b.acl AND reloptions IS NOT DISTINCT FROM b.options) THEN RAISE EXCEPTION '046 rollback view/security drift'; END IF;
 EXECUTE 'CREATE OR REPLACE VIEW private.reporting_045_facts AS '||b.definition;
 IF pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM b.definition
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=b.view_oid AND relowner=b.owner_oid
   AND relacl IS NOT DISTINCT FROM b.acl AND reloptions IS NOT DISTINCT FROM b.options) THEN RAISE EXCEPTION '046 rollback restoration failed'; END IF;
END; $rollback$;
DROP TABLE private.migration_046_reporting;
COMMIT;
