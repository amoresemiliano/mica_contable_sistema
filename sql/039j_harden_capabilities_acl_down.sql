-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restore previous broad ACL exactly, before rolling back 039i.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_capabilities IN ACCESS EXCLUSIVE MODE;
DO $restore$
DECLARE v_saved RECORD; v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039j DOWN requires postgres'; END IF;
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
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_capabilities'::regclass AND attacl IS NOT NULL) THEN
  RAISE EXCEPTION '039j DOWN column ACL drift; preserve later decisions'; END IF;
 -- Restore the observed effective privilege set, not ACL serialization or grantor ordering.
 GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities TO anon, authenticated;
 FOR v_role IN SELECT unnest(ARRAY['anon','authenticated','postgres','service_role']) LOOP
 FOREACH v_privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
  IF has_table_privilege(v_role,'public.eco_capabilities',v_privilege) IS DISTINCT FROM
   TRUE THEN
   RAISE EXCEPTION '039j prior effective authority differs: role %, privilege %',v_role,v_privilege; END IF;
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
 IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR (SELECT jsonb_agg(to_jsonb(policy_row) ORDER BY policy_row.oid) FROM pg_policy policy_row
 WHERE policy_row.polrelid='public.eco_capabilities'::regclass) IS DISTINCT FROM v_saved.policies OR (SELECT jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid)
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid='public.eco_capabilities'::regclass AND NOT trigger_row.tgisinternal) IS DISTINCT FROM v_saved.guards THEN
 RAISE EXCEPTION '039j owner/RLS/policy/guard drift'; END IF;
END; $restore$;
DROP TABLE private.migration_039j_acl;
COMMIT;
