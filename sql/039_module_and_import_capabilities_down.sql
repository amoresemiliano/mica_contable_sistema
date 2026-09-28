-- Historical rollback: restores prior RPC definitions and effective ACLs.
BEGIN;
DO $restore$
DECLARE b RECORD; a RECORD; who TEXT;
BEGIN
  IF to_regclass('private.migration_039_functions') IS NULL THEN RAISE EXCEPTION '039 backup missing'; END IF;
  FOR b IN SELECT * FROM private.migration_039_functions LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(b.signature) AND pg_get_functiondef(oid)=b.installed_definition
      AND pg_get_userbyid(proowner)=b.owner_name AND proacl IS NOT DISTINCT FROM b.installed_acl) THEN
      RAISE EXCEPTION '039 later drift: %',b.signature; END IF;
  END LOOP;
  FOR b IN SELECT * FROM private.migration_039_functions LOOP
    EXECUTE b.definition;
    FOR a IN SELECT DISTINCT grantee FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner)))
      WHERE p.oid=to_regprocedure(b.signature) AND grantee<>p.proowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',b.signature,who);
    END LOOP;
    FOR a IN SELECT * FROM aclexplode(COALESCE(b.acl,acldefault('f',(SELECT oid FROM pg_roles WHERE rolname=b.owner_name)))) LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',a.privilege_type,b.signature,who,CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
    END LOOP;
  END LOOP;
END; $restore$;
DROP POLICY guard_039_read ON public.eco_normalized_records;
DROP POLICY guard_039_read ON public.eco_financial_movements;
DROP POLICY guard_039_read ON public.eco_source_imports;
DROP POLICY guard_039_read ON public.eco_source_files;
DROP POLICY guard_039_read ON public.eco_import_rows;
DROP POLICY guard_039_read ON public.eco_import_issues;
DROP POLICY guard_039_read ON public.eco_org_tax_categories;
DROP POLICY guard_039_read ON public.eco_org_economic_activities;
DROP POLICY guard_039_read ON public.eco_org_activity_iibb_rates;
DROP POLICY guard_039_storage_read ON storage.objects;
DROP POLICY guard_039_storage_write ON storage.objects;
DROP POLICY guard_039_storage_delete ON storage.objects;
DROP FUNCTION public.mica_storage_import_allowed(TEXT,TEXT);
DROP FUNCTION private.require_039_batch(UUID,TEXT[]);
DROP FUNCTION private.require_039_import(TEXT,TEXT);
DROP FUNCTION private.require_039_action(TEXT);
DROP TABLE private.migration_039_functions;
COMMIT;
