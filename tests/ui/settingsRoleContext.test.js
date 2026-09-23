import { jest } from '@jest/globals';
import { readFileSync } from 'node:fs';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';

const from = jest.fn();
const rpc = jest.fn();
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({ supabase: { from, rpc } }));
const { AppStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
const ui = readFileSync('src/js/ui.js', 'utf8');
const oeste = '1f5d071f-a09e-4825-9f12-88533383599e';
let store;

function renderCatalogControls() {
    const nodes = new Map();
    const document = { getElementById(id) {
        if (!nodes.has(id)) nodes.set(id, { style: {}, value: oeste, innerHTML: '', classList: { add() {}, remove() {} } });
        return nodes.get(id);
    } };
    const grid = () => new OperationalGrid({ moduleId: 'capabilities' });
    const methods = ui.slice(ui.indexOf('    static renderRecordActionToolbar('), ui.indexOf('    static renderImportIssues()'));
    const UI = new Function('appStore', 'document', 'window', 'taxCategoriesGrid', 'economicActivitiesGrid', 'iibbRatesGrid',
        `return class { static closeModal() {} ${methods} }`)(store, document, {}, grid(), grid(), grid());
    UI.renderSettings();
    return nodes;
}

test.each([
    ['PLATFORM_SUPERADMIN', 'SUPERADMIN', true, true, true, true],
    ['ACCOUNTING_SUPERADMIN', 'SUPERADMIN', false, true, false, true],
    ['no assignment permission', 'SUPERADMIN', true, false, true, false],
    ['no capabilities', 'SUPERADMIN', false, false, false, false],
    ['ADMIN even with platform booleans', 'ADMIN', true, true, false, false]
])('%s renders controls from effective capabilities', (label, role, manage, assign, seesManage, seesAssign) => {
    store.currentUserRole = role;
    store.activeOrganizationId = role === 'ADMIN' ? oeste : null;
    store.catalogCapabilities = { loaded: true, globalCatalogManage: manage, catalogAssignAnyOrg: assign, accessAnyOrg: false };
    const nodes = renderCatalogControls();
    for (const id of ['btn-import-arca-catalog', 'btn-create-global-category']) {
        expect(nodes.get(id).hidden).toBe(!seesManage);
        expect(nodes.get(id).disabled).toBe(!seesManage);
    }
    for (const id of ['toolbar-tax-categories', 'toolbar-economic-activities']) {
        expect(nodes.get(id).innerHTML.includes('Asignar')).toBe(seesAssign);
        expect(nodes.get(id).innerHTML.includes('Desasignar')).toBe(seesAssign);
        if (role === 'ADMIN') expect(nodes.get(id).innerHTML).toContain('Desactivar');
    }
});

test('loads server capabilities without identity arguments and never bypasses organization RLS', async () => {
    store.currentUserRole = 'SUPERADMIN';
    store.activeOrganizationId = null;
    rpc.mockReturnValue({ single: jest.fn().mockResolvedValue({ data: {
        global_catalog_manage: false, catalog_assign_any_org: true, access_any_org: true
    }, error: null }) });
    await store.loadMyCatalogCapabilities();
    expect(rpc).toHaveBeenCalledWith('get_my_catalog_capabilities');
    expect(store.canManageGlobalCatalog()).toBe(false);
    expect(store.canAssignCatalog()).toBe(true);
    expect(store.organizations).toEqual([]);
});

test.each(['error', 'malformed'])('%s loading capabilities fails closed and logs the failure', async mode => {
    store.currentUserRole = 'SUPERADMIN';
    store.activeOrganizationId = null;
    rpc.mockReturnValue({ single: jest.fn().mockResolvedValue(mode === 'error'
        ? { error: new Error('denied') } : { data: { global_catalog_manage: 'true' }, error: null }) });
    const log = jest.spyOn(console, 'error').mockImplementation(() => {});
    try {
        await store.loadMyCatalogCapabilities();
        expect(store.catalogCapabilities).toEqual({ loaded: false, globalCatalogManage: false, catalogAssignAnyOrg: false, accessAnyOrg: false });
        expect(renderCatalogControls().get('btn-import-arca-catalog').hidden).toBe(true);
        expect(store.canAssignCatalog()).toBe(false);
        expect(log).toHaveBeenCalled();
    } finally { log.mockRestore(); }
});

test('an old capability response cannot restore permissions after session reset', async () => {
    let resolve;
    rpc.mockReturnValue({ single: () => new Promise(done => { resolve = done; }) });
    const pending = store.loadMyCatalogCapabilities();
    store.resetCatalogCapabilities();
    resolve({ data: { global_catalog_manage: true, catalog_assign_any_org: true, access_any_org: true } });
    await pending;
    expect(store.catalogCapabilities.loaded).toBe(false);
});

test('SUPERADMIN without capabilities cannot invoke sensitive handlers directly', async () => {
    store.currentUserRole = 'SUPERADMIN';
    store.activeOrganizationId = null;
    store.resetCatalogCapabilities();
    for (const name of ['handleArcaFileSelected', 'handleArcaTextInputs', 'submitArcaCatalogForm', 'submitTaxCategoryForm',
        'editSingleTaxCategory', 'actionEditTaxCategory', 'actionCloneTaxCategory', 'toggleSingleTaxCategoryAssignment',
        'toggleSingleEconomicActivityAssignment', 'actionToggleTaxCategories', 'actionDeleteTaxCategories',
        'actionAssignEconomicActivities', 'actionUnassignEconomicActivities']) {
        const start = ui.indexOf(`window.${name} =`);
        const end = ui.indexOf('\n};', start) + 3;
        const window = {};
        new Function('window', 'appStore', ui.slice(start, end))(window, store);
        await window[name]();
    }
    expect(rpc).not.toHaveBeenCalled();
    await expect(store.upsertArcaCatalog([])).rejects.toThrow();
    await expect(store.assignEconomicActivityToOrg('id', oeste)).rejects.toThrow();
});

test('SQL rejection is propagated despite a previously granted frontend capability', async () => {
    store.currentUserRole = 'SUPERADMIN';
    store.activeOrganizationId = null;
    store.organizations = [{ id: oeste, name: 'Oeste' }];
    rpc.mockResolvedValue({ error: { message: 'permission revoked on server' } });
    await expect(store.assignEconomicActivityToOrg('id', oeste)).rejects.toThrow('permission revoked on server');
});

function query(data, error = null) {
    const q = { select: jest.fn(), eq: jest.fn(), order: jest.fn(), maybeSingle: jest.fn() };
    q.select.mockReturnValue(q);
    q.eq.mockReturnValue(q);
    q.order.mockResolvedValue({ data, error });
    q.maybeSingle.mockResolvedValue({ data, error });
    q.then = (resolve, reject) => Promise.resolve({ data, error }).then(resolve, reject);
    from.mockReturnValue(q);
    return q;
}

beforeEach(() => {
    jest.resetAllMocks();
    store = new AppStore();
    store.catalogCapabilities = { loaded: true, globalCatalogManage: true, catalogAssignAnyOrg: true, accessAnyOrg: false };
    store.currentUserRole = 'ADMIN';
    store.activeOrganizationId = oeste;
});

test('ADMIN resolves DEMO OESTE through an explicit RLS-filtered SELECT and updates the real header', async () => {
    const q = query({ id: oeste, name: 'DEMO OESTE' });
    await store.loadOrganizations();
    expect(q.select).toHaveBeenCalledWith('id, name');
    expect(q.eq).toHaveBeenCalledWith('id', oeste);
    expect(q.order).not.toHaveBeenCalled();
    expect(store.getActiveOrganizationName()).toBe('DEMO OESTE');
    const elements = { 'user-header-info': {}, 'current-entity-label': {} };
    const window = { currentSessionUserIdentity: 'Usuario', currentUserRole: 'ADMIN' };
    const code = ui.slice(ui.indexOf('window.updateUserHeaderDisplay ='), ui.indexOf('window.handleOrgContextChange ='));
    new Function('window', 'document', 'appStore', code)(window, { getElementById: id => elements[id] }, store);
    window.updateUserHeaderDisplay();
    expect(elements['current-entity-label'].innerText).toBe('Organización: DEMO OESTE');
    expect(elements['user-header-info'].innerText).not.toContain(oeste);
});

test('failed organization lookup clears stale names and never uses UUID or demo fixtures as a name', async () => {
    store.organizations = [{ id: oeste, name: 'Old name' }];
    query(null, { message: 'denied' });
    await expect(store.loadOrganizations()).rejects.toThrow('denied');
    expect(store.organizations).toEqual([]);
    expect(store.getActiveOrganizationName()).not.toContain(oeste);
});

test.each(['ADMIN', 'SUPERADMIN'])('%s sees global controls only in MICA context (actual renderSettings)', role => {
    store.currentUserRole = role;
    store.activeOrganizationId = role === 'SUPERADMIN' ? null : oeste;
    const elements = Object.fromEntries(['btn-import-arca-catalog', 'btn-create-global-category'].map(id => [id, {}]));
    const doc = { getElementById: id => elements[id] || null };
    const code = ui.slice(ui.indexOf('    static renderSettings()'), ui.indexOf('    static renderImportIssues()'));
    const grid = () => new OperationalGrid({ moduleId: 'test', defaultColumns: [], searchFields: [] });
    const UI = new Function('appStore', 'document', 'taxCategoriesGrid', 'economicActivitiesGrid', 'iibbRatesGrid',
        `return class { static closeModal() {} static renderRecordActionToolbar() {} ${code} }`)(store, doc, grid(), grid(), grid());
    UI.renderSettings();
    for (const el of Object.values(elements)) {
        expect(el.hidden).toBe(role !== 'SUPERADMIN');
        expect(el.disabled).toBe(role !== 'SUPERADMIN');
    }
    store.activeOrganizationId = oeste;
    UI.renderSettings();
    expect(elements['btn-import-arca-catalog'].hidden).toBe(true);
});

test('ADMIN cannot invoke global handlers directly, even without DOM controls', async () => {
    for (const name of ['handleArcaFileSelected', 'handleArcaTextInputs', 'submitArcaCatalogForm', 'submitTaxCategoryForm', 'editSingleTaxCategory', 'actionEditTaxCategory', 'actionCloneTaxCategory']) {
        const start = ui.indexOf(`window.${name} =`);
        const end = ui.indexOf('\n};', start) + 3;
        const window = {};
        new Function('window', 'appStore', ui.slice(start, end))(window, store);
        await window[name](); // Accessing the DOM or persistence here would throw.
    }
    await expect(store.upsertArcaCatalog([])).rejects.toThrow('SUPERADMIN');
    await expect(store.createTaxCategory({ name: 'Forbidden' })).rejects.toThrow('SUPERADMIN');
    expect(rpc).not.toHaveBeenCalled();
});

test('ADMIN loads only organization assignments, using arca_code', async () => {
    const q = query([{ organization_id: oeste, is_assigned: true, is_active: false, activity: { id: 'act', name: 'Activity', arca_code: '011111' } }]);
    await store.loadEconomicActivities();
    expect(from).toHaveBeenCalledTimes(1);
    expect(from).toHaveBeenCalledWith('eco_org_economic_activities');
    expect(q.eq).toHaveBeenCalledWith('organization_id', oeste);
    expect(q.select.mock.calls[0][0]).not.toContain('afip_code');
    expect(store.displayedEconomicActivities[0]).toMatchObject({ id: 'act', organization_id: oeste, arca_code: '011111', is_active: false });
    expect(store.economicActivities).toEqual([]);
    expect(store.globalEconomicActivities).toEqual([]);
});

test('ADMIN loads only assigned categories and can reactivate only that subset', async () => {
    const q = query([{ id: 'assignment', organization_id: oeste, is_assigned: true, is_active: false, category: { id: 'cat', name: 'Category' } }]);
    await store.loadTaxCategories();
    expect(from).toHaveBeenCalledWith('eco_org_tax_categories');
    expect(q.eq).toHaveBeenCalledWith('organization_id', oeste);
    rpc.mockResolvedValue({ error: null });
    await store.setTaxCategoriesActive(['cat'], true);
    expect(rpc).toHaveBeenCalledWith('activate_tax_category', { p_category_id: 'cat' });
    rpc.mockClear();
    await expect(store.setTaxCategoriesActive(['cat', 'foreign'], true)).rejects.toThrow('asignaciones');
    await expect(store.assignTaxCategoryToOrg('cat', 'other-org')).rejects.toThrow('SUPERADMIN');
    expect(rpc).not.toHaveBeenCalled();
});

test('global category creation does not implicitly assign to a tenant', async () => {
    rpc.mockResolvedValue({ data: 'new-category', error: null });
    await persistenceService.createTaxCategory({ name: 'Global' });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0][0]).toBe('create_global_tax_category');
});

test('ADMIN can toggle an assigned activity but cannot introduce another activity or target', async () => {
    query([{ organization_id: oeste, is_assigned: true, is_active: false, activity: { id: 'act', name: 'Activity', arca_code: '011111' } }]);
    await store.loadEconomicActivities();
    rpc.mockResolvedValue({ error: null });
    await store.setEconomicActivitiesActive(['act'], true);
    await store.setEconomicActivitiesActive(['act'], false);
    expect(rpc).toHaveBeenCalledWith('activate_economic_activity', { p_activity_id: 'act' });
    expect(rpc).toHaveBeenCalledWith('deactivate_economic_activity', { p_activity_id: 'act' });
    rpc.mockClear();
    await expect(store.setEconomicActivitiesActive(['act', 'foreign'], true)).rejects.toThrow('asignaciones');
    await expect(store.unassignEconomicActivityFromOrg('act', 'other-org')).rejects.toThrow('SUPERADMIN');
    expect(rpc).not.toHaveBeenCalled();
});

test('SUPERADMIN in MICA can create/import globally and assign to an explicit organization', async () => {
    store.currentUserRole = 'SUPERADMIN';
    store.activeOrganizationId = null;
    store.organizations = [{ id: oeste, name: 'DEMO OESTE' }];
    query([]);
    rpc.mockResolvedValue({ data: 'new-category', error: null });
    await store.createTaxCategory({ name: 'Global' });
    expect(rpc.mock.calls[0][0]).toBe('create_global_tax_category');
    expect(rpc).toHaveBeenCalledTimes(1);
    rpc.mockResolvedValue({ data: 1, error: null });
    await expect(store.upsertArcaCatalog([{ arca_code: '011111', name: 'Activity' }])).resolves.toBe(1);
    await store.assignTaxCategoryToOrg('new-category', oeste);
    await store.assignEconomicActivityToOrg('act', oeste);
    expect(rpc).toHaveBeenCalledWith('assign_tax_category_to_org', { p_category_id: 'new-category', p_target_org_id: oeste });
    expect(rpc).toHaveBeenCalledWith('assign_economic_activity_to_org', { p_activity_id: 'act', p_target_org_id: oeste });
});

test('ADMIN without an active organization does not query the global catalogs', async () => {
    store.activeOrganizationId = null;
    await store.loadOrganizations();
    await store.loadTaxCategories();
    await store.loadEconomicActivities();
    expect(from).not.toHaveBeenCalled();
    expect(store.taxCategories).toEqual([]);
    expect(store.displayedEconomicActivities).toEqual([]);
});

test('activity queries contain no afip_code references', () => {
    for (const path of ['src/js/store.js', 'src/js/core/services/persistenceService.js', 'src/js/ui.js']) {
        expect(readFileSync(path, 'utf8')).not.toContain('afip_code');
    }
});

describe.each([
    ['activities', 'loadEconomicActivities', 'displayedEconomicActivities', 'activity', 'activity_id', 'setEconomicActivitiesActive', 'economic_activity', 'assignEconomicActivityToOrg', 'unassignEconomicActivityFromOrg'],
    ['categories', 'loadTaxCategories', 'taxCategories', 'category', 'category_id', 'setTaxCategoriesActive', 'tax_category', 'assignTaxCategoryToOrg', 'unassignTaxCategoryFromOrg']
])('%s assignment boundary', (kind, load, rows, joined, key, activate, rpcKind, assign, unassign) => {
    test('tenant excludes unassigned rows and retains inactive assignments', async () => {
        const q = query([
            { organization_id: oeste, is_assigned: true, is_active: false, [joined]: { id: 'allowed', name: 'Inactive' } },
            { organization_id: oeste, is_assigned: false, is_active: true, [joined]: { id: 'revoked', name: 'Revoked' } }
        ]);
        await store[load]();
        expect(q.eq).toHaveBeenCalledWith('organization_id', oeste);
        expect(q.eq).toHaveBeenCalledWith('is_assigned', true);
        expect(q.eq).not.toHaveBeenCalledWith('is_active', true);
        expect(store[rows].map(row => row.id)).toEqual(['allowed']);
        expect(store[rows][0].is_active).toBe(false);
        await expect(store[activate](['revoked'], true)).rejects.toThrow('ADMIN');
        expect(rpc).not.toHaveBeenCalled();
    });

    test('tenant activation and deactivation use distinct RPCs without a client-provided organization', async () => {
        query([{ organization_id: oeste, is_assigned: true, is_active: true, [joined]: { id: 'allowed', name: 'Assigned' } }]);
        await store[load]();
        rpc.mockResolvedValue({ error: null });
        await store[activate](['allowed'], false);
        await store[activate](['allowed'], true);
        expect(rpc).toHaveBeenCalledWith(`deactivate_${rpcKind}`, { [`p_${key}`]: 'allowed' });
        expect(rpc).toHaveBeenCalledWith(`activate_${rpcKind}`, { [`p_${key}`]: 'allowed' });
        rpc.mockClear();
        await expect(store[assign]('allowed', oeste)).rejects.toThrow('SUPERADMIN');
        await expect(store[unassign]('allowed', oeste)).rejects.toThrow('SUPERADMIN');
        store[rows][0].organization_id = 'other-org';
        await expect(store[activate](['allowed'], true)).rejects.toThrow('ADMIN');
        expect(rpc).not.toHaveBeenCalled();
    });

    test('SUPERADMIN assigns/unassigns only to a recognized target and cannot use tenant activation', async () => {
        store.currentUserRole = 'SUPERADMIN';
        store.activeOrganizationId = null;
        store.organizations = [{ id: oeste, name: 'DEMO OESTE' }];
        query([]);
        rpc.mockResolvedValue({ error: null });
        await store[assign]('global-item', oeste);
        await store[unassign]('global-item', oeste);
        expect(rpc).toHaveBeenCalledWith(`assign_${rpcKind}_to_org`, { [`p_${key}`]: 'global-item', p_target_org_id: oeste });
        expect(rpc).toHaveBeenCalledWith(`unassign_${rpcKind}_from_org`, { [`p_${key}`]: 'global-item', p_target_org_id: oeste });
        rpc.mockClear();
        await expect(store[assign]('global-item', 'unknown-org')).rejects.toThrow('destino');
        await expect(store[activate](['global-item'], true)).rejects.toThrow('ADMIN');
        expect(rpc).not.toHaveBeenCalled();
    });
});
