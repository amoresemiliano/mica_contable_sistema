// Static/local evidence only. SQL harness is prepared for manual execution.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {permissionByCode,presetCapabilities,MICA_PERMISSION_CATALOG_039B} from '../../src/js/core/micaPermissionContract.js';
import {editableCapabilities,permissionPreview} from '../../src/js/core/services/administrationService.js';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/039g_delegate_organization_create.sql'),down=read('sql/039g_delegate_organization_create_down.sql');
test('only organization creation becomes delegable; frozen 039b projection stays reserved',()=>{
 const c=permissionByCode('ORGANIZATION_CREATE');
 expect(c).toMatchObject({ownerReserved:false,delegationClass:'PLATFORM_DELEGABLE',assignable:true,visibleInEditor:true});
 expect(presetCapabilities('ACCOUNTING_SUPERADMIN','PLATFORM')).toContain(c.code);
 expect(editableCapabilities([{code:c.code,scope:'PLATFORM',delegation_class:'PLATFORM_DELEGABLE'}],'PLATFORM')).toHaveLength(1);
 expect(editableCapabilities([{code:c.code,scope:'PLATFORM',delegation_class:'OWNER_RESERVED'}],'PLATFORM')).toHaveLength(0);
 for(const code of ['ORGANIZATION_ARCHIVE','ACCESS_ANY_ORG','GLOBAL_USER_MANAGE','PLATFORM_MANAGE','SUPPORT_IMPERSONATE','HARD_DELETE_EXCEPTIONAL','PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION']) {
  expect(permissionByCode(code).ownerReserved).toBe(true);
  expect(presetCapabilities('ACCOUNTING_SUPERADMIN','PLATFORM')).not.toContain(code);
 }
 expect(MICA_PERMISSION_CATALOG_039B.find(c=>c.code==='ORGANIZATION_CREATE').ownerReserved).toBe(true);
 expect(permissionPreview({inherited:true,overrides:['ALLOW','DENY']})).toMatchObject({effective:false,effect:'DENY'});
});
test('039g changes one class and grants only root and accounting without replacing authorization',()=>{
 expect(up.match(/UPDATE public\.eco_capabilities SET[^;]+;/g)).toEqual(["UPDATE public.eco_capabilities SET delegation_class='PLATFORM_DELEGABLE' WHERE code='ORGANIZATION_CREATE';"]);
 expect(up).toContain('ARRAY[b.root_template,b.accounting_template]');
 expect(up).not.toMatch(/CREATE OR REPLACE FUNCTION|UPDATE private\.eco_platform_org_scopes|INSERT INTO private\.eco_platform_org_scopes/);
 for(const name of ['guard_036_capability','guard_036_reserved_frozen']) {
  expect(up).toContain('DISABLE TRIGGER '+name);expect(up).toContain('ENABLE TRIGGER '+name);
  expect(down).toContain('DISABLE TRIGGER '+name);expect(down).toContain('ENABLE TRIGGER '+name);
 }
 expect(up).toContain('IN ACCESS EXCLUSIVE MODE');
 expect(up).toContain("current_user<>'postgres'");
 expect(down).not.toMatch(/CASCADE|DELETE FROM private\.eco_platform_owner/);
 for(const text of ['b.installed_capability','b.installed_grants','b.security_functions','b.protection_triggers','039g exact restoration failed']) expect(down).toContain(text);
});
test('preflight is readonly and distinguishes requested people, scopes, overrides and structural owner',()=>{
 const sql=read('sql/039g_preflight_readonly.sql').replace(/--[^\n]*/g,'');
 expect(sql).not.toMatch(/\b(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|DO|CALL)\b/i);
 for(const value of ['drcmarianela@gmail.com','vegendigital@gmail.com','all_active_organizations_scoped','structural_owner','platform_override','organization_override']) expect(sql).toContain(value);
 expect(up).not.toContain('@gmail.com');
});
test('prepared harness covers root protection, scopes, imports and DENY',()=>{
 const sql=read('tests/db/039g_delegate_organization_create.sql');
 for(const value of ['Root lost create','Root deactivation allowed','Root reassignment allowed','Root override allowed','Root preset modification allowed',
  'Archive allowed','Structural privilege leaked','Existing scopes changed','Explicit scopes missing','DENY failed to override base',
  'ARCA_RECIBIDOS','ARCA_EMITIDOS','PERCEPCIONES_IVA','PERCEPCIONES_ARBA','BANK_STATEMENT_BBVA','PAYROLL_ACONPY']) expect(sql).toContain(value);
 expect(sql.trim().endsWith('ROLLBACK;')).toBe(true);
});

test('standalone 039g harness targets post-039h and historical accounting is only a rejected assignment',()=>{
 const sql=read('tests/db/039g_delegate_organization_create.sql');
 expect(sql).toContain("INTO STRICT operational FROM public.eco_role_templates WHERE code='ADMINISTRACION_OPERATIVA_MICA' AND scope='PLATFORM' AND is_active");
 expect(sql).toContain("INTO STRICT historical FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN' AND NOT is_active");
 expect(sql).toContain("code='VEGEN_PLATFORM_ADMIN'");
 const attempt=sql.match(/BEGIN\s+PERFORM public\.mica_admin_apply\('platform_role',jsonb_build_object\('user_profile_id',staff,'role_template_id',historical\)\);[\s\S]*?END;/)?.[0];
 expect(attempt).toContain('Deprecated ACCOUNTING_SUPERADMIN assignment allowed');
 expect(attempt).toContain('EXCEPTION WHEN insufficient_privilege THEN NULL');
 expect(sql.match(/'role_template_id',historical/g)).toHaveLength(1);
 for(const text of ['Create/archive delegation contract changed','Creation without capability allowed','Artificial platform membership',
  'ACCESS_ANY_ORG bypassed creation DENY','Root assignment changed','Deprecated preset reactivated or assigned']) expect(sql).toContain(text);
 expect(sql).not.toMatch(/INSERT INTO public\.eco_organization_members|UPDATE public\.eco_role_templates/);
});
test('previous migrations remain byte-for-byte unchanged',()=>{
 for(const [file,hash] of Object.entries(JSON.parse(read('tests/fixtures/039g_previous_sql.sha256.json'))))
  expect(createHash('sha256').update(readFileSync(file)).digest('hex')).toBe(hash);
});
