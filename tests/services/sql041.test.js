// Contract checks only. Prepared DB harness is never executed by these tests.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read = path => readFileSync(path,'utf8').replaceAll('\r','');
const up=read('sql/041_administration_completion.sql'),down=read('sql/041_administration_completion_down.sql');
const body=name=>up.match(new RegExp('CREATE FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?\\$\\$;'))[0];
const authority=body('private.admin_041_platform'),bridge=body('private.admin_041_bridge'),role=body('private.admin_041_role');
const users=body('public.mica_platform_access'),rates=body('public.mica_platform_iibb'),guard=body('private.guard_041_iibb_assignment');
test('additive 041 never replaces canonical context/tenant authorization functions or grants capabilities',()=>{
 expect(up).not.toContain('CREATE OR REPLACE FUNCTION');
 expect(up).not.toMatch(/(INSERT INTO|UPDATE|DELETE FROM) public\.eco_capabilities/);
 expect(up).not.toContain('SET organization_id=');
 expect(up).not.toContain('set_active_org_context');
 expect(up).toContain('search_path=');
 expect(up.match(/LANGUAGE plpgsql[\s\S]*?SECURITY DEFINER SET search_path=''/g)).toHaveLength(7);
 expect(up).toContain('FROM PUBLIC,anon,authenticated');
 expect(up).toContain('TO authenticated');
});
test('preflight fingerprints are derived from canonical sources and guard owner/security metadata',()=>{
 const sources=['sql/038_mica_administration.sql','sql/039b_operational_access_and_ux.sql','sql/037_platform_tenant_operation.sql','sql/036_owner_core_and_delegation_guard.sql','sql/039h_operational_administration.sql','sql/040_organization_profile_fields.sql'];
 const expected=[...up.split('END; $preflight$;')[0].matchAll(/\('([^']+\([^']*\))','([a-f0-9]{32})'\)/g)];
 expect(expected).toHaveLength(12);
 for(const [,signature,hash] of expected) {
  const name=signature.split('(')[0];
  const source=sources.map(read).flatMap(s=>[...s.matchAll(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?AS \\$\\$([\\s\\S]*?)\\$\\$;','g'))]).at(-1);
  expect(createHash('md5').update(source[1].trim()).digest('hex')).toBe(hash);
 }
 expect(up).toContain("pg_get_userbyid(p.proowner)='postgres'");
 expect(up).toContain('p.proconfig=ARRAY');
});
test('Platform target authorization is explicit, scoped, and never establishes tenant context',()=>{
 expect(authority).toContain('private.has_mica_platform_role()');
 expect(authority).toContain('private.platform_org_in_scope(p_org)');
 expect(authority).toContain('private.admin_039b_users()');
 expect(authority).toContain('organization_id IS NOT NULL');
 expect(bridge).toContain("effect='DENY'");
 expect(bridge).toContain('public.eco_membership_capability_overrides');
 expect(bridge).toContain('public.eco_platform_role_org_capabilities');
 expect(bridge).not.toContain('private.can_operate_mica_org');
});
test('company invitations and assignments validate full role authority and preserve canonical membership identity',()=>{
 for(const cap of ['ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN']) expect(users).toContain(`private.admin_041_bridge(p_org,'${cap}')`);
 expect(role).toContain("t.scope='ORGANIZATION'");
 expect(role).toContain('p.organization_id=p_org');
 expect(role).toContain("t.code<>'ACCOUNTING_SUPERADMIN'");
 expect(role).toContain('private.admin_041_bridge(p_org,code)');
 expect(users).toContain('private.admin_038_target(target)');
 expect(users).toContain('ON CONFLICT(organization_id,user_profile_id)');
 expect(users).toContain('SET is_active=FALSE');
 expect(users).not.toContain('INSERT INTO auth.users');
 expect(users).not.toContain('DELETE FROM public.eco_organization_members');
 expect(users).toContain("'activated',FALSE");
 expect(users).toContain("'MICA_PLATFORM_COMPANY_ACCESS'");
});
test('new and existing emails have separate paths; incompatible/protected Platform roles stay forbidden',()=>{
 const platformRole = body('private.admin_041_platform_role');
 expect(users).toContain('u.email_confirmed_at IS NOT NULL');
 expect(users).toContain('ON CONFLICT(email) DO NOTHING');
 expect(users).toContain('Existing account must authenticate and confirm email; no duplicate invitation');
 expect(platformRole).toContain("t.scope='PLATFORM'");
 for(const code of ['ROOT_TECHNICAL_MICA','VEGEN_PLATFORM_ADMIN','ACCOUNTING_SUPERADMIN']) expect(platformRole).toContain(`'${code}'`);
 expect(users).toContain("private.admin_041_platform_role(role_id)");
 expect(platformRole).toContain("private.admin_038_cap(code,'ORGANIZATION',NULL)");
 expect(users).toContain("public.mica_invitation('create',NULL,p_data)");
 expect(users).toContain("public.mica_admin_apply('platform_role'");
});
test('IIBB preserves domain/version/history, requires rate authority, active activity assignment and nonoverlap',()=>{
 expect(rates).toContain("private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org)");
 expect(up).toContain('GROUP BY activity_id,jurisdiction,rate,valid_from,valid_to');
 for(const column of ['activity_id','jurisdiction','rate','valid_from','valid_to']) expect(rates).toContain(column);
 expect(rates).toContain('public.eco_org_economic_activities');
 expect(rates).toContain("COALESCE(definition.valid_from,'-infinity'::DATE)<=COALESCE(r.valid_to,'infinity'::DATE)");
 expect(rates).toContain('UPDATE public.eco_org_activity_iibb_rates SET is_active=FALSE');
 expect(rates).not.toContain('DELETE FROM');
 expect(guard).toContain('Rate version is immutable');
 expect(guard).toContain('IIBB history cannot be deleted');
 expect(guard).toContain("private.admin_041_platform('RATE_MANAGE_ANY_ORG',target)");
 expect(up).toContain('BEFORE INSERT OR UPDATE OR DELETE');
});
test('rollback removes only added contracts/provenance and preserves all org configuration/access history',()=>{
 expect(down).not.toContain('CASCADE');
 expect(down).not.toContain('DELETE FROM');
 expect(down).not.toContain('DROP TABLE public.eco_org_activity_iibb_rates');
 expect(down).toContain('DROP COLUMN definition_id');
 expect(down).toContain('private.migration_041_rollback_archive');
 expect(down).toContain("'assignments',COALESCE");
 for(const name of ['mica_platform_iibb','mica_platform_access','admin_041_platform','admin_041_bridge','admin_041_role','admin_041_platform_role','guard_041_iibb_assignment']) expect(down).toContain(name);
});
