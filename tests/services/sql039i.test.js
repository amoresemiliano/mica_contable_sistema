// Static verification only. PostgreSQL execution is explicitly outside this task.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=path=>readFileSync(path,'utf8').replaceAll('\r','');
const up=read('sql/039i_fix_mica_admin_apply_ambiguity.sql');
const down=read('sql/039i_fix_mica_admin_apply_ambiguity_down.sql');
const harness=read('tests/db/039i_fix_mica_admin_apply_ambiguity.sql');
const definition=sql=>sql.match(/CREATE OR REPLACE FUNCTION public\.mica_admin_apply\(p_action TEXT,p_data JSONB\)[\s\S]*?END; \$\$;/)[0];
const oldFunction=definition(read('sql/039h_operational_administration.sql'));
const newFunction=definition(up);
const hash=sql=>createHash('md5').update(sql.split('AS $$')[1].split('$$;')[0].trim()).digest('hex');

test('only the reviewed table alias and three column qualifications change',()=>{
 expect(newFunction).toBe(oldFunction.replace(
  "FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN'\n    AND ((p_action='preset' AND id=result) OR (p_action IN ('platform_role','membership') AND id=tpl))",
  "FROM public.eco_role_templates rt WHERE rt.code='ACCOUNTING_SUPERADMIN'\n    AND ((p_action='preset' AND rt.id=result) OR (p_action IN ('platform_role','membership') AND rt.id=tpl))"));
 expect(newFunction).not.toBe(oldFunction);
 expect(up.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(1);
 const wrapper=up.replace(newFunction,'');
 expect(wrapper).not.toMatch(/(?:INSERT INTO|UPDATE|DELETE FROM|ALTER TABLE) public\./);
 expect(wrapper).not.toMatch(/DISABLE TRIGGER|session_replication_role/);
});

test('preflight pins installed 039h definition, hash, owner, ACL, security and search path',()=>{
 for(const text of ['private.migration_039g_create','private.migration_039h_state','private.migration_039h_functions',
  'pg_get_functiondef(proc_row.oid)=saved_function.installed',"pg_get_userbyid(proc_row.proowner)='postgres'",
  'proc_row.prosecdef',`proc_row.proconfig=ARRAY['search_path=""']::TEXT[]`,
  'to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl',hash(oldFunction),hash(newFunction)]) expect(up).toContain(text);
 expect(up.indexOf('039i exact 039h definition/owner/ACL/security drift')).toBeLessThan(up.indexOf('CREATE TABLE'));
 expect(up).toContain('REVOKE ALL ON private.migration_039i_function FROM PUBLIC,anon,authenticated');
});

test('DOWN rejects drift and restores the captured defective definition with exact ACL/owner checks',()=>{
 expect(down).toContain('pg_get_functiondef(proc_row.oid)=v_saved.installed');
 expect(down).toContain(hash(newFunction));
 expect(down).toContain('EXECUTE v_saved.definition');
 expect(down).toContain('pg_get_functiondef(proc_row.oid)=v_saved.definition');
 expect(down.match(/to_jsonb\(proc_row.proacl\) IS NOT DISTINCT FROM v_saved.acl/g)).toHaveLength(2);
 expect(down).not.toMatch(/CASCADE|(?:INSERT INTO|UPDATE|DELETE FROM|ALTER TABLE) public\./);
});

test('regression catches the ambiguous code predicate and audits variable/SQL alias collisions',()=>{
 const ambiguous=sql=>/\b(?:WHERE|AND|OR)\s+code\s*=/i.test(sql);
 expect(ambiguous(oldFunction)).toBe(true);
 expect(ambiguous(newFunction)).toBe(false);
 const clean=newFunction.replace(/'(?:''|[^'])*'|--[^\n]*/g,' ');
 const locals=clean.match(/DECLARE([\s\S]*?)BEGIN/)[1].split(';').map(s=>s.trim().match(/^(\w+)\s+/)?.[1]).filter(Boolean);
 for(const name of ['code','org','target','result','active','effect','kind','sc','tpl','cap','member']) expect(locals).toContain(name);
 const aliases=[...clean.matchAll(/\b(?:FROM|JOIN|UPDATE)\s+(?:public|private)\.\w+\s+(\w+)/gi)].map(m=>m[1]);
 expect(aliases.filter(alias=>locals.includes(alias))).toEqual([]);
 // Bare code is allowed only as a local loop variable/argument, or an INSERT target column.
 const remaining=clean.replace(/INSERT INTO public\.eco_role_templates\([^)]*\)/g,'')
  .replace(/\bcode TEXT/g,'').replace(/FOR code IN/g,'').replace(/admin_038_cap\(code,/g,'admin_038_cap(');
 expect(remaining).not.toMatch(/(?<![.\w])code\b/);
});

test('prepared harness includes all 039h checks and 039g checks adapted only to the current preset',()=>{
 const block=path=>read(path).match(/DO \$test\$[\s\S]*?END; \$test\$;/)[0];
 expect(harness).toContain(block('tests/db/039h_operational_administration.sql'));
 expect(harness).toContain(block('tests/fixtures/039g_pre039h_harness.sql')
  .replace("code='ACCOUNTING_SUPERADMIN'","code='ADMINISTRACION_OPERATIVA_MICA'"));
 for(const guard of ['Tenant assignment/activation failed','Deprecated preset assignment allowed','Root preset edit allowed',
  'Forbidden platform capability','Historical memberships or seven scopes changed','DENY failed to override base']) expect(harness).toContain(guard);
 expect(harness).toContain(down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,''));
 expect(harness).toContain('039i DOWN did not restore exact 039h definition');
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});

test('all historical SQL including applied 039g/039h and atomic release remains byte-identical',()=>{
 const hashes=JSON.parse(read('tests/fixtures/039i_previous_sql.sha256.json'));
 expect(hashes).toHaveProperty(['sql/039g_revised_release.sql']);
 expect(hashes).toHaveProperty(['sql/039h_operational_administration.sql']);
 for(const [path,expected] of Object.entries(hashes)) expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(expected);
 expect(createHash('sha256').update(readFileSync('sql/039h_live_target_manifest.json')).digest('hex'))
  .toBe('232e69a581b5dcb489686982f296fc918fff33da7d4da1714a4fe4db10205ac0');
});
