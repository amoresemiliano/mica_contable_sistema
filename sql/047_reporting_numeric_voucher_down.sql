-- Restore the exact pre-047 reporting projection; no source/history deletion.
BEGIN;
SET LOCAL search_path='';
SELECT pg_advisory_xact_lock(450045);
DO $rollback$
DECLARE b RECORD;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.migration_047_reporting') IS NULL THEN RAISE EXCEPTION '047 not installed or wrong owner'; END IF;
 SELECT * INTO STRICT b FROM private.migration_047_reporting;
 IF b.installed_definition IS NULL OR pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM b.installed_definition
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=b.view_oid AND relowner=b.owner_oid
   AND relacl IS NOT DISTINCT FROM b.acl AND reloptions IS NOT DISTINCT FROM b.options) THEN RAISE EXCEPTION '047 rollback view/security drift'; END IF;
 IF jsonb_array_length(b.helpers) IS DISTINCT FROM 2 OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(b.helpers) h LEFT JOIN pg_proc p ON p.oid=(h->>'oid')::OID
  WHERE p.oid IS NULL OR p.oid IS DISTINCT FROM to_regprocedure(h->>'signature')
   OR pg_get_functiondef(p.oid) IS DISTINCT FROM h->>'definition'
   OR p.proowner IS DISTINCT FROM (h->>'owner')::OID
   OR p.proacl::TEXT IS DISTINCT FROM h->>'acl'
   OR to_jsonb(p.proconfig) IS DISTINCT FROM h->'config'
   OR p.prosecdef IS DISTINCT FROM (h->>'security_definer')::BOOLEAN) THEN
  RAISE EXCEPTION '047 rollback helper/security drift'; END IF;
 EXECUTE 'CREATE OR REPLACE VIEW private.reporting_045_facts AS '||b.definition;
 IF pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM b.definition
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=b.view_oid AND relowner=b.owner_oid
   AND relacl IS NOT DISTINCT FROM b.acl AND reloptions IS NOT DISTINCT FROM b.options) THEN RAISE EXCEPTION '047 rollback restoration failed'; END IF;
END; $rollback$;
DROP FUNCTION private.reporting_047_number(TEXT),private.reporting_047_voucher_sign(TEXT);
DROP TABLE private.migration_047_reporting;
COMMIT;
