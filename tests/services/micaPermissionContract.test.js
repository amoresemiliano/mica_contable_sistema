import { readFileSync } from 'node:fs';
import { MICA_PERMISSION_CATALOG as catalog, MICA_PRESET_DEFINITIONS as presets, PERMISSION_GROUPS,
    MICA_MODULE_CONTRACT, MICA_IMPORT_CONTRACT, presetCapabilities } from '../../src/js/core/micaPermissionContract.js';
import { isMicaCapability } from '../../src/js/core/micaCapabilities.js';
import { editableCapabilities, permissionPreview } from '../../src/js/core/services/administrationService.js';
import { capabilityPresentation } from '../../src/js/core/capabilityPresentation.js';
import { canImport, canVisitModule, canOperationalAction } from '../../src/js/core/moduleAccess.js';
const read = path => readFileSync(path,'utf8');
const actor = (codes, platform=[], org='NORTE') => ({contextState:org?'TENANT_READY':'PLATFORM_READY',activeOrganizationId:org,
    hasCapability:(code,{scope='PLATFORM'}={})=>(scope==='ORGANIZATION'?codes:platform).includes(code)});

test('every permission has unique explicit Spanish product metadata and declared presets', () => {
    expect(new Set(catalog.map(c=>c.code)).size).toBe(catalog.length);
    for(const c of catalog) {
        expect(c.label).toMatch(/[a-záéíóúñ]/); expect(c.label).not.toBe(c.code);
        expect(c.description.length).toBeGreaterThan(20); expect(PERMISSION_GROUPS[c.group]).toBeDefined();
        expect(['PLATFORM','ORGANIZATION']).toContain(c.scope); expect(Number.isInteger(c.order)).toBe(true);
        expect(typeof c.ownerReserved).toBe('boolean'); expect(typeof c.assignable).toBe('boolean');
        expect(['ACTIVE','DISABLED_PENDING_BACKEND']).toContain(c.runtimeStatus);
        for(const preset of c.defaultPresets) expect(presets[preset]).toBeDefined();
        expect(capabilityPresentation({code:c.code,description:'server English text'}).label).toBe(c.label);
    }
});
test('proposals and reserved authority stay outside normal editor and effective product allowlist', () => {
    for(const c of catalog.filter(c=>c.status==='PROPOSED')) {
        expect(c.defaultPresets).toEqual([]); expect(c.assignable).toBe(false);
        expect(isMicaCapability(c.code,c.scope)).toBe(false);
        expect(editableCapabilities([c],c.scope)).toEqual([]);
    }
    expect(editableCapabilities(catalog.filter(c=>c.ownerReserved),'PLATFORM')).toEqual([]);
    for(const code of ['RECIPES_VIEW','INVENTORY_VIEW'])
        expect(editableCapabilities([{code,scope:'ORGANIZATION'}],'ORGANIZATION')).toEqual([]);
    expect(editableCapabilities(catalog,'ORGANIZATION').some(c=>c.code==='RECORD_RESTORE')).toBe(false);
    expect(editableCapabilities(catalog,'ORGANIZATION','PLATFORM_BRIDGE').some(c=>c.code==='RECORD_RESTORE')).toBe(true);
});
test.each(Object.keys(presets))('%s: module, direct navigation, importer and action matrix consumes effective grants', preset => {
    const codes=presetCapabilities(preset,'ORGANIZATION'), platform=presetCapabilities(preset,'PLATFORM');
    const s=actor(codes,platform);
    for(const [id,rule] of Object.entries(MICA_MODULE_CONTRACT)) expect(canVisitModule(s,id)).toBe(rule.any.some(c=>codes.includes(c)));
    for(const [type,rule] of Object.entries(MICA_IMPORT_CONTRACT)) expect(canImport(s,type)).toBe(rule.enabled&&rule.all.every(c=>codes.includes(c)));
    expect(canOperationalAction(s,'classify')).toBe(['ROOT_TECHNICAL_MICA','ACCOUNTING_SUPERADMIN','MICA_ORG_ADMIN','MICA_ACCOUNTANT'].includes(preset));
    expect(canOperationalAction(s,'softDelete')).toBe(canOperationalAction(s,'classify'));
    expect(canOperationalAction(s,'restore')).toBe(['ROOT_TECHNICAL_MICA','ACCOUNTING_SUPERADMIN'].includes(preset));
    expect(canOperationalAction(s,'export')).toBe(preset!=='MICA_IMPORT_OPERATOR');
    expect(canOperationalAction(s,'manualCreate')).toBe(false);
    const noTenant=actor(codes,platform,null);
    for(const type of Object.keys(MICA_IMPORT_CONTRACT)) expect(canImport(noTenant,type)).toBe(false);
    expect(canVisitModule(noTenant,'tab-bancos')).toBe(false);
    expect(canVisitModule(s,'tab-client-ocr')).toBe(false);
});
test('ALLOW extends a readonly preset but DENY removes the action, regardless of legacy role', () => {
    const base=presetCapabilities('MICA_READ_ONLY','ORGANIZATION');
    const effective = overrides => [...new Set([...base,'IMPORT_CREATE','BANK_IMPORT'])].filter(code=>
        permissionPreview({inherited:base.includes(code),overrides:overrides[code]||[]}).effective);
    const s=actor(effective({IMPORT_CREATE:['ALLOW'],BANK_IMPORT:['ALLOW']}));
    s.currentUserRole='USER'; expect(canImport(s,'banco')).toBe(true);
    const denied=actor(effective({IMPORT_CREATE:['ALLOW'],BANK_IMPORT:['ALLOW','DENY']}));
    denied.currentUserRole='SUPERADMIN'; expect(canImport(denied,'banco')).toBe(false);
    expect(canImport(actor(['IMPORT_CREATE'],['ACCESS_ANY_ORG']),'banco')).toBe(false);
});
test('approved additions are assignable independently of their unavailable backend', () => {
    const additions=catalog.filter(c=>c.scope==='ORGANIZATION'&&c.status==='PREPARED_039B');
    expect(additions).toHaveLength(11);
    expect(editableCapabilities(additions,'ORGANIZATION')).toEqual(additions);
    for(const c of additions) {
        expect(c.delegationClass).toBe('ORGANIZATION_DELEGABLE');
        expect(c.runtimeStatus).toBe('DISABLED_PENDING_BACKEND');
        expect(isMicaCapability(c.code,c.scope)).toBe(true);
    }
    const s=actor(catalog.filter(c=>c.scope==='ORGANIZATION').map(c=>c.code));
    for(const action of ['manualCreate','manualEdit','manualSoftDelete']) expect(canOperationalAction(s,action)).toBe(false);
    expect(canImport(s,'recibido')).toBe(false);
});
test('historical tenant restore and ACCESS_ANY_ORG cannot bypass the new platform gate', () => {
    const contextual=['RECORD_VIEW','RECORD_RESTORE'];
    expect(canOperationalAction(actor(contextual),'restore')).toBe(false);
    expect(canOperationalAction(actor(contextual,['ACCESS_ANY_ORG']),'restore')).toBe(false);
    expect(canOperationalAction(actor(contextual,['DATA_RESTORE_ANY_ORG']),'restore')).toBe(true);
    expect(canOperationalAction(actor(['RECORD_VIEW'],['DATA_RESTORE_ANY_ORG']),'restore')).toBe(false);
    expect(canOperationalAction(actor(contextual,['DATA_RESTORE_ANY_ORG'],null),'restore')).toBe(false);
    for(const preset of Object.keys(presets).filter(p=>presets[p].scope==='ORGANIZATION')) {
        expect(presetCapabilities(preset,'PLATFORM')).toEqual([]);
        expect(presetCapabilities(preset,'ORGANIZATION')).not.toContain('RECORD_RESTORE');
    }
});
test('OCR is contained by manual entry, no independent menu or fake simulator promise', () => {
    const html=read('index.html');
    const manual=html.split('<section id="tab-movimientos-manuales"')[1].split('</section>')[0];
    expect(manual).toContain('id="manual-ocr-panel"'); expect(manual).toContain('id="ocr-input"');
    expect(html).not.toContain("switchTab('tab-client-ocr')");
    expect(html).not.toContain('id="tab-client-ocr"'); expect(manual).not.toContain('Simulador');
    expect(manual).toContain('form-purchase-reginfo'); expect(manual).toContain('form-internal-movement');
});
