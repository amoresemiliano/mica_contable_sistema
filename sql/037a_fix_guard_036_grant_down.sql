-- Historical rollback ONLY: restores the known defective definition.
-- Restores 42703 behavior for membership overrides. Do not run as a remedy for that error.
BEGIN;
DO $restore$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_037a_guard_backup') IS NULL THEN
    RAISE EXCEPTION '037a down: missing exact LIVE baseline'; END IF;
  LOCK TABLE public.eco_role_template_capabilities,public.eco_user_platform_capability_overrides,
    public.eco_platform_role_org_capabilities,public.eco_membership_capability_overrides,
    public.eco_member_capability_overrides IN SHARE ROW EXCLUSIVE MODE;
  SELECT * INTO STRICT b FROM private.migration_037a_guard_backup WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('private.guard_036_grant()')
    AND oid=b.function_oid AND pg_get_functiondef(oid)=b.installed_definition
    AND pg_get_userbyid(proowner)=b.owner_name AND proacl IS NOT DISTINCT FROM b.acl) THEN
    RAISE EXCEPTION '037a down: later function/owner/ACL drift; refusing overwrite'; END IF;
  EXECUTE b.definition;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=b.function_oid AND pg_get_functiondef(oid)=b.definition
    AND pg_get_userbyid(proowner)=b.owner_name AND proacl IS NOT DISTINCT FROM b.acl) THEN
    RAISE EXCEPTION '037a down: exact restoration failed'; END IF;
END;
$restore$;
DROP TABLE private.migration_037a_guard_backup;
COMMIT;
