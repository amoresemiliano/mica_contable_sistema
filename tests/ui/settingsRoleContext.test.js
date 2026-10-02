import { renderOperationalHeader } from '../../src/js/components/operationalOrgSelector.js';
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
function grantPlatform(manage = true, assign = true) {
    store.permissions.platform = { loaded: true, codes: [manage && 'GLOBAL_CATALOG_MANAGE', assign && 'CATALOG_ASSIGN_ANY_ORG'].filter(Boolean) };
    store.catalogAssignmentTargets = [{ organization_id: oeste, organization_name: 'Oeste' }];
}

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
    ['USER with platform grants', 'USER', true, true, true, true]
])('%s renders controls from effective capabilities', (label, role, manage, assign, seesManage, seesAssign) => {
    store.currentUserRole = role;
    store.activeOrganizationId = role === 'ADMIN' ? oeste : null;
    grantPlatform(manage, assign);
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
    grantPlatform();
    store.activeOrganizationId = null;
    rpc.mockImplementation(name => Promise.resolve({ data: name === 'list_catalog_assignment_targets' ? [] : ['CATALOG_ASSIGN_ANY_ORG', 'ACCESS_ANY_ORG'].map(code => ({ code, scope: 'PLATFORM', organization_id: null })), error: null }));
    await store.loadMyCatalogCapabilities();
    expect(rpc).toHaveBeenCalledWith('get_my_effective_capabilities', { p_org_id: null });
    expect(rpc).toHaveBeenCalledWith('list_catalog_assignment_targets');
    expect(store.canManageGlobalCatalog()).toBe(false);
    expect(store.canAssignCatalog()).toBe(true);
    expect(store.organizations).toEqual([]);
});

test.each(['error', 'malformed'])('%s loading capabilities fails closed and logs the failure', async mode => {
    store.strictLoads = false; // The interactive loader logs; the atomic hydration draft propagates errors.
    store.currentUserRole = 'SUPERADMIN';
    grantPlatform();
    store.activeOrganizationId = null;
    rpc.mockResolvedValue(mode === 'error' ? { error: new Error('denied') } : { data: { invalid: true }, error: null });
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
    rpc.mockImplementation(() => new Promise(done => { resolve = done; }));
    const pending = store.loadMyCatalogCapabilities();
    store.resetCatalogCapabilities();
    resolve({ data: [{ code: 'GLOBAL_CATALOG_MANAGE', scope: 'PLATFORM', organization_id: null }] });
    await pending;
    expect(store.catalogCapabilities.loaded).toBe(false);
});

test('SUPERADMIN without capabilities cannot invoke sensitive handlers directly', async () => {
    store.currentUserRole = 'SUPERADMIN';
    grantPlatform();
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
    grantPlatform();
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

test('permissions are scoped and independent of compatibility role and template', () => {
    store.currentUserRole = 'USER';
    expect(store.canActivateCatalog('activity')).toBe(true);
    expect(store.hasCapability('CATALOG_ACTIVITY_MANAGE', { scope: 'ORGANIZATION', orgId: 'other' })).toBe(false);
    expect(store.canManageGlobalCatalog()).toBe(false);
    grantPlatform();
    expect(store.canManageGlobalCatalog()).toBe(true);
    expect(store.canAssignCatalog()).toBe(true);
    store.setUserRole('SUPERADMIN');
    expect(store.canAssignCatalog()).toBe(false);
    expect(store.canActivateCatalog('activity')).toBe(false);
});

test('rejected server context switch preserves local context, permissions and data', async () => {
    store.permissions.platform = { loaded: true, codes: ['ACCESS_ANY_ORG'] };
    const before = store.permissions;
    store.taxCategories = [{ id: 'preserve' }];
    rpc.mockImplementation(async name => name === 'get_my_operational_context'
        ? { data: { organization_id: oeste, organization_name: 'Oeste' } } : { error: { message: 'context denied' } });
    await expect(store.switchOrganizationContext('other')).rejects.toThrow('context denied');
    expect(store.activeOrganizationId).toBe(oeste);
    expect(store.permissions).toBe(before);
    expect(store.taxCategories).toEqual([{ id: 'preserve' }]);
});

test('successful context switch reloads permissions after server confirmation', async () => {
    store.permissions.platform = { loaded: true, codes: ['ACCESS_ANY_ORG'] };
    const events = [];
    rpc.mockImplementation(async name => {
        events.push([name, store.activeOrganizationId]);
        if (name === 'get_my_operational_context') return { data: { organization_id: 'other', organization_name: 'Other' } };
        if (name === 'get_operational_snapshot') return { data: { organization_id: 'other', categories: [], activities: [], rates: [] } };
        if (name === 'get_operational_records_page' || name === 'get_operational_financials_page') return { data: [] };
        return { data: name === 'get_my_effective_capabilities' ? [] : null, error: null };
    });
    query([]);
    await store.switchOrganizationContext('other');
    expect(events[0]).toEqual(['switch_superadmin_org_context', oeste]);
    expect(events).toContainEqual(['get_my_effective_capabilities', 'other']);
    expect(store.permissions.organization.orgId).toBe('other');
    expect(store.canActivateCatalog('activity')).toBe(false);
});

test('store has exactly one role setter and role display predicate', () => {
    const source = readFileSync('src/js/store.js', 'utf8');
    expect(source.match(/^    setUserRole\(role\)/gm)).toHaveLength(1);
    expect(source.match(/^    isSuperAdmin\(\)/gm)).toHaveLength(1);
});

beforeEach(() => {
    jest.resetAllMocks();
    store = new AppStore();
    store.strictLoads = true; // Unit-test legacy catalog mappings independently of session bootstrap.
    store.permissions.organization = { loaded: true, orgId: oeste, codes: ['CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE'] };
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
    new Function('window', 'document', 'appStore', 'renderOperationalHeader', code)(window, { getElementById: id => elements[id] }, store, renderOperationalHeader);
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
    if (role === 'SUPERADMIN') grantPlatform();
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
    await expect(store.upsertArcaCatalog([])).rejects.toThrow('capability required');
    await expect(store.createTaxCategory({ name: 'Forbidden' })).rejects.toThrow('capability required');
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
    await expect(store.assignTaxCategoryToOrg('cat', 'other-org')).rejects.toThrow('capability required');
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
    await expect(store.unassignEconomicActivityFromOrg('act', 'other-org')).rejects.toThrow('capability required');
    expect(rpc).not.toHaveBeenCalled();
});

test('SUPERADMIN in MICA can create/import globally and assign to an explicit organization', async () => {
    store.currentUserRole = 'SUPERADMIN';
    grantPlatform();
    store.activeOrganizationId = null;
    store.organizations = [{ id: oeste, name: 'DEMO OESTE' }];
    query([]);
    rpc.mockImplementation(name => name === 'list_catalog_assignment_state' ? { range: jest.fn().mockResolvedValue({ data: [], error: null }) } : Promise.resolve({ data: 'new-category', error: null }));
    await store.createTaxCategory({ name: 'Global' });
    expect(rpc.mock.calls[0][0]).toBe('create_global_tax_category');
    expect(rpc).toHaveBeenCalledWith('list_catalog_assignment_state', { p_catalog_type: 'category' });
    rpc.mockImplementation(name => name === 'list_catalog_assignment_state' ? { range: jest.fn().mockResolvedValue({ data: [], error: null }) } : Promise.resolve({ data: 1, error: null }));
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
        await expect(store[activate](['revoked'], true)).rejects.toThrow('asignaciones');
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
        await expect(store[assign]('allowed', oeste)).rejects.toThrow('capability required');
        await expect(store[unassign]('allowed', oeste)).rejects.toThrow('capability required');
        store[rows][0].organization_id = 'other-org';
        await expect(store[activate](['allowed'], true)).rejects.toThrow('asignaciones');
        expect(rpc).not.toHaveBeenCalled();
    });

    test('SUPERADMIN assigns/unassigns only to a recognized target and cannot use tenant activation', async () => {
        store.currentUserRole = 'SUPERADMIN';
    grantPlatform();
        store.activeOrganizationId = null;
        store.organizations = [{ id: oeste, name: 'DEMO OESTE' }];
        query([]);
        rpc.mockImplementation(name => name === 'list_catalog_assignment_state' ? { range: jest.fn().mockResolvedValue({ data: [], error: null }) } : Promise.resolve({ data: null, error: null }));
        await store[assign]('global-item', oeste);
        await store[unassign]('global-item', oeste);
        expect(rpc).toHaveBeenCalledWith(`assign_${rpcKind}_to_org`, { [`p_${key}`]: 'global-item', p_target_org_id: oeste });
        expect(rpc).toHaveBeenCalledWith(`unassign_${rpcKind}_from_org`, { [`p_${key}`]: 'global-item', p_target_org_id: oeste });
        rpc.mockClear();
        await expect(store[assign]('global-item', 'unknown-org')).rejects.toThrow('destino');
        await expect(store[activate](['global-item'], true)).rejects.toThrow('asignaciones');
        expect(rpc).not.toHaveBeenCalled();
    });
});


test.each([
    ['activity', 'loadEconomicActivities', 'displayedEconomicActivities', 'eco_economic_activities'],
    ['category', 'loadTaxCategories', 'taxCategories', 'eco_tax_categories']
])('%s global state comes from catalog RPC without transversal assignment SELECT', async (kind, load, rows, table) => {
    store.currentUserRole = 'USER';
    grantPlatform(false, true);
    store.activeOrganizationId = null;
    store.organizations = []; // Operational RLS may legitimately expose no organizations.
    query([{ id: 'assigned', name: 'One' }, { id: 'withdrawn', name: 'Two' }]);
    const range = jest.fn()
        .mockResolvedValueOnce({ data: [
            { organization_id: oeste, item_id: 'assigned', is_assigned: true, is_active: false },
            { organization_id: oeste, item_id: 'withdrawn', is_assigned: false, is_active: true }
        ], error: null })
        .mockResolvedValueOnce({ data: [], error: null });
    rpc.mockReturnValue({ range });
    await store[load]();
    expect(from.mock.calls).toEqual([[table]]);
    expect(rpc).toHaveBeenCalledWith('list_catalog_assignment_state', { p_catalog_type: kind });
    expect(store[rows][0].assignedOrganizationIds).toEqual([oeste]);
    expect(store[rows][1].assignedOrganizationIds).toEqual([]);
    expect(store[rows][0].assignedState).toBe('Oeste');
    expect(range.mock.calls).toEqual([[0, 499], [2, 501]]);
});

test('catalog state service preserves all response pages and propagates server denial', async () => {
    const range = jest.fn()
        .mockResolvedValueOnce({ data: [{ organization_id: oeste, item_id: 'a', is_assigned: true, is_active: true }], error: null })
        .mockResolvedValueOnce({ data: [{ organization_id: oeste, item_id: 'b', is_assigned: true, is_active: false }], error: null })
        .mockResolvedValueOnce({ data: [], error: null });
    rpc.mockReturnValue({ range });
    await expect(persistenceService.listCatalogAssignmentState('activity')).resolves.toHaveLength(2);
    expect(range.mock.calls).toEqual([[0, 499], [1, 500], [2, 501]]);
    range.mockResolvedValueOnce({ data: null, error: { message: 'catalog permission denied' } });
    await expect(persistenceService.listCatalogAssignmentState('activity')).rejects.toThrow('catalog permission denied');
});

test('catalog management without assignment capability never fetches assignment metadata', async () => {
    grantPlatform(true, false);
    store.activeOrganizationId = null;
    query([{ id: 'cat', name: 'Global' }]);
    await store.loadTaxCategories();
    expect(store.taxCategories).toHaveLength(1);
    expect(store.taxCategories[0].assignedOrganizationIds).toEqual([]);
    expect(rpc).not.toHaveBeenCalled();
});
