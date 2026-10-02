-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Readonly preflight + reviewed policy manifest required.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_role_templates,public.eco_role_template_capabilities,public.eco_platform_role_org_capabilities,public.eco_user_platform_role,public.eco_user_platform_capability_overrides,public.eco_membership_capability_overrides IN ACCESS EXCLUSIVE MODE;
DO $preflight$
DECLARE v_spec RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039k requires postgres'; END IF;
 IF to_regclass('private.migration_039j_acl') IS NULL THEN RAISE EXCEPTION '039j required'; END IF;
 IF to_regclass('private.migration_039k_acl') IS NOT NULL THEN RAISE EXCEPTION '039k already installed'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(ARRAY['public.mica_admin_apply(text,jsonb)','public.mica_admin_read(uuid,text)',
  'public.mica_invitation(text,uuid,jsonb)']) rpc_signature WHERE NOT EXISTS(SELECT 1 FROM pg_proc rpc_row
  WHERE rpc_row.oid=to_regprocedure(rpc_signature) AND rpc_row.prosecdef AND pg_get_userbyid(rpc_row.proowner)='postgres'
  AND rpc_row.proconfig @> ARRAY['search_path=""'])) THEN RAISE EXCEPTION '039k administrative RPC security differs'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner owner_row
 JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.is_active AND template_row.is_active AND template_row.code='VEGEN_PLATFORM_ADMIN')
 OR (SELECT count(*) FROM private.eco_platform_owner)<>1 THEN RAISE EXCEPTION '039k structural root assignment differs'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role assignment_row
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID
 AND assignment_row.is_active AND template_row.is_active AND template_row.code='ADMINISTRACION_OPERATIVA_MICA') THEN
 RAISE EXCEPTION '039k Marianela assignment differs'; END IF;
 FOR v_spec IN SELECT * FROM (VALUES ('eco_role_templates',TRUE,'guard_036_template','[{"name":"authenticated_read_role_templates","check":null,"roles":["authenticated"],"using":"(is_active = true)","command":"r","permissive":true}]'::JSONB),
('eco_role_template_capabilities',TRUE,'guard_036_grant','[{"name":"authenticated_read_role_template_capabilities","check":null,"roles":["authenticated"],"using":"(EXISTS ( SELECT 1\n   FROM eco_role_templates t\n  WHERE ((t.id = eco_role_template_capabilities.role_template_id) AND (t.is_active = true))))","command":"r","permissive":true}]'::JSONB),
('eco_platform_role_org_capabilities',FALSE,'guard_036_grant','[]'::JSONB),
('eco_user_platform_role',FALSE,'guard_036_platform_role','[]'::JSONB),
('eco_user_platform_capability_overrides',FALSE,'guard_036_grant','[]'::JSONB),
('eco_membership_capability_overrides',FALSE,'guard_036_grant','[]'::JSONB)) expected(table_name,keep_select,guard_name,policies) LOOP
  v_relation:=to_regclass('public.'||v_spec.table_name);
  IF v_spec.policies IS NULL THEN RAISE EXCEPTION '039k review LIVE policies and populate manifest: %',v_spec.table_name; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid=v_relation
   AND pg_get_userbyid(relation_row.relowner)='postgres' AND relation_row.relrowsecurity) THEN
   RAISE EXCEPTION '039k missing table or owner/RLS differs: %',v_spec.table_name; END IF;
  IF (SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation) IS DISTINCT FROM v_spec.policies THEN RAISE EXCEPTION '039k reviewed policy set differs: %',v_relation; END IF;
  IF v_spec.keep_select AND NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=v_relation AND polcmd IN('r','*')
   AND ('authenticated'::regrole::OID=ANY(polroles) OR 0=ANY(polroles))) THEN
   RAISE EXCEPTION '039k retained SELECT requires existing read policy: %',v_relation; END IF;
  IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=v_relation AND attacl IS NOT NULL) THEN
   RAISE EXCEPTION '039k unreviewed column ACL: %',v_relation; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=v_relation AND tgname=v_spec.guard_name AND tgenabled='O'
   AND tgfoid=to_regprocedure('private.'||CASE WHEN v_spec.guard_name='guard_036_platform_role'
    THEN 'guard_036_identity' ELSE v_spec.guard_name END||'()'))
   OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=v_relation AND tgname LIKE 'guard_036_%' AND tgenabled<>'O') THEN
   RAISE EXCEPTION '039k guards 036 must remain active: %',v_relation; END IF;
  IF v_spec.table_name='eco_user_platform_role' AND NOT EXISTS(SELECT 1 FROM pg_trigger
   WHERE tgrelid=v_relation AND tgname='guard_036_role_truncate' AND tgenabled='O'
    AND tgfoid=to_regprocedure('private.guard_036_frozen()')) THEN
   RAISE EXCEPTION '039k platform role truncate guard missing'; END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','postgres','service_role'] LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,v_relation,v_privilege) IS DISTINCT FROM TRUE THEN
   RAISE EXCEPTION '039k prior authority differs: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,v_relation,v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039k unexpected delegation authority: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
 END LOOP;
END LOOP;
 END LOOP;
END; $preflight$;
CREATE TABLE private.migration_039k_acl(table_name TEXT PRIMARY KEY,keep_select BOOLEAN NOT NULL,raw_acl ACLITEM[],
 owner_oid OID NOT NULL,rls BOOLEAN NOT NULL,force_rls BOOLEAN NOT NULL,policies JSONB NOT NULL,guards JSONB NOT NULL);
ALTER TABLE private.migration_039k_acl ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039k_acl FROM PUBLIC,anon,authenticated;
DO $harden$
DECLARE v_saved RECORD; v_spec RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 FOR v_spec IN SELECT * FROM (VALUES ('eco_role_templates',TRUE,'guard_036_template','[{"name":"authenticated_read_role_templates","check":null,"roles":["authenticated"],"using":"(is_active = true)","command":"r","permissive":true}]'::JSONB),
('eco_role_template_capabilities',TRUE,'guard_036_grant','[{"name":"authenticated_read_role_template_capabilities","check":null,"roles":["authenticated"],"using":"(EXISTS ( SELECT 1\n   FROM eco_role_templates t\n  WHERE ((t.id = eco_role_template_capabilities.role_template_id) AND (t.is_active = true))))","command":"r","permissive":true}]'::JSONB),
('eco_platform_role_org_capabilities',FALSE,'guard_036_grant','[]'::JSONB),
('eco_user_platform_role',FALSE,'guard_036_platform_role','[]'::JSONB),
('eco_user_platform_capability_overrides',FALSE,'guard_036_grant','[]'::JSONB),
('eco_membership_capability_overrides',FALSE,'guard_036_grant','[]'::JSONB)) expected(table_name,keep_select,guard_name,policies) LOOP
  v_relation:=to_regclass('public.'||v_spec.table_name);
  INSERT INTO private.migration_039k_acl SELECT v_spec.table_name,v_spec.keep_select,relation_row.relacl,
   relation_row.relowner,relation_row.relrowsecurity,relation_row.relforcerowsecurity,(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation),(SELECT COALESCE(jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid),'[]')
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid=v_relation AND NOT trigger_row.tgisinternal)
   FROM pg_class relation_row WHERE relation_row.oid=v_relation;
 END LOOP;
END; $harden$;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_role_templates FROM authenticated;
REVOKE ALL ON public.eco_role_templates FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_role_template_capabilities FROM authenticated;
REVOKE ALL ON public.eco_role_template_capabilities FROM anon;
REVOKE ALL ON public.eco_platform_role_org_capabilities FROM authenticated;
REVOKE ALL ON public.eco_platform_role_org_capabilities FROM anon;
REVOKE ALL ON public.eco_user_platform_role FROM authenticated;
REVOKE ALL ON public.eco_user_platform_role FROM anon;
REVOKE ALL ON public.eco_user_platform_capability_overrides FROM authenticated;
REVOKE ALL ON public.eco_user_platform_capability_overrides FROM anon;
REVOKE ALL ON public.eco_membership_capability_overrides FROM authenticated;
REVOKE ALL ON public.eco_membership_capability_overrides FROM anon;
DO $postcheck$
DECLARE v_saved RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
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
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner owner_row
 JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.is_active AND template_row.is_active AND template_row.code='VEGEN_PLATFORM_ADMIN')
 OR (SELECT count(*) FROM private.eco_platform_owner)<>1 THEN RAISE EXCEPTION '039k structural root assignment differs'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role assignment_row
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID
 AND assignment_row.is_active AND template_row.is_active AND template_row.code='ADMINISTRACION_OPERATIVA_MICA') THEN
 RAISE EXCEPTION '039k Marianela assignment differs'; END IF;
END; $postcheck$;
COMMIT;
