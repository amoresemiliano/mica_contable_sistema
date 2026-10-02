import {readFileSync} from 'node:fs';
import {permissionByCode,presetCapabilities,MICA_OPERATIONAL_PLATFORM} from '../../src/js/core/micaPermissionContract.js';
import {editableCapabilities} from '../../src/js/core/services/administrationService.js';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/039h_operational_administration.sql'),down=read('sql/039h_operational_administration_down.sql');
test('operational preset has exactly functional platform grants and no permission editor',()=>{
 const platform=presetCapabilities('ADMINISTRACION_OPERATIVA_MICA','PLATFORM');
 expect(platform).toEqual(MICA_OPERATIONAL_PLATFORM);
 expect(platform).toHaveLength(9);
 for(const code of ['MICA_ADMIN_MANAGE','AUDIT_PLATFORM_VIEW','SAAS_ANALYTICS_VIEW','ACCESS_ANY_ORG','ORGANIZATION_ARCHIVE']) expect(platform).not.toContain(code);
 const org=presetCapabilities('ADMINISTRACION_OPERATIVA_MICA','ORGANIZATION');
 expect(org).not.toContain('ORG_MEMBER_PERMISSION_MANAGE');
 for(const code of ['ORG_MEMBER_PRESET_ASSIGN','FISCAL_DOCUMENT_IMPORT','MANUAL_MOVEMENT_CREATE','RECORD_RESTORE','CATALOG_CATEGORY_MANAGE']) expect(org).toContain(code);
 expect(permissionByCode('ORG_MEMBER_PRESET_ASSIGN')).toMatchObject({scope:'ORGANIZATION',delegationClass:'ORGANIZATION_DELEGABLE'});
 expect(editableCapabilities([{code:'ORG_MEMBER_PRESET_ASSIGN',scope:'ORGANIZATION'}],'ORGANIZATION')).toHaveLength(1);
});
test('tenant assignment and invitations are separated from overrides and global account activation',()=>{
 expect(up).toContain("PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PRESET_ASSIGN');");
 expect(up).toContain("PERFORM private.admin_038_authorize(p_org,NULL,'ORG_MEMBER_PRESET_ASSIGN');");
 expect(up).toContain("ELSIF p_action='override' AND kind='membership'");
 expect(up).toContain("PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');");
 for(const condition of ['Only an invited confirmed pending tenant','approved_at IS NULL','assigned_to=target AND organization_id=org','u.email_confirmed_at IS NOT NULL','organization_id<>org']) expect(up).toContain(condition);
 expect(up).not.toContain('@gmail.com');
 expect(up).not.toMatch(/CREATE OR REPLACE FUNCTION private\.(can_platform|can_operate_mica_org|guard_036)/);
});
test('exact reviewed identity, function drift, existing scopes, root and rollback references are guarded',()=>{
 for(const guard of ['Target identity/assignment drift','Target missing active explicit scopes','039h function drift','Existing scopes changed','Root changed','Review readonly preflight']) expect(up).toContain(guard);
 for(const guard of ['function/ACL drift','seeded row drift','additional recipients/references','f.definition','installed_assignment']) expect(down).toContain(guard);
 expect(down).not.toMatch(/CASCADE|DELETE FROM private\.eco_platform_org_scopes|DELETE FROM public\.eco_organizations/);
 const sql=read('sql/039h_preflight_readonly.sql').replace(/--[^\n]*/g,'');
 expect(sql).not.toMatch(/\b(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|DO|CALL)\b/i);
 const release=read('sql/039g_revised_release.sql');
 expect(release.match(/^BEGIN;$/gm)).toHaveLength(1);
 expect(release.match(/^COMMIT;$/gm)).toHaveLength(1);
 expect(release).toContain('Review readonly preflight; fill exact target manifest');
});
test('prepared rollback harness covers operational actor, denied structural actions and complete company editing',()=>{
 const harness=read('tests/db/039h_operational_administration.sql');
 for(const text of ['SELECT target,preset','legal_name','trade_name','tax_id','Archive allowed','New organization missing explicit scope',
 'Tenant assignment/activation failed','Tenant deactivation altered global account','Override allowed','Platform invitation allowed','Preset creation allowed',
 'Capability edit allowed','Root administration allowed','Root preset edit allowed','DENY bypassed','Root reserved authority lost','Root UI authority lost']) expect(harness).toContain(text);
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});
test('historical accounting is deactivated after reassignment with recipients and exact rollback guards',()=>{
 expect(up.indexOf('UPDATE public.eco_user_platform_role SET role_template_id=tpl')).toBeLessThan(up.indexOf('UPDATE public.eco_role_templates SET is_active=FALSE'));
 for(const text of ['Accounting has other active recipients','Cannot deprecate accounting with active recipients',
  'Historical accounting grants changed','Deprecated preset is historical only','historical_preset','historical_grants','historical_bridge']) expect(up).toContain(text);
 expect(up).not.toContain('DELETE FROM public.eco_role_templates');
 expect(down).toContain('Deprecated accounting state/grants/recipients drift');
 expect(down).toContain('Historical preset/assignment exact restoration failed');
 expect(down.indexOf('SET is_active=(b.historical_preset')).toBeLessThan(down.indexOf('UPDATE public.eco_user_platform_role SET'));
 const harness=read('tests/db/039h_operational_administration.sql');
 for(const text of ['Marianela operational assignment missing','Accounting is reusable or has active recipients','Deprecated preset assignment allowed',
 'Deprecated preset reactivation allowed','Create/archive boundary changed','Historical grants changed']) expect(harness).toContain(text);
});
