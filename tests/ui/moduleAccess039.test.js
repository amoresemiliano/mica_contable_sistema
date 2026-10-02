import { jest } from '@jest/globals';
import { canImport, canOcr, canVisitModule, pruneDeniedDatasets, renderModuleAccess } from '../../src/js/core/moduleAccess.js';
import { isMicaCapability } from '../../src/js/core/micaCapabilities.js';

function actor(codes = [], platform = []) {
    return { contextState: 'TENANT_READY', activeOrganizationId: 'NORTE', codes, platform,
        hasCapability(code, { scope = 'PLATFORM' } = {}) { return (scope === 'ORGANIZATION' ? this.codes : this.platform).includes(code); },
        isCatalogPlatformContext() { return false; },
        items: [{ id: 'private' }], perceptions: [], bankTransactions: [], salariesList: [], tenantResetListeners: [] };
}
test('root scope does not grant bank action; concrete grants do', () => {
    const s = actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE'], ['ACCESS_ANY_ORG']);
    expect(canImport(s,'banco')).toBe(false);
    s.codes.push('BANK_IMPORT'); expect(canImport(s,'banco')).toBe(true);
});
test.each(['SUPERADMIN','ADMIN','OWNER','CONSULTANT'])('legacy %s cannot import', role => {
    const s = actor(['RECORD_VIEW']); s.currentUserRole = role;
    for (const type of ['recibido','emitido','banco','percepcion','sueldo']) expect(canImport(s,type)).toBe(false);
});
test.each([
    [[], []], [['PERCEPTION_IMPORT'], ['percepcion']],
    [['BANK_IMPORT'], ['banco']], [['PAYROLL_IMPORT'], ['sueldo']]
])('IMPORT_CREATE plus %j enables only %j (with module VIEW)', (specific, expected) => {
    const s = actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE',...specific]);
    const types = ['recibido','emitido','percepcion','banco','sueldo'];
    expect(types.filter(type => canImport(s,type))).toEqual(expected);
});
test('all current action capabilities together cannot substitute a specific fiscal import capability', () => {
    const s=actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','BANK_IMPORT','PERCEPTION_IMPORT','PAYROLL_IMPORT','RECORD_CLASSIFY','DOCUMENTS_UPLOAD'], ['ACCESS_ANY_ORG']);
    expect(canImport(s,'recibido')).toBe(false); expect(canImport(s,'emitido')).toBe(false);
});
test('server effective result excluding denied PAYROLL wins over base or legacy flags', () => {
    const s = actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','BANK_IMPORT']);
    s.base = ['PAYROLL_IMPORT']; s.overrides = ['ALLOW','DENY'];
    expect(canImport(s,'sueldo')).toBe(false);
});
test.each(['PLATFORM_READY','LOADING','SWITCHING','ERROR','SIGNED_OUT'])('%s never imports', state => {
    const s = actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','BANK_IMPORT']); s.contextState = state;
    expect(canImport(s,'banco')).toBe(false);
});
test('null org never imports even with stale ready flag', () => {
    const s = actor(['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','BANK_IMPORT']); s.activeOrganizationId=null;
    expect(canImport(s,'banco')).toBe(false);
});
test('action does not substitute module VIEW or authorize direct navigation', () => {
    const s = actor(['IMPORT_CREATE','BANK_IMPORT']);
    expect(canVisitModule(s,'tab-bancos')).toBe(false); expect(canImport(s,'banco')).toBe(false);
    expect(canVisitModule(s,'invented-module')).toBe(false);
});
test('revoked VIEW clears operational state and selections and exits open module', () => {
    const s = actor([]); const reset = jest.fn(); s.tenantResetListeners.push(reset);
    pruneDeniedDatasets(s); expect(s.items).toEqual([]); expect(s.salaries).toBeNull(); expect(reset).toHaveBeenCalledTimes(1);
    const section = { id:'tab-bancos', classList:{ add:jest.fn() } };
    const link = { dataset:{tab:'tab-bancos'}, setAttribute:jest.fn() };
    const doc = { querySelector:()=>section, querySelectorAll:q=>q==='.tab-content' ? [section] : [link] };
    const navigate=jest.fn(); renderModuleAccess(s,doc,navigate);
    expect(navigate).toHaveBeenCalledWith('tab-access'); expect(section.inert).toBe(true); expect(link.hidden).toBe(true);
});
test.each([['upload','DOCUMENTS_UPLOAD'],['process','DOCUMENTS_OCR_PROCESS'],['verify','DOCUMENTS_OCR_VERIFY']])('OCR %s is independent', (action, cap) => {
    const s=actor([cap]); expect(canVisitModule(s,'tab-client-ocr')).toBe(false);
    expect(canVisitModule(s,'tab-movimientos-manuales')).toBe(true);
    for(const other of ['upload','process','verify']) expect(canOcr(s,other)).toBe(other===action);
    s.activeOrganizationId=null; expect(canOcr(s,action)).toBe(false);
});
test('foreign capabilities cannot enter MICA module contract', () => {
    const s=actor(['RECIPES_VIEW','INVENTORY_VIEW']);
    expect(isMicaCapability('RECIPES_VIEW','ORGANIZATION')).toBe(false);
    expect(canVisitModule(s,'tab-conciliador')).toBe(false);
});
