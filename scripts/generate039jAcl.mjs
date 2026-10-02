// Offline SQL preparation only. No database connection or SQL execution.
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8').replaceAll('\r','');
const privileges="ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']";
const authority=installed=>`FOR v_role IN SELECT unnest(ARRAY['anon','authenticated','postgres','service_role']) LOOP
 FOREACH v_privilege IN ARRAY ${privileges} LOOP
  IF has_table_privilege(v_role,'public.eco_capabilities',v_privilege) IS DISTINCT FROM
   ${installed?"(v_role IN ('postgres','service_role') OR (v_role='authenticated' AND v_privilege='SELECT'))":'TRUE'} THEN
   RAISE EXCEPTION '039j ${installed?'installed':'prior'} effective authority differs: role %, privilege %',v_role,v_privilege; END IF;
  IF v_role IN ('anon','authenticated') AND has_table_privilege(v_role,'public.eco_capabilities',v_privilege||' WITH GRANT OPTION') THEN
   RAISE EXCEPTION '039j unreviewed delegation authority: role %, privilege %',v_role,v_privilege; END IF;
 END LOOP;
END LOOP;`;
const otherGrants=`IF EXISTS(WITH previous_grants AS (
 SELECT grantee,privilege_type,is_grantable FROM aclexplode(v_saved.raw_acl)
 WHERE grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID)), current_grants AS (
 SELECT grants.grantee,grants.privilege_type,grants.is_grantable FROM pg_class relation_row
 CROSS JOIN LATERAL aclexplode(relation_row.relacl) grants WHERE relation_row.oid='public.eco_capabilities'::regclass
 AND grants.grantee NOT IN('anon'::regrole::OID,'authenticated'::regrole::OID))
 (SELECT * FROM previous_grants EXCEPT SELECT * FROM current_grants)
 UNION ALL (SELECT * FROM current_grants EXCEPT SELECT * FROM previous_grants)) THEN
 RAISE EXCEPTION '039j grants of other roles changed'; END IF;`;
const policies=`(SELECT jsonb_agg(to_jsonb(policy_row) ORDER BY policy_row.oid) FROM pg_policy policy_row
 WHERE policy_row.polrelid='public.eco_capabilities'::regclass)`;
const guards=`(SELECT jsonb_agg(jsonb_build_object('trigger',to_jsonb(trigger_row),'definition',pg_get_functiondef(trigger_row.tgfoid)) ORDER BY trigger_row.oid)
 FROM pg_trigger trigger_row WHERE trigger_row.tgrelid='public.eco_capabilities'::regclass AND NOT trigger_row.tgisinternal)`;
const preserved=`IF NOT EXISTS(SELECT 1 FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass
 AND relation_row.relowner=v_saved.owner_oid AND relation_row.relrowsecurity=v_saved.rls
 AND relation_row.relforcerowsecurity=v_saved.force_rls)
 OR ${policies} IS DISTINCT FROM v_saved.policies OR ${guards} IS DISTINCT FROM v_saved.guards THEN
 RAISE EXCEPTION '039j owner/RLS/policy/guard drift'; END IF;`;
const up=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. No SQL executed by agent.
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
 ${authority(false)}
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
 ${policies},${guards} FROM pg_class relation_row WHERE relation_row.oid='public.eco_capabilities'::regclass;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities FROM authenticated;
REVOKE ALL ON public.eco_capabilities FROM anon;
DO $verify$
DECLARE v_saved RECORD; v_role TEXT; v_privilege TEXT;
BEGIN
 SELECT * INTO STRICT v_saved FROM private.migration_039j_acl;
 ${preserved}
 ${authority(true)}
 ${otherGrants}
END; $verify$;
COMMIT;
`;
const down=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restore previous broad ACL exactly, before rolling back 039i.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_capabilities IN ACCESS EXCLUSIVE MODE;
DO $restore$
DECLARE v_saved RECORD; v_role TEXT; v_privilege TEXT;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039j DOWN requires postgres'; END IF;
 SELECT * INTO STRICT v_saved FROM private.migration_039j_acl;
 ${preserved}
 ${authority(true)}
 ${otherGrants}
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_capabilities'::regclass AND attacl IS NOT NULL) THEN
  RAISE EXCEPTION '039j DOWN column ACL drift; preserve later decisions'; END IF;
 -- Restore the observed effective privilege set, not ACL serialization or grantor ordering.
 GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities TO anon, authenticated;
 ${authority(false)}
 ${otherGrants}
 ${preserved}
END; $restore$;
DROP TABLE private.migration_039j_acl;
COMMIT;
`;
// Historical files remain immutable. Adapt their checks in the combined 039j harness only.
let operationalHarness=read('tests/db/039i_fix_mica_admin_apply_ambiguity.sql').replace(/^BEGIN;\n/m,'').replace(/^ROLLBACK;\s*$/m,'');
operationalHarness=operationalHarness.replace('v_scope RECORD;','v_scope RECORD; v_deleted_rows BIGINT;');
for(const [statement,label] of [
 ['DELETE FROM private.eco_platform_owner WHERE user_profile_id=root_id;','Structural owner deletion allowed'],
 ['DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=root_preset;','Root grants deletion allowed']
]) {
 const before=`${statement}\n  RAISE EXCEPTION '${label}'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;`;
 if(!operationalHarness.includes(before)) throw new Error('Historical mutation check differs: '+label);
 operationalHarness=operationalHarness.replace(before,`${statement}
  GET DIAGNOSTICS v_deleted_rows = ROW_COUNT;
  IF v_deleted_rows<>0 THEN RAISE EXCEPTION '${label}'; END IF;
  RAISE NOTICE '${label}: SQL accepted, zero rows changed; review structural ACL separately';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE '${label}: blocked by SQL authority/guard'; END;`);
}
// Function ACL checks inherited from 039i also compare semantic sets, not array order.
for(const saved of ['saved_function','v_saved']) {
 const expected=`(CASE WHEN ${saved}.acl IS NULL OR ${saved}.acl='null'::JSONB THEN acldefault('f',proc_row.proowner)
    ELSE ARRAY(SELECT acl_entry::ACLITEM FROM jsonb_array_elements_text(${saved}.acl) acl_entry) END)`;
 const actual="COALESCE(proc_row.proacl,acldefault('f',proc_row.proowner))";
 const fields='grantor,grantee,privilege_type,is_grantable';
 const semantic=`NOT EXISTS((SELECT ${fields} FROM aclexplode(${actual}) EXCEPT SELECT ${fields} FROM aclexplode(${expected}))
   UNION ALL (SELECT ${fields} FROM aclexplode(${expected}) EXCEPT SELECT ${fields} FROM aclexplode(${actual})))`;
 operationalHarness=operationalHarness.replaceAll(`to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM ${saved}.acl`,semantic);
}
const harness=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY, manually AFTER 039j; no agent execution.
-- SQL authority assertions precede DML checks; zero affected rows is NOT accepted as denial.
BEGIN;
DO $test_acl$
DECLARE v_saved RECORD; v_role TEXT; v_privilege TEXT;
BEGIN
 SELECT * INTO STRICT v_saved FROM private.migration_039j_acl;
 ${preserved}
 ${authority(true)}
 ${otherGrants}
 SET LOCAL ROLE authenticated;
 PERFORM count(*) FROM public.eco_capabilities;
 IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE NOT is_active) THEN RAISE EXCEPTION 'SELECT policy regressed'; END IF;
 BEGIN
  UPDATE public.eco_capabilities SET description=description WHERE FALSE;
  RAISE EXCEPTION 'UPDATE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.eco_capabilities DEFAULT VALUES;
  RAISE EXCEPTION 'INSERT returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM public.eco_capabilities WHERE FALSE;
  RAISE EXCEPTION 'DELETE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  TRUNCATE public.eco_capabilities;
  RAISE EXCEPTION 'TRUNCATE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 SET LOCAL ROLE anon;
 BEGIN
  PERFORM count(*) FROM public.eco_capabilities;
  RAISE EXCEPTION 'Anon SELECT returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE public.eco_capabilities SET description=description WHERE FALSE;
  RAISE EXCEPTION 'Anon UPDATE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.eco_capabilities DEFAULT VALUES;
  RAISE EXCEPTION 'Anon INSERT returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM public.eco_capabilities WHERE FALSE;
  RAISE EXCEPTION 'Anon DELETE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  TRUNCATE public.eco_capabilities;
  RAISE EXCEPTION 'Anon TRUNCATE returned without permission denied';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 SET LOCAL ROLE service_role;
 PERFORM count(*) FROM public.eco_capabilities;
 RESET ROLE;
 PERFORM count(*) FROM public.eco_capabilities;
END; $test_acl$;
-- Execute 039i/039h/039g logic: semantic function ACL checks; non-capability tables test mutation separately.
SAVEPOINT operational_harnesses;
${operationalHarness}
ROLLBACK TO SAVEPOINT operational_harnesses;
-- Verify exact DOWN inside a savepoint; restore hardened ACL before final rollback.
SAVEPOINT acl_down;
${down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,'')}
ROLLBACK TO SAVEPOINT acl_down;
ROLLBACK;
`;
for(const [path,content] of Object.entries({
 'sql/039j_harden_capabilities_acl.sql':up,
 'sql/039j_harden_capabilities_acl_down.sql':down,
 'tests/db/039j_harden_capabilities_acl.sql':harness
})) {
 if(process.argv.includes('--check')) { if(read(path)!==content) throw new Error('Artifact differs: '+path); }
 else fs.writeFileSync(path,content);
}
console.log('039j artifacts '+(process.argv.includes('--check')?'match':'prepared')+' offline; no SQL executed.');
