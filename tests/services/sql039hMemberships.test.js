import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/039h_operational_administration.sql'), down=read('sql/039h_operational_administration_down.sql');
const reviewed=JSON.parse(read('sql/039h_reviewed_memberships.json'));
test('accepts only the three reviewed membership identities, organizations, CONSULTANT preset and active state',()=>{
 expect(reviewed.map(m=>m.id).sort()).toEqual(['43c506ef-ccd8-4e5c-8b48-a3aedd6562e5','1a4b2b8e-f411-4fdc-a73f-e2eae3d497fc','27745eb5-bf76-4b59-9b01-416caef5713d'].sort());
 for(const member of reviewed) {
  expect(member.preset_code).toBe('CONSULTANT');expect(member.is_active).toBe(true);
  expect(up).toContain(member.id);expect(up).toContain(member.organization_id);
 }
 const preflight=up.split('END; $preflight$;')[0];
 for(const guard of ['count(*) FROM public.eco_organization_members WHERE user_profile_id=target)<>3',
 'member_row.id=expected_member.id','member_row.user_profile_id=target',
 'member_row.organization_id=expected_member.organization_id','member_row.is_active=expected_member.is_active',
 'tenant_preset.code=expected_member.preset_code',"tenant_preset.scope='ORGANIZATION'",'Unreviewed membership overrides']) expect(preflight).toContain(guard);
 expect(preflight).not.toContain('OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target)');
});
test('captures complete before/installed rows and changes only active flags before platform reassignment',()=>{
 expect(up).toContain('memberships_before=(SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY id)');
 expect(up).toContain('memberships_installed=(SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id)');
 const normalization=up.match(/UPDATE public\.eco_organization_members SET is_active=FALSE[^;]+;/)?.[0];
 expect(normalization).toContain('WHERE user_profile_id=b.target');
 expect(normalization).toContain('jsonb_array_elements(b.memberships_before)');
 expect(normalization).not.toContain('role_template_id');
 expect(up.indexOf(normalization)).toBeLessThan(up.indexOf('UPDATE public.eco_user_platform_role SET role_template_id=tpl'));
 expect(up).not.toMatch(/DELETE FROM public\.eco_organization_members/);
 for(const guard of ['Expected seven active explicit scopes','Existing scopes changed','Membership normalization changed identity or left active tenants']) expect(up).toContain(guard);
});
test('DOWN rejects drift and overrides before restoring complete original rows without inventing memberships or scopes',()=>{
 for(const guard of ['Installed memberships drift','Unreviewed membership overrides block restoration','jsonb_populate_record(NULL::public.eco_organization_members,$1)',
 'jsonb_array_elements(b.memberships_before)','Exact membership restoration failed','Rollback changed scopes']) expect(down).toContain(guard);
 expect(down).not.toMatch(/(?:INSERT INTO|DELETE FROM) (?:public\.eco_organization_members|private\.eco_platform_org_scopes)/);
 expect(down.indexOf('Installed memberships drift')).toBeLessThan(down.indexOf('UPDATE public.eco_role_templates'));
});
test('roundtrip harness uses the actual release and DOWNs, with BEFORE fixture, scope-only operation and exact restoration',()=>{
 const harness=read('tests/db/039h_membership_roundtrip.sql');
 const inner=sql=>sql.replace(/^BEGIN;\n/m,'').replace(/(?:COMMIT|ROLLBACK);\s*$/,'');
 expect(harness).toContain(inner(read('sql/039g_revised_release.sql')));
 expect(harness).toContain(inner(down));
 expect(harness).toContain(inner(read('sql/039g_delegate_organization_create_down.sql')));
 for(const text of ['Expected mixed platform and active historical tenant BEFORE fixture','Historical memberships missing or still active',
 'Scope-only operation failed','Roundtrip did not restore exact memberships/scopes/assignment/preset/grants/functions',
 'ROLLBACK TO SAVEPOINT operational_checks']) expect(harness).toContain(text);
 expect(harness.match(/^BEGIN;$/gm)).toHaveLength(1);
 expect(harness).not.toMatch(/^COMMIT;$/m);
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});
test('reviewed target manifest remains byte-for-byte unchanged',()=>{
 expect(createHash('sha256').update(readFileSync('sql/039h_live_target_manifest.json')).digest('hex'))
  .toBe('232e69a581b5dcb489686982f296fc918fff33da7d4da1714a4fe4db10205ac0');
});
