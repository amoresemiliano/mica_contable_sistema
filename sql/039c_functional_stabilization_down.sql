-- Manual rollback, refuses to discard new user/business data or later changes.
BEGIN;
DO $preflight$
DECLARE r RECORD; cap UUID;
BEGIN
 IF to_regclass('private.migration_039c_functions') IS NULL THEN RAISE EXCEPTION '039c not installed'; END IF;
 IF EXISTS(SELECT 1 FROM private.eco_manual_records) OR EXISTS(SELECT 1 FROM private.eco_mica_invitations) THEN
  RAISE EXCEPTION '039c has business/invitation data: preserve and review explicitly before rollback'; END IF;
 FOR r IN SELECT * FROM private.migration_039c_functions LOOP
  IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM r.installed_definition THEN RAISE EXCEPTION 'Later function drift: %',r.signature; END IF;
 END LOOP;
 SELECT id INTO STRICT cap FROM public.eco_capabilities WHERE code='FISCAL_DOCUMENT_IMPORT'
   AND scope='ORGANIZATION' AND delegation_class='ORGANIZATION_DELEGABLE' AND is_active;
 IF EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides WHERE capability_id=cap)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE capability_id=cap)
  OR EXISTS(SELECT 1 FROM private.eco_platform_org_overrides WHERE capability_id=cap)
  OR EXISTS(SELECT 1 FROM public.eco_role_template_capabilities t WHERE capability_id=cap AND NOT EXISTS(
   SELECT 1 FROM private.migration_039c_grants g WHERE g.relation='public.eco_role_template_capabilities' AND g.key=to_jsonb(t)))
  OR EXISTS(SELECT 1 FROM public.eco_platform_role_org_capabilities t WHERE capability_id=cap AND NOT EXISTS(
   SELECT 1 FROM private.migration_039c_grants g WHERE g.relation='public.eco_platform_role_org_capabilities' AND g.key=to_jsonb(t))) THEN
  RAISE EXCEPTION 'Fiscal capability has later grants/overrides: preserve administrative decisions'; END IF;
END; $preflight$;
DROP FUNCTION public.mica_invitation(TEXT,UUID,JSONB);
DROP FUNCTION public.mica_manual_records(TEXT,UUID,UUID,JSONB);
DROP FUNCTION public.mica_import_file_status(UUID);
DO $restore$
DECLARE r RECORD;
BEGIN
 FOR r IN SELECT * FROM private.migration_039c_functions WHERE definition<>'' LOOP EXECUTE r.definition; END LOOP;
 FOR r IN SELECT * FROM private.migration_039c_grants LOOP
  EXECUTE format('DELETE FROM %s t WHERE to_jsonb(t)=$1',r.relation) USING r.key;
 END LOOP;
 -- Foreign keys deliberately reject rollback after individual grants/overrides.
 DELETE FROM public.eco_capabilities WHERE code='FISCAL_DOCUMENT_IMPORT';
END; $restore$;
DROP FUNCTION private.reuse_039c_file(UUID,TEXT);
DROP TABLE private.eco_mica_invitations;
DROP TABLE private.eco_manual_records;
DROP TABLE private.migration_039c_grants;
DROP TABLE private.migration_039c_functions;
COMMIT;
