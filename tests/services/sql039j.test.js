// Offline contracts only: no SQL/database execution and no claim of LIVE validation.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=path=>readFileSync(path,'utf8').replaceAll('\r','');
const up=read('sql/039j_harden_capabilities_acl.sql');
const down=read('sql/039j_harden_capabilities_acl_down.sql');
const harness=read('tests/db/039j_harden_capabilities_acl.sql');

test('039j changes only the approved capabilities table ACL for authenticated and anon',()=>{
 expect(up.match(/(?:GRANT|REVOKE) [^;]+ON public\.[^;]+;/g)).toEqual([
  'REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities FROM authenticated;',
  'REVOKE ALL ON public.eco_capabilities FROM anon;'
 ]);
 expect(up).not.toMatch(/(?:CREATE|ALTER|DROP) POLICY|DISABLE TRIGGER|CREATE OR REPLACE FUNCTION|FORCE ROW LEVEL SECURITY/);
 expect(up).not.toMatch(/(?:INSERT INTO|UPDATE|DELETE FROM) public\./);
 expect(up).toContain("v_role='authenticated' AND v_privilege='SELECT'");
 expect(up).toContain('039j grants of other roles changed');
});

test('preflight checks predecessors and effective authority, owner, RLS and SELECT policy before revocation',()=>{
 for(const name of ['private.migration_039g_create','private.migration_039h_state','private.migration_039i_function']) expect(up).toContain(name);
 for(const text of ["current_user<>'postgres'","pg_get_userbyid(relation_row.relowner)='postgres'",
  'relation_row.relrowsecurity AND NOT relation_row.relforcerowsecurity',
  "policy_row.polname='authenticated_read_capabilities' AND policy_row.polcmd='r' AND policy_row.polpermissive",
  "policy_row.polroles=ARRAY['authenticated'::regrole::OID]",
  "pg_get_expr(policy_row.polqual,policy_row.polrelid)='(is_active = true)' AND policy_row.polwithcheck IS NULL",
  "count(*) FROM pg_policy WHERE polrelid='public.eco_capabilities'::regclass)<>1",
  "ARRAY['anon','authenticated','postgres','service_role']",
  "ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']",
  "has_table_privilege(v_role,'public.eco_capabilities',v_privilege)",'039j unexpected column ACL requires review']) expect(up).toContain(text);
 expect(up.indexOf('039j prior effective authority differs')).toBeLessThan(up.indexOf('REVOKE INSERT'));
 expect(up).not.toMatch(/original_acl|installed_acl|jsonb_agg\(jsonb_build_object\('grantor'|exact expected ACL differs/);
});

test('backup and postchecks preserve owner, policies, guards and all non-target grants',()=>{
 for(const text of ['raw_acl ACLITEM[]',
  'REVOKE ALL ON private.migration_039j_acl FROM PUBLIC,anon,authenticated',
  'pg_get_functiondef(trigger_row.tgfoid)',"tgname='guard_036_capability' AND tgenabled='O'",
  "tgname='guard_036_capability_truncate' AND tgenabled='O'",'039j owner/RLS/policy/guard drift',
  "v_role IN ('postgres','service_role')",
  'aclexplode(v_saved.raw_acl)','EXCEPT SELECT * FROM current_grants','EXCEPT SELECT * FROM previous_grants']) expect(up).toContain(text);
 expect(up).toContain('039j installed effective authority differs: role %, privilege %');
});

test('DOWN checks installed effective authority and restores all eight prior privileges only for target roles',()=>{
 for(const text of ['039j installed effective authority differs','039j DOWN column ACL drift',
  'aclexplode(v_saved.raw_acl)',
  'GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.eco_capabilities TO anon, authenticated;',
  '039j prior effective authority differs']) expect(down).toContain(text);
 expect(down).not.toMatch(/CASCADE|DISABLE TRIGGER|(?:INSERT INTO|UPDATE|DELETE FROM) public\./);
 expect(down.indexOf('039j installed effective authority differs')).toBeLessThan(down.indexOf('GRANT SELECT'));
 expect(down.indexOf('039j prior effective authority differs')).toBeGreaterThan(down.indexOf('GRANT SELECT'));
 expect(down).not.toMatch(/IS DISTINCT FROM v_saved\.(?:raw_acl|original_acl|installed_acl)/);
});

test('harness separates SQL authority from row mutation and requires 42501, not zero affected rows',()=>{
 const aclChecks=harness.split('-- Execute 039i')[0];
 for(const text of ['039j installed effective authority differs', 'UPDATE public.eco_capabilities SET description=description WHERE FALSE;',
  'DELETE FROM public.eco_capabilities WHERE FALSE;','INSERT INTO public.eco_capabilities DEFAULT VALUES;',
  'TRUNCATE public.eco_capabilities;','SET LOCAL ROLE authenticated;', 'SET LOCAL ROLE anon;',
  'SET LOCAL ROLE service_role;', 'Anon SELECT returned without permission denied']) expect(aclChecks).toContain(text);
 expect(aclChecks.match(/EXCEPTION WHEN insufficient_privilege THEN NULL/g)).toHaveLength(9);
 expect(aclChecks).toContain("'TRIGGER','MAINTAIN'");
 for(const operation of ['UPDATE','INSERT','DELETE','TRUNCATE']) expect(aclChecks).toContain('Anon '+operation+' returned without permission denied');
 expect(aclChecks).not.toMatch(/WHEN OTHERS|GET DIAGNOSTICS|ROW_COUNT/);
 for(const text of ['Tenant assignment/activation failed','Deprecated preset assignment allowed','Root preset edit allowed',
  'DENY failed to override base','Historical memberships or seven scopes changed','039i DOWN did not restore exact 039h definition']) expect(harness).toContain(text);
 expect(harness).toContain(down.replace(/^BEGIN;\n/m,'').replace(/^COMMIT;\n/m,''));
 expect(harness).toContain('Marianela operational assignment missing');
 expect(harness).toContain("code='VEGEN_PLATFORM_ADMIN'");
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});

test('integrated historical checks distinguish mutation from SQL authority outside capabilities and ignore function ACL order',()=>{
 expect(harness.match(/GET DIAGNOSTICS v_deleted_rows = ROW_COUNT/g)).toHaveLength(2);
 expect(harness).toContain('v_deleted_rows BIGINT;');
 expect(harness).toContain("IF v_deleted_rows<>0 THEN RAISE EXCEPTION 'Root grants deletion allowed'");
 expect(harness).toContain('review structural ACL separately');
 expect(harness).not.toContain('to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM');
 expect(harness).toContain('FROM aclexplode(COALESCE(proc_row.proacl');
 const capabilityAttempt=harness.match(/UPDATE public\.eco_capabilities SET description='forbidden'[^;]+;[\s\S]*?END;/)?.[0];
 expect(capabilityAttempt).toContain("RAISE EXCEPTION 'Capability edit allowed'");
 expect(capabilityAttempt).not.toContain('ROW_COUNT');
});

test('structural table review is SELECT-only, includes inherited privileges and reports no unverified LIVE findings',()=>{
 const readonly=read('sql/039j_preflight_readonly.sql');
 const stripped=readonly.replace(/--[^\n]*|'(?:''|[^'])*'/g,'');
 expect(stripped).not.toMatch(/\b(INSERT|UPDATE|DELETE|TRUNCATE|GRANT|REVOKE|CREATE|ALTER|DROP|DO|CALL)\b/i);
 for(const table of ['eco_capabilities','eco_role_templates','eco_role_template_capabilities','eco_platform_role_org_capabilities','eco_user_platform_role']) expect(readonly).toContain(table);
 for(const text of ['has_table_privilege','aclexplode','is_grantable','attacl','pg_policy']) expect(readonly).toContain(text);
 expect(read('docs/039j_ACL_REVIEW.md')).toContain('No aportada; pendiente de consulta readonly');
});

test('historical SQL through LIVE 039i remains byte-identical',()=>{
 const hashes=JSON.parse(read('tests/fixtures/039j_previous_sql.sha256.json'));
 expect(hashes).toHaveProperty(['sql/039i_fix_mica_admin_apply_ambiguity.sql']);
 for(const [path,expected] of Object.entries(hashes)) expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(expected);
});
