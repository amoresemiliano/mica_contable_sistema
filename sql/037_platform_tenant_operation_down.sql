-- Manual rollback only; no SQL is executed by generation or Jest.
BEGIN;
DO $restore$
DECLARE b RECORD;
BEGIN
  -- Refuse to delete scopes/overrides provisioned later by 038 or an administrator.
  LOCK TABLE private.eco_platform_org_scopes,private.eco_platform_org_overrides IN ACCESS EXCLUSIVE MODE;
  IF EXISTS (SELECT 1 FROM private.eco_platform_org_scopes) OR EXISTS (SELECT 1 FROM private.eco_platform_org_overrides) THEN
    RAISE EXCEPTION '037 down: provisioned scope/override data exists; preserve and review before rollback'; END IF;
  IF (SELECT count(*) FROM private.migration_037_functions)<>9 THEN RAISE EXCEPTION '037 down: incomplete baseline'; END IF;
  FOR b IN SELECT * FROM private.migration_037_functions LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(b.signature)
      AND pg_get_functiondef(oid)=b.installed_definition AND pg_get_userbyid(proowner)=b.owner_name
      AND proacl IS NOT DISTINCT FROM b.acl) THEN RAISE EXCEPTION '037 down: function drift %',b.signature; END IF;
  END LOOP;
  FOR b IN SELECT * FROM private.migration_037_functions LOOP
    EXECUTE b.definition;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(b.signature)
      AND pg_get_functiondef(oid)=b.definition AND pg_get_userbyid(proowner)=b.owner_name
      AND proacl IS NOT DISTINCT FROM b.acl) THEN RAISE EXCEPTION '037 down: restoration mismatch %',b.signature; END IF;
  END LOOP;
END;
$restore$;
DROP FUNCTION public.can_operate_mica_org(UUID,TEXT);
DROP FUNCTION private.can_operate_mica_org(UUID,TEXT);
DROP FUNCTION private.platform_org_in_scope(UUID);
DROP FUNCTION private.has_mica_platform_role();
DROP TRIGGER guard_037_platform_override ON private.eco_platform_org_overrides;
DROP FUNCTION private.guard_037_platform_override();
DROP FUNCTION private.mica_capability_allowed(TEXT,TEXT);
DROP TABLE private.eco_platform_org_overrides;
DROP TABLE private.eco_platform_org_scopes;
DROP TABLE private.migration_037_functions;
COMMIT;
