-- 038 rollback: preserve business rows, profiles, presets/grants and audit history.
-- Removes the administration API; it does NOT undo decisions made through that API.
BEGIN;
DO $preflight$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_038_backup') IS NULL THEN RAISE EXCEPTION '038 baseline missing'; END IF;
  FOR b IN SELECT * FROM private.migration_038_backup LOOP
    IF to_regprocedure(b.signature) IS NULL OR pg_get_functiondef(to_regprocedure(b.signature))<>b.installed_definition
      OR pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=to_regprocedure(b.signature)))<>b.owner_name
      OR (SELECT proacl FROM pg_proc WHERE oid=to_regprocedure(b.signature)) IS DISTINCT FROM b.installed_acl THEN
      RAISE EXCEPTION '038 later drift: %',b.signature; END IF;
  END LOOP;
END; $preflight$;
DO $restore$
DECLARE b RECORD; a RECORD; who TEXT;
BEGIN
  SELECT * INTO STRICT b FROM private.migration_038_backup WHERE signature='public.handle_new_user()';
  EXECUTE b.definition;
  FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(
    (SELECT proacl FROM pg_proc WHERE oid='public.handle_new_user()'::regprocedure),
    acldefault('f',(SELECT proowner FROM pg_proc WHERE oid='public.handle_new_user()'::regprocedure))))
    WHERE grantee<>(SELECT proowner FROM pg_proc WHERE oid='public.handle_new_user()'::regprocedure) LOOP
    who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
    EXECUTE format('REVOKE ALL ON FUNCTION public.handle_new_user() FROM %s',who);
  END LOOP;
  FOR a IN SELECT * FROM aclexplode(COALESCE(b.acl,acldefault('f',(SELECT oid FROM pg_roles WHERE rolname=b.owner_name)))) LOOP
    who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
    EXECUTE format('GRANT %s ON FUNCTION public.handle_new_user() TO %s%s',a.privilege_type,who,
      CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
END; $restore$;
DROP FUNCTION public.mica_admin_read(UUID,TEXT);
DROP FUNCTION public.mica_admin_apply(TEXT,JSONB);
DROP FUNCTION private.admin_038_cap(TEXT,TEXT,UUID);
DROP FUNCTION private.admin_038_target(UUID);
DROP FUNCTION private.admin_038_authorize(UUID,TEXT,TEXT);
DROP FUNCTION private.admin_038_actor();
DROP TABLE private.eco_mica_pending_profiles;
DROP TABLE private.eco_mica_presets;
DROP TABLE private.migration_038_backup;
COMMIT;
