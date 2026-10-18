// Static contracts only. This suite never executes SQL.
import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/042_multiorg_and_rate_assignments.sql'),down=read('sql/042_multiorg_and_rate_assignments_down.sql');
const func=name=>up.match(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?\\$\\$;'))[0];
test('042 preflight hashes derive from the canonical pre-042 bodies and check security metadata',()=>{
 const sources=['sql/019_capability_foundation.sql','sql/023_clean_authorization_cutover.sql','sql/037_platform_tenant_operation.sql','sql/041_administration_completion.sql'].map(read);
 const pairs=[...up.split('END; $preflight$;')[0].matchAll(/\('([^']+\([^']*\))','([a-f0-9]{32})'\)/g)];
 expect(pairs).toHaveLength(10);
 for(const [,signature,hash] of pairs){
  const name=signature.split('(')[0];
  const body=sources.flatMap(s=>[...s.matchAll(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?AS \\$\\$([\\s\\S]*?)\\$\\$;','g'))]).at(-1)[1].trim();
  expect(crypto.createHash('md5').update(body).digest('hex')).toBe(hash);
 }
 expect(up).toContain("pg_get_userbyid(p.proowner)='postgres'");expect(up).toContain('p.proconfig=ARRAY');expect(up).toContain('aclexplode');
});
test('membership list is caller-only, active organization/role checked, with Platform explicit scopes preserved',()=>{
 const list=func('public.list_my_organization_contexts');
 expect(list).toContain('m.user_profile_id=actor AND m.is_active AND o.is_active AND t.is_active');
 expect(list).toContain("t.scope='ORGANIZATION'");expect(list).toContain('private.platform_org_in_scope(o.id)');
 expect(list).toContain('role_template_id UUID,role_name TEXT');
});
test('tenant switch validates server membership, rejects null, locks revocable access and only changes session context',()=>{
 const change=func('public.switch_my_organization_context');
 expect(change).toContain('p_org_id IS NULL');expect(change).toContain('m.organization_id=p_org_id');
 expect(change).toContain('FOR SHARE OF m,o,t');expect(change).toContain('FOR UPDATE');
 expect(change).toContain('public.switch_superadmin_org_context(p_org_id)');
 expect(change).not.toContain('UPDATE public.eco_user_profiles');expect(change).not.toContain('INSERT INTO public.eco_organization_members');
 expect(change).toContain("'ORGANIZATION_CONTEXT_SWITCHED'");
});
test('initial context preserves accessible selection, uses deterministic existing-name order and never gives a tenant Platform',()=>{
 const context=func('public.get_my_operational_context');
 expect(context).toContain('c.organization_id=org');expect(context).toContain('p.organization_id=c.organization_id');
 expect(context).toContain('ORDER BY c.organization_name,c.organization_id LIMIT 1');
 expect(context).toContain('No active organization membership');expect(context).toContain('public.switch_my_organization_context(org)');
 expect(context).toContain('m.organization_id=org AND m.is_active AND t.is_active');
 expect(context).toContain("'can_switch_organization_context',NOT platform");
 expect(context).not.toContain('STABLE');
});
test('IIBB list reports target activity prerequisite; original guard/overlap/rate authority remain mandatory',()=>{
 const rates=func('public.mica_platform_iibb');
 expect(rates).toContain("'activity_assigned',EXISTS");expect(rates).toContain('m.organization_id=p_org AND m.activity_id=d.activity_id');
 expect(rates).toContain('Primero asigná la actividad económica % a esta empresa.');
 expect(rates).toContain("private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org)");
 expect(rates).toContain("RAISE EXCEPTION 'Conflicting active rate period'");
 expect(up).not.toContain('CREATE OR REPLACE FUNCTION private.guard_041');
 expect(up.match(/CREATE OR REPLACE FUNCTION [^(]+/g)).toEqual(['CREATE OR REPLACE FUNCTION public.get_my_operational_context','CREATE OR REPLACE FUNCTION public.mica_platform_iibb']);
});
test('all new/replaced RPCs are SECURITY DEFINER with fixed search path; rollback restores exact contracts and preserves data',()=>{
 expect(up.match(/LANGUAGE plpgsql(?: STABLE)? SECURITY DEFINER SET search_path=''/g)).toHaveLength(4);
 expect(up).toContain('FROM PUBLIC,anon');expect(up).toContain('TO authenticated');
 expect(down).toContain('EXECUTE r.definition');expect(down).toContain('p.proacl IS NOT DISTINCT FROM r.acl');
 expect(down).not.toContain('DELETE FROM');expect(down).not.toContain('CASCADE');
 expect(down).not.toContain('DROP TABLE public.');
});
