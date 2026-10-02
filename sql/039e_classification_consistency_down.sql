-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Preserve all classification data.
BEGIN;
DO $restore$
DECLARE v_saved RECORD;
BEGIN
  IF to_regclass('private.migration_039e_functions') IS NULL THEN RAISE EXCEPTION '039e not installed'; END IF;
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    IF pg_get_functiondef(to_regprocedure(v_saved.signature)) IS DISTINCT FROM v_saved.installed_definition
      OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
        AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e later definition/owner/ACL drift: %',v_saved.signature;
    END IF;
  END LOOP;
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    EXECUTE v_saved.definition;
    IF pg_get_functiondef(to_regprocedure(v_saved.signature)) IS DISTINCT FROM v_saved.definition
      OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
        AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e restoration differs: %',v_saved.signature;
    END IF;
  END LOOP;
END; $restore$;
DROP TABLE private.migration_039e_functions;
COMMIT;
