-- Restore exact pre-042 bodies, volatility and configuration. Retain context/rate/audit data.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $$
DECLARE r RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '042 rollback requires postgres'; END IF;
 IF (SELECT count(*) FROM private.migration_042_functions)<>2 THEN RAISE EXCEPTION '042 backup incomplete'; END IF;
 FOR r IN SELECT * FROM private.migration_042_functions LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
    AND pg_get_userbyid(p.proowner)=r.owner_name AND p.proacl IS NOT DISTINCT FROM r.acl) THEN
   RAISE EXCEPTION '042 owner/ACL changed since migration: %',r.signature; END IF;
  EXECUTE r.definition;
 END LOOP;
END; $$;
DROP FUNCTION public.switch_my_organization_context(UUID);
DROP FUNCTION public.list_my_organization_contexts();
DROP TABLE private.migration_042_functions;
NOTIFY pgrst,'reload schema';
COMMIT;
