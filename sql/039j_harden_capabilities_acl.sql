-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. No SQL executed by agent.
-- Validate eight EFFECTIVE privileges; ACL order, serialization and grantor do not authorize.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_capabilities IN ACCESS EXCLUSIVE MODE;
DO $preflight$
DECLARE v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039j requires postgres'; END IF;
 IF to_regclass('private.migration_039g_create') IS NULL OR to_regclass('private.migration_039h_state') IS NULL
  OR to_regclass('private.migration_039i_function') IS NULL THEN RAISE EXCEPTION '039g/039h/039i required'; END IF;
 IF to_regclass('private.migration_039j_acl') IS NOT NULL THEN RAISE EXCEPTION '039j already installed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass
  AND pg_get_userbyid(relation_row.relowner)='postgres' AND relation_row.relrowsecurity AND NOT relation_row.relforcerowsecurity) THEN
  RAISE EXCEPTION '039j owner/RLS differs'; END IF;
 IF (SELECT count(*) FROM pg_policy WHERE polrelid='public.eco_capabilities'::regclass)<>1
  OR NOT EXISTS(SELECT 1 FROM pg_policy policy_row WHERE policy_row.polrelid='public.eco_capabilities'::regclass
   AND policy_row.polname='authenticated_read_capabilities' AND policy_row.polcmd='r' AND policy_row.polpermissive
   AND policy_row.polroles=ARRAY['authenticated'::regrole::OID]
   AND pg_get_expr(policy_row.polqual,policy_row.polrelid)='(is_active = true)' AND policy_row.polwithcheck IS NULL) THEN
  RAISE EXCEPTION '039j exact SELECT policy differs'; END IF;
 FOR v_role IN SELECT unnest(ARRAY['anon','authenticated','postgres','service_role']) LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,'public.eco_capabilities',v_privilege) IS DISTINCT FROM
   TRUE THEN
   RAISE EXCEPTION '039j prior effective authority differs: role %, privilege %',v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,'public.eco_capabilities',v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039j unreviewed delegation authority: role %, privilege %',v_role,v_privilege; END IF;
 END LOOP;
END LOOP;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_capabilities'::regclass AND attacl IS NOT NULL) THEN
  RAISE EXCEPTION '039j unexpected column ACL requires review'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_capabilities'::regclass
  AND tgname='guard_036_capability' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_capability()'))
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_capabilities'::regclass
  AND tgname='guard_036_capability_truncate' AND tgenabled='O') THEN RAISE EXCEPTION '039j 036 guards must remain active'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039j_acl(id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id),raw_acl ACLITEM[],
 owner_oid OID NOT NULL,rls BOOLEAN NOT NULL,force_rls BOOLEAN NOT NULL,
 policies JSONB NOT NULL,guards JSONB NOT NULL);
ALTER TABLE private.migration_039j_acl ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039j_acl FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039j_acl(id,raw_acl,owner_oid,rls,force_rls,policies,guards)
 SELECT TRUE,relation_row.relacl,relation_row.relowner,relation_row.relrowsecurity,relation_row.relforcerowsecurity,
 (SELECT jsonb_agg(to_jsonb(policy_row) ORDER BY policy_row.oid) FROM pg_policy policy_row
 WHERE policy_row.polrelid='public.eco_capabilities'::regclass),(SELECT jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid)
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid='public.eco_capabilities'::regclass AND NOT trigger_row.tgisinternal) FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities FROM authenticated;
REVOKE ALL ON public.eco_capabilities FROM anon;
DO $verify$
DECLARE v_saved RECORD; v_role TEXT; v_privilege TEXT;
BEGIN
 SELECT * INTO STRICT v_saved FROM private.migration_039j_acl;
 IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR (SELECT jsonb_agg(to_jsonb(policy_row) ORDER BY policy_row.oid) FROM pg_policy policy_row
 WHERE policy_row.polrelid='public.eco_capabilities'::regclass) IS DISTINCT FROM v_saved.policies OR (SELECT jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid)
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid='public.eco_capabilities'::regclass AND NOT trigger_row.tgisinternal) IS DISTINCT FROM v_saved.guards THEN
 RAISE EXCEPTION '039j owner/RLS/policy/guard drift'; END IF;
 FOR v_role IN SELECT unnest(ARRAY['anon','authenticated','postgres','service_role']) LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,'public.eco_capabilities',v_privilege) IS DISTINCT FROM
   (v_role IN ('postgres','service_role') OR (v_role='authenticated' AND v_privilege='SELECT')) THEN
   RAISE EXCEPTION '039j installed effective authority differs: role %, privilege %',v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,'public.eco_capabilities',v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039j unreviewed delegation authority: role %, privilege %',v_role,v_privilege; END IF;
 END LOOP;
END LOOP;
 IF EXISTS(WITH previous_grants AS (
 SELECT grantee,privilege_type,is_grantable FROM aclexplode(v_saved.raw_acl)
 WHERE grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID)), current_grants AS (
 SELECT grants.grantee,grants.privilege_type,grants.is_grantable FROM pg_class relation_row
 CROSS JOIN LATERAL aclexplode(relation_row.relacl) grants WHERE relation_row.oid='public.eco_capabilities'::regclass
 AND grants.grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID))
 (SELECT * FROM previous_grants EXCEPT SELECT * FROM current_grants)
 UNION ALL (SELECT * FROM current_grants EXCEPT SELECT * FROM previous_grants)) THEN
 RAISE EXCEPTION '039j grants of other roles changed'; END IF;
END; $verify$;
COMMIT;
