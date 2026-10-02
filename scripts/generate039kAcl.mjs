// Offline artifact preparation. No database connection or SQL execution.
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8').replaceAll('\r','');
export const tables=['eco_role_templates','eco_role_template_capabilities','eco_platform_role_org_capabilities',
 'eco_user_platform_role','eco_user_platform_capability_overrides','eco_membership_capability_overrides'];
const manifest=JSON.parse(read('sql/039k_policy_manifest.json'));
if(Object.keys(manifest).sort().join()!==[...tables].sort().join()) throw new Error('Policy manifest table set differs');
for(const policies of Object.values(manifest)) if(policies!==null&&!Array.isArray(policies)) throw new Error('Policy manifest entries must be arrays or null');
const q=s=>"'"+s.replaceAll("'","''")+"'";
const privileges="ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']";
const specs=tables.map((t,i)=>`(${q(t)},${i<2?'TRUE':'FALSE'},${q(i===0?'guard_036_template':i===3?'guard_036_platform_role':'guard_036_grant')},${manifest[t]===null?'NULL::JSONB':q(JSON.stringify(manifest[t]))+'::JSONB'})`).join(',\n');
const policySnapshot=`(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation)`;
const guardSnapshot=`(SELECT COALESCE(jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid),'[]')
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid=v_relation AND NOT trigger_row.tgisinternal)`;
const authority=(installed)=>`FOREACH v_role IN ARRAY ARRAY['anon','authenticated','postgres','service_role'] LOOP
 FOREACH v_privilege IN ARRAY ${privileges} LOOP
  IF has_table_privilege(v_role,v_relation,v_privilege) IS DISTINCT FROM ${installed?"(v_role IN ('postgres','service_role') OR (v_role='authenticated' AND v_saved.keep_select AND v_privilege='SELECT'))":'TRUE'} THEN
   RAISE EXCEPTION '039k ${installed?'installed':'prior'} authority differs: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,v_relation,v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039k unexpected delegation authority: table %, role %, privilege %',v_relation,v_role,v_privilege; END IF;
 END LOOP;
END LOOP;`;
const identities=`IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner owner_row
 JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.is_active AND template_row.is_active AND template_row.code='VEGEN_PLATFORM_ADMIN')
 OR (SELECT count(*) FROM private.eco_platform_owner)<>1 THEN RAISE EXCEPTION '039k structural root assignment differs'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role assignment_row
 JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
 WHERE assignment_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID
 AND assignment_row.is_active AND template_row.is_active AND template_row.code='ADMINISTRACION_OPERATIVA_MICA') THEN
 RAISE EXCEPTION '039k Marianela assignment differs'; END IF;`;
const metadata=`IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid=v_relation
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR ${policySnapshot} IS DISTINCT FROM v_saved.policies
 OR ${guardSnapshot} IS DISTINCT FROM v_saved.guards THEN RAISE EXCEPTION '039k owner/RLS/policy/guard drift: %',v_relation; END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=v_relation AND attacl IS NOT NULL) THEN
 RAISE EXCEPTION '039k column authority drift: %',v_relation; END IF;`;
const others=`IF EXISTS(WITH previous_grants AS (
 SELECT grantee,privilege_type,is_grantable FROM aclexplode(v_saved.raw_acl)
 WHERE grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID)), current_grants AS (
 SELECT grants.grantee,grants.privilege_type,grants.is_grantable FROM pg_class relation_row
 CROSS JOIN LATERAL aclexplode(relation_row.relacl) grants WHERE relation_row.oid=v_relation
 AND grants.grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID))
 (SELECT * FROM previous_grants EXCEPT SELECT * FROM current_grants)
 UNION ALL (SELECT * FROM current_grants EXCEPT SELECT * FROM previous_grants)) THEN
 RAISE EXCEPTION '039k grants of other roles changed: %',v_relation; END IF;`;
const lock=`LOCK TABLE ${tables.map(t=>'public.'+t).join(',')} IN ACCESS EXCLUSIVE MODE;`;
const up=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Readonly preflight + reviewed policy manifest required.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
${lock}
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
 ${identities}
 FOR v_spec IN SELECT * FROM (VALUES ${specs}) expected(table_name,keep_select,guard_name,policies) LOOP
  v_relation:=to_regclass('public.'||v_spec.table_name);
  IF v_spec.policies IS NULL THEN RAISE EXCEPTION '039k review LIVE policies and populate manifest: %',v_spec.table_name; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid=v_relation
   AND pg_get_userbyid(relation_row.relowner)='postgres' AND relation_row.relrowsecurity) THEN
   RAISE EXCEPTION '039k missing table or owner/RLS differs: %',v_spec.table_name; END IF;
  IF ${policySnapshot} IS DISTINCT FROM v_spec.policies THEN RAISE EXCEPTION '039k reviewed policy set differs: %',v_relation; END IF;
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
  ${authority(false)}
 END LOOP;
END; $preflight$;
CREATE TABLE private.migration_039k_acl(table_name TEXT PRIMARY KEY,keep_select BOOLEAN NOT NULL,raw_acl ACLITEM[],
 owner_oid OID NOT NULL,rls BOOLEAN NOT NULL,force_rls BOOLEAN NOT NULL,policies JSONB NOT NULL,guards JSONB NOT NULL);
ALTER TABLE private.migration_039k_acl ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039k_acl FROM PUBLIC,anon,authenticated;
DO $harden$
DECLARE v_saved RECORD; v_spec RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 FOR v_spec IN SELECT * FROM (VALUES ${specs}) expected(table_name,keep_select,guard_name,policies) LOOP
  v_relation:=to_regclass('public.'||v_spec.table_name);
  INSERT INTO private.migration_039k_acl SELECT v_spec.table_name,v_spec.keep_select,relation_row.relacl,
   relation_row.relowner,relation_row.relrowsecurity,relation_row.relforcerowsecurity,${policySnapshot},${guardSnapshot}
   FROM pg_class relation_row WHERE relation_row.oid=v_relation;
 END LOOP;
END; $harden$;
${tables.map((t,i)=>`REVOKE ${i<2?'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN':'ALL'} ON public.${t} FROM authenticated;
REVOKE ALL ON public.${t} FROM anon;`).join('\n')}
DO $postcheck$
DECLARE v_saved RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  ${authority(true)}
  ${metadata}
  ${others}
 END LOOP;
 ${identities}
END; $postcheck$;
COMMIT;
`;
const down=`-- MICA ourzapkjykzlwsjunzmd. Prepared only. Roll back 039k before 039j.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
${lock}
DO $restore$
DECLARE v_saved RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039k DOWN requires postgres'; END IF;
 IF (SELECT count(*) FROM private.migration_039k_acl)<>6 THEN RAISE EXCEPTION '039k backup incomplete'; END IF;
 -- Validate all six before restoring any authority.
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  ${authority(true)}
  ${metadata}
  ${others}
 END LOOP;
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON %s TO anon, authenticated',v_relation);
  ${authority(false)}
  ${metadata}
  ${others}
 END LOOP;
END; $restore$;
DROP TABLE private.migration_039k_acl;
COMMIT;
`;
const readonly=`-- MICA ourzapkjykzlwsjunzmd. SELECT ONLY; not executed by agent.
-- Copy each reviewed policies array into 039k_policy_manifest.json and regenerate offline.
SELECT v_relation::REGCLASS AS relation,${policySnapshot} AS policies
FROM unnest(ARRAY[${tables.map(t=>q('public.'+t)+'::REGCLASS').join(',')}]) v_relation;
SELECT relation_row.oid::REGCLASS,pg_get_userbyid(relation_row.relowner),relation_row.relrowsecurity,relation_row.relforcerowsecurity
FROM pg_class relation_row WHERE relation_row.oid IN(${tables.map(t=>q('public.'+t)+'::REGCLASS').join(',')});
SELECT target.table_name,actor.role_name,privilege.privilege_name,
 has_table_privilege(actor.role_name,'public.'||target.table_name,privilege.privilege_name) AS effective_authority
FROM unnest(ARRAY[${tables.map(q).join(',')}]) target(table_name)
CROSS JOIN unnest(ARRAY['anon','authenticated','service_role','postgres']) actor(role_name)
CROSS JOIN unnest(${privileges}) privilege(privilege_name);
SELECT tgrelid::REGCLASS,tgname,tgenabled,pg_get_triggerdef(oid) FROM pg_trigger
WHERE tgrelid IN(${tables.map(t=>q('public.'+t)+'::REGCLASS').join(',')}) AND NOT tgisinternal;
SELECT to_jsonb(owner_row) AS structural_owner,template_row.code FROM private.eco_platform_owner owner_row
JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id
JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id;
SELECT to_jsonb(assignment_row),template_row.code FROM public.eco_user_platform_role assignment_row
JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
WHERE assignment_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID;
`;
const harness=`-- MICA ourzapkjykzlwsjunzmd. Prepared only. After 039k, all fixtures roll back.
BEGIN;
DO $test$
DECLARE v_saved RECORD; v_relation REGCLASS; v_role TEXT; v_privilege TEXT; v_column TEXT;
 v_root_auth UUID; v_root_preset UUID; v_new_preset UUID;
BEGIN
 ${identities}
 FOR v_saved IN SELECT * FROM private.migration_039k_acl LOOP
  v_relation:=to_regclass('public.'||v_saved.table_name);
  ${authority(true)}
  ${metadata}
  ${others}
  SELECT attname INTO STRICT v_column FROM pg_attribute WHERE attrelid=v_relation AND attnum>0 AND NOT attisdropped ORDER BY attnum LIMIT 1;
  FOREACH v_role IN ARRAY ARRAY['authenticated','anon'] LOOP
   EXECUTE format('SET LOCAL ROLE %I',v_role);
   BEGIN
    EXECUTE format('UPDATE %s SET %I=%I WHERE FALSE',v_relation,v_column,v_column);
    RAISE EXCEPTION 'Direct UPDATE accepted: % / %',v_relation,v_role;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN
    EXECUTE format('INSERT INTO %s DEFAULT VALUES',v_relation);
    RAISE EXCEPTION 'Direct INSERT accepted: % / %',v_relation,v_role;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN
    EXECUTE format('DELETE FROM %s WHERE FALSE',v_relation);
    RAISE EXCEPTION 'Direct DELETE accepted: % / %',v_relation,v_role;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   BEGIN
    EXECUTE format('TRUNCATE %s',v_relation);
    RAISE EXCEPTION 'Direct TRUNCATE accepted: % / %',v_relation,v_role;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   IF v_role='authenticated' AND v_saved.keep_select THEN EXECUTE format('SELECT count(*) FROM %s',v_relation);
   ELSE BEGIN
    EXECUTE format('SELECT count(*) FROM %s',v_relation);
    RAISE EXCEPTION 'Direct SELECT accepted: % / %',v_relation,v_role;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END; END IF;
   RESET ROLE;
  END LOOP;
 END LOOP;
 SELECT owner_row.auth_user_id,assignment_row.role_template_id INTO STRICT v_root_auth,v_root_preset
 FROM private.eco_platform_owner owner_row JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id;
 SET LOCAL ROLE authenticated;
 BEGIN
  DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=v_root_preset;
  RAISE EXCEPTION 'Root grants DELETE did not raise 42501';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.sub',v_root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_root_auth,'role','authenticated')::TEXT,TRUE);
 SET LOCAL ROLE authenticated;
 v_new_preset:=public.mica_admin_apply('preset',jsonb_build_object('name','039k root fixture','scope','ORGANIZATION',
  'capabilities',jsonb_build_array('RECORD_VIEW'),'bridge','[]'::JSONB));
 PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',v_new_preset,'name','039k edited fixture','scope','ORGANIZATION',
  'expected_recipients',0,'capabilities',jsonb_build_array('RECORD_VIEW'),'bridge','[]'::JSONB));
 RESET ROLE;
END; $test$;
SAVEPOINT prior_harnesses;
${read('tests/db/039j_harden_capabilities_acl.sql').replace(/^BEGIN;\n/m,'').replace(/^ROLLBACK;\s*$/m,'')}
ROLLBACK TO SAVEPOINT prior_harnesses;
SAVEPOINT down_check;
${down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,'')}
ROLLBACK TO SAVEPOINT down_check;
ROLLBACK;
`;
for(const [path,text] of Object.entries({
 'sql/039k_harden_structural_acl.sql':up,'sql/039k_harden_structural_acl_down.sql':down,
 'sql/039k_preflight_readonly.sql':readonly,'tests/db/039k_harden_structural_acl.sql':harness
})) {
 if(process.argv.includes('--check')) { if(read(path)!==text) throw new Error('Artifact differs: '+path); }
 else fs.writeFileSync(path,text);
}
console.log('039k prepared offline; policies '+(Object.values(manifest).some(p=>p===null)?'await LIVE review':'populated')+'. No SQL executed.');
