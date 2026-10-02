// Offline artifact generation only. Never connects to or executes SQL against a database.
import fs from 'node:fs';
import {createHash} from 'node:crypto';
const read=path=>fs.readFileSync(path,'utf8').replaceAll('\r','');
const digest=text=>createHash('md5').update(text.trim()).digest('hex');
const historical=read('sql/039h_operational_administration.sql');
const original=historical.match(/CREATE OR REPLACE FUNCTION public\.mica_admin_apply\(p_action TEXT,p_data JSONB\)[\s\S]*?END; \$\$;/)?.[0];
if(!original) throw new Error('039h function missing');
const before="FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN'\n    AND ((p_action='preset' AND id=result) OR (p_action IN ('platform_role','membership') AND id=tpl))";
const after="FROM public.eco_role_templates rt WHERE rt.code='ACCOUNTING_SUPERADMIN'\n    AND ((p_action='preset' AND rt.id=result) OR (p_action IN ('platform_role','membership') AND rt.id=tpl))";
if(original.split(before).length!==2) throw new Error('Expected exactly one reviewed ambiguity');
const fixed=original.replace(before,after);
const body=sql=>sql.split('AS $$')[1].split('$$;')[0];
const originalHash=digest(body(original)), installedHash=digest(body(fixed));
const up=`-- MICA ourzapkjykzlwsjunzmd. 039i PREPARED ONLY. No SQL executed by the agent.
-- Only qualifies the deprecated-preset lookup. No data/grant/scope/authority changes.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039i requires postgres'; END IF;
 IF to_regclass('private.migration_039g_create') IS NULL
  OR to_regclass('private.migration_039h_state') IS NULL
  OR to_regclass('private.migration_039h_functions') IS NULL THEN
  RAISE EXCEPTION '039g and 039h must be installed'; END IF;
 IF to_regclass('private.migration_039i_function') IS NOT NULL THEN RAISE EXCEPTION '039i already installed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row JOIN private.migration_039h_functions saved_function
   ON saved_function.signature='public.mica_admin_apply(text,jsonb)'
   WHERE proc_row.oid=to_regprocedure(saved_function.signature)
    AND pg_get_userbyid(proc_row.proowner)='postgres' AND proc_row.prosecdef
    AND proc_row.proconfig=ARRAY['search_path=""']::TEXT[]
    AND pg_get_functiondef(proc_row.oid)=saved_function.installed
    AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
    AND saved_function.owner_name='postgres'
    AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='${originalHash}') THEN
  RAISE EXCEPTION '039i exact 039h definition/owner/ACL/security drift'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039i_function(
 id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id),definition TEXT NOT NULL,installed TEXT,
 owner_name TEXT NOT NULL,acl JSONB,settings TEXT[],security_definer BOOLEAN NOT NULL);
ALTER TABLE private.migration_039i_function ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039i_function FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039i_function(id,definition,owner_name,acl,settings,security_definer)
 SELECT TRUE,pg_get_functiondef(proc_row.oid),pg_get_userbyid(proc_row.proowner),to_jsonb(proc_row.proacl),proc_row.proconfig,proc_row.prosecdef
 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)');
${fixed}
DO $verify$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row CROSS JOIN private.migration_039i_function saved_function
  WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
   AND pg_get_userbyid(proc_row.proowner)=saved_function.owner_name
   AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
   AND proc_row.proconfig IS NOT DISTINCT FROM saved_function.settings
   AND proc_row.prosecdef=saved_function.security_definer
   AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='${installedHash}') THEN
  RAISE EXCEPTION '039i installation changed owner/ACL/security or unexpected body'; END IF;
 UPDATE private.migration_039i_function SET installed=pg_get_functiondef(to_regprocedure('public.mica_admin_apply(text,jsonb)'));
END; $verify$;
COMMIT;
`;
const down=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restores the exact defective 039h definition.
-- Roll back 039i BEFORE 039h. This deliberately restores the known ambiguity.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $restore$
DECLARE v_saved RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039i DOWN requires postgres'; END IF;
 IF to_regclass('private.migration_039i_function') IS NULL THEN RAISE EXCEPTION '039i not installed'; END IF;
 SELECT * INTO STRICT v_saved FROM private.migration_039i_function;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.installed
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer
  AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='${installedHash}') THEN
  RAISE EXCEPTION '039i DOWN definition/owner/ACL/security drift'; END IF;
 EXECUTE v_saved.definition;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  AND pg_get_functiondef(proc_row.oid)=v_saved.definition
  AND pg_get_userbyid(proc_row.proowner)=v_saved.owner_name
  AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM v_saved.acl
  AND proc_row.proconfig IS NOT DISTINCT FROM v_saved.settings AND proc_row.prosecdef=v_saved.security_definer) THEN
  RAISE EXCEPTION '039i DOWN exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039i_function;
COMMIT;
`;
const block=path=>read(path).match(/DO \$test\$[\s\S]*?END; \$test\$;/)?.[0];
const hHarness=block('tests/db/039h_operational_administration.sql');
// Frozen historical source: the standalone 039g harness now targets post-039h.
const gHarness=block('tests/fixtures/039g_pre039h_harness.sql');
if(!hHarness||!gHarness||gHarness.split("code='ACCOUNTING_SUPERADMIN'").length!==2) throw new Error('Harness sources differ');
const harness=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; run manually AFTER 039i. Never executed by agent.
-- Runs the complete 039h harness unchanged, then 039g checks with the current operational preset.
-- 039g originally assigned ACCOUNTING_SUPERADMIN: that assignment must stay blocked after 039h.
BEGIN;
DO $installed$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.migration_039i_function saved_function JOIN pg_proc proc_row
  ON proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
  WHERE pg_get_functiondef(proc_row.oid)=saved_function.installed
   AND pg_get_userbyid(proc_row.proowner)=saved_function.owner_name
   AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
   AND proc_row.proconfig IS NOT DISTINCT FROM saved_function.settings AND proc_row.prosecdef=saved_function.security_definer) THEN
  RAISE EXCEPTION '039i function or security drift'; END IF;
END; $installed$;
SAVEPOINT harness_039h;
${hHarness}
ROLLBACK TO SAVEPOINT harness_039h;
SAVEPOINT harness_039g_current_preset;
${gHarness.replace("code='ACCOUNTING_SUPERADMIN'","code='ADMINISTRACION_OPERATIVA_MICA'")}
ROLLBACK TO SAVEPOINT harness_039g_current_preset;
-- Exercise the actual DOWN and verify restoration without leaving the defective function installed.
SAVEPOINT harness_039i_down;
${down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,'')}
DO $restored$
BEGIN
 IF (SELECT pg_get_functiondef(to_regprocedure('public.mica_admin_apply(text,jsonb)')))
   IS DISTINCT FROM (SELECT saved_function.installed FROM private.migration_039h_functions saved_function
    WHERE saved_function.signature='public.mica_admin_apply(text,jsonb)') THEN
  RAISE EXCEPTION '039i DOWN did not restore exact 039h definition'; END IF;
END; $restored$;
ROLLBACK TO SAVEPOINT harness_039i_down;
ROLLBACK;
`;
for(const [path,content] of Object.entries({
 'sql/039i_fix_mica_admin_apply_ambiguity.sql':up,
 'sql/039i_fix_mica_admin_apply_ambiguity_down.sql':down,
 'tests/db/039i_fix_mica_admin_apply_ambiguity.sql':harness
})) {
 if(process.argv.includes('--check')) { if(read(path)!==content) throw new Error('Generated artifact differs: '+path); }
 else fs.writeFileSync(path,content);
}
console.log('039i artifacts '+(process.argv.includes('--check')?'match':'prepared')+' offline. No SQL executed.');
