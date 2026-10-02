// Static checks only. These tests do not execute SQL or query LIVE.
import {readFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const tables=['eco_role_templates','eco_role_template_capabilities','eco_platform_role_org_capabilities',
 'eco_user_platform_role','eco_user_platform_capability_overrides','eco_membership_capability_overrides'];
const up=read('sql/039k_harden_structural_acl.sql'),down=read('sql/039k_harden_structural_acl_down.sql');
const harness=read('tests/db/039k_harden_structural_acl.sql');

test('only the six authorized table ACLs change, with retained SELECT only on the first two',()=>{
 const expected=tables.flatMap((table,i)=>[
  `REVOKE ${i<2?'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN':'ALL'} ON public.${table} FROM authenticated;`,
  `REVOKE ALL ON public.${table} FROM anon;`]);
 expect(up.match(/REVOKE [^;]+ ON public\.[^;]+;/g)).toEqual(expected);
 expect(up).not.toMatch(/(?:INSERT INTO|UPDATE|DELETE FROM|ALTER TABLE) public\./);
 expect(up).not.toMatch(/(?:ALTER|CREATE|DROP) POLICY|DISABLE TRIGGER|CREATE OR REPLACE FUNCTION/);
 for(const name of ['eco_organization_members','eco_user_profiles','eco_capabilities']) expect(up).not.toContain(`ON public.${name} `);
});

test('exact policy manifest is mandatory, and missing LIVE evidence fails closed before mutations',()=>{
 const manifest=JSON.parse(read('sql/039k_policy_manifest.json'));
 expect(Object.keys(manifest).sort()).toEqual([...tables].sort());
 expect(up).toContain('v_spec.policies IS NULL');
 expect(up).toContain('039k review LIVE policies and populate manifest');
 expect(up).toContain('IS DISTINCT FROM v_spec.policies');
 expect(up.indexOf('039k review LIVE policies')).toBeLessThan(up.indexOf('CREATE TABLE'));
 for(const text of ['private.migration_039j_acl',"pg_get_userbyid(relation_row.relowner)='postgres'",'relation_row.relrowsecurity',
  '039k guards 036 must remain active','039k platform role truncate guard missing','039k structural root assignment differs',
  '039k Marianela assignment differs','MAINTAIN','has_table_privilege(v_role,v_relation,v_privilege)']) expect(up).toContain(text);
});

test('DOWN validates the installed matrix before restoring eight effective privileges, preserving metadata and other roles',()=>{
 expect(down).toContain('039k backup incomplete');
 expect(down.indexOf('039k installed authority differs')).toBeLessThan(down.indexOf("EXECUTE format('GRANT"));
 for(const text of ['039k owner/RLS/policy/guard drift','039k grants of other roles changed',
  'aclexplode(v_saved.raw_acl)','EXCEPT SELECT * FROM current_grants','MAINTAIN ON %s TO anon, authenticated',
  '039k prior authority differs']) expect(down).toContain(text);
 expect(down).not.toMatch(/IS DISTINCT FROM v_saved\.raw_acl|(?:INSERT INTO|UPDATE|DELETE FROM) public\./);
});

test('harness requires permission denied even for zero-row DML, and exercises authorized RPCs plus previous harnesses',()=>{
 const first=harness.split('SAVEPOINT prior_harnesses;')[0];
 for(const operation of ['UPDATE','INSERT','DELETE','TRUNCATE','SELECT']) expect(first).toContain('Direct '+operation+' accepted');
 expect(first).toContain('Root grants DELETE did not raise 42501');
 expect(first.match(/EXCEPTION WHEN insufficient_privilege THEN NULL/g)).toHaveLength(6);
 expect(first).not.toContain('ROW_COUNT');
 expect(first).toContain("mica_admin_apply('preset'");
 expect(harness).toContain(read('tests/db/039j_harden_capabilities_acl.sql').replace(/^BEGIN;\n/m,'').replace(/^ROLLBACK;\s*$/m,''));
 expect(harness).toContain(down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,''));
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});

test('frontend has no direct structural-table call-sites; administration remains RPC based',()=>{
 const files=dir=>readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?(e.name==='vendor'?[]:files(dir+'/'+e.name)):e.name.endsWith('.js')?[dir+'/'+e.name]:[]);
 for(const file of files('src')) {
  const source=read(file);
  for(const table of tables) expect(source).not.toContain(table);
 }
 const service=read('src/js/core/services/administrationService.js');
 for(const rpc of ['mica_admin_read','mica_admin_apply','mica_invitation']) expect(service).toContain(rpc);
});

test('readonly policy capture performs no mutation and documentation distinguishes pending evidence from LIVE success',()=>{
 const readonly=read('sql/039k_preflight_readonly.sql').replace(/--[^\n]*|'(?:''|[^'])*'/g,'');
 expect(readonly).not.toMatch(/\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|GRANT|REVOKE|DO|CALL)\b/i);
 expect(read('docs/039k_STRUCTURAL_ACL_REVIEW.md')).toContain('pendiente de revisión');
});

test('historical SQL including applied 039j remains byte-identical',()=>{
 const hashes=JSON.parse(read('tests/fixtures/039k_previous_sql.sha256.json'));
 expect(hashes).toHaveProperty(['sql/039j_harden_capabilities_acl.sql']);
 for(const [path,hash] of Object.entries(hashes)) expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(hash);
});
