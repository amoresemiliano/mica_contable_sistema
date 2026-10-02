-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restores the exact defective 039h definition.
-- Roll back 039i BEFORE 039h. This deliberately restores the known ambiguity.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $restore$
DECLARE v_saved RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039i DOWN requires postgres'; END IF;
 IF to_regclass('private.migration_039i_function') IS NULL THEN RAISE EXCEPTION '039i not installed'; END IF;
 SELECT * INTO STRICT v_saved FROM private.migration_039i_function;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.installed
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer
  AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='a3fbc3e14522dc603f5ba9010cebd9bf') THEN
  RAISE EXCEPTION '039i DOWN definition/owner/ACL/security drift'; END IF;
 EXECUTE v_saved.definition;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.definition
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer) THEN
  RAISE EXCEPTION '039i DOWN exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039i_function;
COMMIT;
