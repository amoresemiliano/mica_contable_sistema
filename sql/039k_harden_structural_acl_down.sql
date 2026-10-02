-- MICA ourzapkjykzlwsjunzmd. Prepared only. Roll back 039k before 039j.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_role_templates,public.eco_role_template_capabilities,public.eco_platform_role_org_capabilities,public.eco_user_platform_role,public.eco_user_platform_capability_overrides,public.eco_membership_capability_overrides IN ACCESS EXCLUSIVE MODE;
DO $restore$
DECLARE v_saved RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039k DOWN requires postgres'; END IF;
 IF (SELECT count(*) FROM private.migration_039k_acl)<>6 THEN RAISE EXCEPTION '039k backup incomplete'; END IF;
 -- Validate all six before restoring any authority.
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','postgres','service_role'] LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,v_relation,v_privilege) IS DISTINCT FROM (v_role IN ('postgres','service_role') OR (v_role='authenticated' AND v_saved.keep_select AND v_privilege='SELECT')) THEN
   RAISE EXCEPTION '039k installed authority differs: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,v_relation,v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039k unexpected delegation authority: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
 END LOOP;
END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid=v_relation
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR (SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation) IS DISTINCT FROM v_saved.policies
 OR (SELECT COALESCE(jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid),'[]')
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid=v_relation AND NOT trigger_row.tgisinternal) IS DISTINCT FROM v_saved.guards THEN RAISE EXCEPTION '039k owner/RLS/policy/guard drift: %',v_relation; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=v_relation AND attacl IS NOT NULL) THEN
 RAISE EXCEPTION '039k column authority drift: %',v_relation; END IF;
  IF EXISTS(WITH previous_grants AS (
 SELECT grantee,privilege_type,is_grantable FROM aclexplode(v_saved.raw_acl)
 WHERE grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID)), current_grants AS (
 SELECT grants.grantee,grants.privilege_type,grants.is_grantable FROM pg_class relation_row
 CROSS JOIN LATERAL aclexplode(relation_row.relacl) grants WHERE relation_row.oid=v_relation
 AND grants.grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID))
 (SELECT * FROM previous_grants EXCEPT SELECT * FROM current_grants)
 UNION ALL (SELECT * FROM current_grants EXCEPT SELECT * FROM previous_grants)) THEN
 RAISE EXCEPTION '039k grants of other roles changed: %',v_relation; END IF;
 END LOOP;
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON %s TO anon, authenticated',v_relation);
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','postgres','service_role'] LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,v_relation,v_privilege) IS DISTINCT FROM TRUE THEN
   RAISE EXCEPTION '039k prior authority differs: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,v_relation,v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039k unexpected delegation authority: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
 END LOOP;
END LOOP;
  IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid=v_relation
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR (SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation) IS DISTINCT FROM v_saved.policies
 OR (SELECT COALESCE(jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid),'[]')
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid=v_relation AND NOT trigger_row.tgisinternal) IS DISTINCT FROM v_saved.guards THEN RAISE EXCEPTION '039k owner/RLS/policy/guard drift: %',v_relation; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=v_relation AND attacl IS NOT NULL) THEN
 RAISE EXCEPTION '039k column authority drift: %',v_relation; END IF;
  IF EXISTS(WITH previous_grants AS (
 SELECT grantee,privilege_type,is_grantable FROM aclexplode(v_saved.raw_acl)
 WHERE grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID)), current_grants AS (
 SELECT grants.grantee,grants.privilege_type,grants.is_grantable FROM pg_class relation_row
 CROSS JOIN LATERAL aclexplode(relation_row.relacl) grants WHERE relation_row.oid=v_relation
 AND grants.grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID))
 (SELECT * FROM previous_grants EXCEPT SELECT * FROM current_grants)
 UNION ALL (SELECT * FROM current_grants EXCEPT SELECT * FROM previous_grants)) THEN
 RAISE EXCEPTION '039k grants of other roles changed: %',v_relation; END IF;
 END LOOP;
END; $restore$;
DROP TABLE private.migration_039k_acl;
COMMIT;
