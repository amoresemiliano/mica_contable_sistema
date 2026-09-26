import { jest } from '@jest/globals';
import { readFileSync } from 'node:fs';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';
import { mountOperationalOrgSelectors, renderOperationalImportControls, renderOperationalHeader } from '../../src/js/components/operationalOrgSelector.js';

const rpc = jest.fn();
const query = () => ({ select() { return this; }, order: async () => ({ data: [], error: null }) });
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({ supabase: { rpc, from: query } }));
const { AppStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
let serverOrg, store;
const targets = ['NORTE', 'SUR'].map(id => ({ organization_id: id, organization_name: id }));
const context = () => ({ organization_id: serverOrg, organization_name: serverOrg, profile_name: 'Owner real', profile_scope: 'PLATFORM' });
const snapshot = org => ({ organization_id: org,
    records: [{ id: `${org}-invoice`, organization_id: org, record_type: 'ARCA_RECIBIDOS', total: 20 },
        { id: `${org}-perception`, organization_id: org, record_type: 'PERCEPCION', total: 1 }],
    financials: ['BANCO', 'SUELDO', 'SUELDO'].map((op, i) => ({ id: `${org}-${i}`, organization_id: org,
        operation_type: op, periodo: `2026-0${i + 1}`, normalized_payload: { monto: i, sueldoNeto: i } })),
    categories: [{ id: org + '-category', organization_id: org, name: org, is_active: true }],
    activities: [{ id: org + '-activity', organization_id: org, name: org, is_active: true }], rates: [] });
function server(name, args) {
    if (name === 'switch_superadmin_org_context') { serverOrg = args.p_org_id; return Promise.resolve({ error: null }); }
    if (name === 'get_my_operational_context') return Promise.resolve({ data: context() });
    if (name === 'get_my_effective_capabilities') return Promise.resolve({ data: ['ACCESS_ANY_ORG', 'GLOBAL_CATALOG_MANAGE'].map(code => ({ code, scope: 'PLATFORM', organization_id: null })) });
    if (name === 'list_operational_org_targets') return { range: async offset => ({ data: offset ? [] : targets }) };
    if (name === 'get_operational_snapshot') {
        const { records, financials, ...catalogs } = snapshot(args.p_org_id);
        return Promise.resolve({ data: catalogs });
    }
    if (name === 'get_operational_records_page' || name === 'get_operational_financials_page') {
        const key = name === 'get_operational_records_page' ? 'records' : 'financials';
        return Promise.resolve({ data: snapshot(args.p_org_id)[key]
            .filter(r => !args.p_after_id || r.id > args.p_after_id).sort((a, b) => a.id.localeCompare(b.id)) });
    }
    throw new Error('Unexpected RPC ' + name);
}
beforeEach(() => {
    rpc.mockReset().mockImplementation(server);
    serverOrg = null;
    store = new AppStore();
});

test('PLATFORM -> NORTE -> SUR -> PLATFORM replaces every dataset and retains all salary periods', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    expect(store.contextState).toBe('PLATFORM_READY');
    for (const org of ['NORTE', 'SUR']) {
        store.manualMovements = store.ocrHistory = store.importIssues = [{ id: 'old' }];
        await store.switchOrganizationContext(org);
        expect(store.items.map(r => r.id)).toEqual([org + '-invoice']);
        expect(store.perceptions.map(r => r.id)).toEqual([org + '-perception']);
        expect(store.bankTransactions).toHaveLength(1);
        expect(store.salariesList).toHaveLength(2);
        expect(store.taxCategories[0].organization_id).toBe(org);
        expect(store.economicActivities[0].organization_id).toBe(org);
        expect(store.isCatalogPlatformContext()).toBe(false);
        expect(store.manualMovements).toEqual([]);
        expect(store.ocrHistory).toEqual([]);
        expect(store.importIssues).toEqual([]);
    }
    await store.switchOrganizationContext(null);
    for (const key of ['items', 'perceptions', 'bankTransactions', 'salariesList', 'iibbRates']) expect(store[key]).toEqual([]);
    expect(store.salaries).toBeNull();
    expect(store.isCatalogPlatformContext()).toBe(true);
});

test('server-first: rejected switch preserves old context and records', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    await store.switchOrganizationContext('NORTE');
    const items = store.items;
    let rejectSwitch;
    rpc.mockImplementation((name, args) => name === 'switch_superadmin_org_context'
        ? new Promise(resolve => { rejectSwitch = resolve; }) : server(name, args));
    const pending = store.switchOrganizationContext('SUR');
    expect(store.activeOrganizationId).toBe('NORTE');
    expect(store.items).toBe(items);
    rejectSwitch({ error: { message: 'denied' } });
    await expect(pending).rejects.toThrow('denied');
    expect(store.activeOrganizationId).toBe('NORTE');
    expect(store.items).toBe(items);
    expect(store.contextState).toBe('TENANT_READY');
});

test('rehydration failure after confirmation never restores NORTE data under SUR', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    await store.switchOrganizationContext('NORTE');
    rpc.mockImplementation((name, args) => name === 'get_operational_snapshot'
        ? Promise.resolve({ error: { message: 'load failed' } }) : server(name, args));
    await expect(store.switchOrganizationContext('SUR')).rejects.toThrow('load failed');
    expect(store.activeOrganizationId).toBe('SUR');
    expect(store.contextState).toBe('ERROR');
    expect(store.items).toEqual([]);
    expect(store.salaries).toBeNull();
    await store.switchOrganizationContext(null);
    expect(store.contextState).toBe('PLATFORM_READY');
});

test('lost switch response reconciles committed server context and clears non-persistent state', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    await store.switchOrganizationContext('NORTE');
    store.manualMovements = store.ocrHistory = [{ id: 'NORTE-local' }];
    rpc.mockImplementation((name, args) => {
        if (name === 'switch_superadmin_org_context') {
            serverOrg = args.p_org_id;
            return Promise.resolve({ error: { message: 'Response lost after commit' } });
        }
        return server(name, args);
    });
    await store.switchOrganizationContext('SUR');
    expect(store.activeOrganizationId).toBe('SUR');
    expect(store.items.map(r => r.id)).toEqual(['SUR-invoice']);
    expect(store.manualMovements).toEqual([]);
    expect(store.ocrHistory).toEqual([]);
});

test('late response after logout cannot repopulate state; overlapping switches are rejected', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    let complete;
    rpc.mockImplementation((name, args) => name === 'get_operational_snapshot'
        ? new Promise(resolve => { complete = resolve; }) : server(name, args));
    const pending = store.switchOrganizationContext('NORTE');
    while (!complete) await Promise.resolve();
    await expect(store.switchOrganizationContext('SUR')).rejects.toThrow();
    store.endSession();
    complete({ data: snapshot('NORTE') });
    await pending;
    expect(store.items).toEqual([]);
    expect(store.sessionUserId).toBeNull();
    expect(store.contextState).toBe('SIGNED_OUT');
});

test('paged reader rejects foreign records instead of silently rendering them', async () => {
    rpc.mockImplementation((name, args) => name === 'get_operational_records_page'
        ? Promise.resolve({ data: snapshot('SUR').records }) : server(name, args));
    await expect(persistenceService.loadOperationalSnapshot('NORTE')).rejects.toThrow('Invalid tenant data');
});

test('short pages keep loading until empty and each request carries confirmed org and cursor', async () => {
    const rows = Array.from({ length: 3 }, (_, i) => ({ id: String(i + 1), organization_id: 'NORTE' }));
    rpc.mockImplementation((name, args) => Promise.resolve({ data: rows.filter(r => r.id > (args.p_after_id || '')).slice(0, 1) }));
    await expect(persistenceService.loadOperationalPages('get_operational_records_page', 'NORTE')).resolves.toEqual(rows);
    expect(rpc.mock.calls.map(([, args]) => args)).toEqual([null, '1', '2', '3'].map(p_after_id =>
        ({ p_org_id: 'NORTE', p_after_id, p_limit: 500 })));
});

test('repeated cursor fails instead of duplicating data or looping forever', async () => {
    rpc.mockResolvedValue({ data: [{ id: '1', organization_id: 'NORTE' }] });
    await expect(persistenceService.loadOperationalPages('get_operational_records_page', 'NORTE')).rejects.toThrow('cursor');
    expect(rpc).toHaveBeenCalledTimes(2);
});

test('historical page failure after switching leaves all tenant datasets empty', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    await store.switchOrganizationContext('NORTE');
    rpc.mockImplementation((name, args) => name === 'get_operational_records_page' && args.p_after_id
        ? Promise.resolve({ error: { message: 'Second page failed' } }) : server(name, args));
    await expect(store.switchOrganizationContext('SUR')).rejects.toThrow('Second page failed');
    expect(store.activeOrganizationId).toBe('SUR');
    expect(store.contextState).toBe('ERROR');
    for (const key of ['items', 'perceptions', 'bankTransactions', 'salariesList', 'taxCategories', 'iibbRates']) {
        expect(store[key]).toEqual([]);
    }
});

test('catalog refresh does not download historical pages', async () => {
    const result = await persistenceService.loadOperationalSnapshot('NORTE', { catalogOnly: true });
    expect(result.taxCategories[0].organization_id).toBe('NORTE');
    expect(result).not.toHaveProperty('items');
    expect(rpc.mock.calls.map(([name]) => name)).toEqual(['get_operational_snapshot']);
});

test('owner imports denied; tenant imports follow effective capability combinations', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    await store.switchOrganizationContext('NORTE');
    expect(store.canImportOperational('recibido')).toBe(false);
    store.permissions.platform.codes = [];
    store.currentUserRole = 'SUPERADMIN'; // Compatibility text must not authorize anything.
    store.permissions.organization = { loaded: true, orgId: 'NORTE', codes: ['IMPORT_CREATE', 'BANK_IMPORT'] };
    expect(store.canImportOperational('recibido')).toBe(true);
    expect(store.canImportOperational('banco')).toBe(true);
    expect(store.canImportOperational('sueldo')).toBe(false);
    const nodes = new Map();
    const document = { getElementById: id => { if (!nodes.has(id)) nodes.set(id, {}); return nodes.get(id); } };
    renderOperationalImportControls(store, document);
    expect(nodes.get('zone-bancos').hidden).toBe(false);
    store.permissions.platform.codes = ['ACCESS_ANY_ORG'];
    renderOperationalImportControls(store, document);
    expect(nodes.get('zone-bancos').hidden).toBe(true);
    expect(nodes.get('file-bancos').disabled).toBe(true);
});

test('real header uses session email, confirmed organization and actual platform preset', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com', user_metadata: { full_name: 'Google Name' } });
    await store.switchOrganizationContext('NORTE');
    store.currentUserRole = 'invented role';
    const nodes = { 'user-header-info': {}, 'current-entity-label': {} };
    renderOperationalHeader(store, { getElementById: id => nodes[id] });
    expect(nodes['user-header-info'].innerText).toBe('owner@example.com · NORTE · Owner real');
});

// Small DOM harness executes the real reusable component, not a copy of its behavior.
class Element {
    constructor(id = '') { this.id = id; this.children = []; this.parent = null; this.hidden = false; }
    get firstChild() { return this.children[0]; }
    append(...nodes) { for (const n of nodes) { if (n.parent) n.parent.children.splice(n.parent.children.indexOf(n), 1); n.parent = this; this.children.push(n); } }
    setAttribute() {}
    replaceChildren() { this.children = []; }
}
test('all selector instances share context, preserve current tab, hide for catalog-only capability', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    const sections = ['tab-bancos', 'tab-sueldos', 'tab-categorizacion'].map(id => new Element(id));
    sections[1].hidden = true;
    const document = { querySelectorAll: () => sections, createElement: () => new Element() };
    mountOperationalOrgSelectors(store, document);
    const selector = section => section.children[0].children[0].children[0];
    selector(sections[0]).value = 'NORTE';
    await selector(sections[0]).onchange();
    for (const section of sections) expect(selector(section).value).toBe('NORTE');
    expect(sections[0].hidden).toBe(false);
    expect(sections[1].hidden).toBe(true);
    store.permissions.platform.codes = ['CATALOG_ASSIGN_ANY_ORG'];
    store.notify();
    for (const section of sections) expect(section.children[0].children[0].hidden).toBe(true);
    await expect(store.switchOrganizationContext('SUR')).rejects.toThrow('ACCESS_ANY_ORG');
});

test('grid clears selections, filters, range and pagination', () => {
    const grid = new OperationalGrid({ moduleId: 'test' });
    grid.selectedRowIds.add('NORTE'); grid.searchQuery = 'secret'; grid.primaryFilter = 'debitos';
    grid.setCustomRange('2026-01-01', '2026-02-01'); grid.displayLimit = 500;
    grid.resetTenantState();
    expect(grid.getSelectedCount()).toBe(0); expect(grid.searchQuery).toBe('');
    expect(grid.startDate).toBe(''); expect(grid.primaryFilter).toBe('all'); expect(grid.displayLimit).toBe(10);
});

test('tenant preferences never reuse legacy or another user/organization history', async () => {
    const values = new Map([['mica_bank_templates', JSON.stringify({ legacy: true })]]);
    global.localStorage = { getItem: key => values.get(key) || null, setItem: (key, value) => values.set(key, value) };
    try {
        await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
        await store.switchOrganizationContext('NORTE');
        store.saveBankTemplate('private', { col: 1 });
        await store.switchOrganizationContext('SUR');
        expect(store.bankTemplates).toEqual({});
        await store.switchOrganizationContext('NORTE');
        expect(store.bankTemplates).toEqual({ private: { col: 1 } });
        await store.initializeSession({ id: 'another-owner', email: 'another@example.com' });
        expect(store.bankTemplates).toEqual({});
    } finally { delete global.localStorage; }
});

test('a pending write blocks switching until its complete operation finishes', async () => {
    await store.initializeSession({ id: 'owner', email: 'owner@example.com' });
    let complete;
    const write = jest.spyOn(persistenceService, 'upsertArcaCatalog').mockImplementation(() => new Promise(resolve => { complete = resolve; }));
    try {
        const pending = store.upsertArcaCatalog([{ arca_code: '1', name: 'A' }]);
        await expect(store.switchOrganizationContext('NORTE')).rejects.toThrow('operación en curso');
        complete(1);
        await pending;
        await store.switchOrganizationContext('NORTE');
        expect(store.contextState).toBe('TENANT_READY');
    } finally { write.mockRestore(); }
});

test('migration retains switch signature and separates operational discovery from catalog permissions', () => {
    const sql = readFileSync('sql/035_owner_operational_context.sql', 'utf8');
    expect(sql).toContain('switch_superadmin_org_context(p_org_id UUID)');
    expect(sql).toContain('RETURNS VOID');
    expect(sql).not.toContain('CATALOG_ASSIGN_ANY_ORG');
    expect(sql).not.toContain('SUPPORT_IMPERSONATE');
    expect(sql).not.toMatch(/CREATE OR REPLACE FUNCTION private.can_org/);
    for (const name of ['list_operational_org_targets', 'get_my_operational_context', 'get_operational_snapshot']) {
        expect(sql).toContain(`FUNCTION public.${name}`);
    }
});
