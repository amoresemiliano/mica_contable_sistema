import { jest } from '@jest/globals';
import { createAdministrationView } from '../../src/js/components/administration.js';

const walk = n => [n, ...(n.children || []).filter(c => typeof c === 'object').flatMap(walk)];

function node(tag) {
    return {
        tag, children: [], events: {}, value: '', className: '', textContent: '', innerHTML: '',
        append(...children) { this.children.push(...children); },
        replaceChildren(...children) { this.children = children; },
        setAttribute(key, value) { this[key] = value; },
        getAttribute(key) { return this[key]; },
        addEventListener(key, fn) { this.events[key] = fn; },
        focus() { global.document.activeElement = this; },
        close: jest.fn(), remove: jest.fn(), showModal: jest.fn(),
        closest() { return null; }, getClientRects() { return [1]; },
        querySelectorAll() { return walk(this).filter(n => ['button', 'input', 'select'].includes(n.tag)); },
        contains(target) { return walk(this).includes(target); }
    };
}

let oldDocument;
beforeEach(() => {
    oldDocument = global.document;
    global.document = {
        createElement: node,
        createElementNS: (_namespace, tag) => node(tag),
        activeElement: null,
        addEventListener: jest.fn(),
        getElementById: jest.fn(id => node(id))
    };
});
afterEach(() => { global.document = oldDocument; });

const data = () => ({
    rights: { operational_admin: true, organizations: true, create_organization: true, update_organization: true, archive_organization: true, users: true, memberships: true },
    organizations: [
        { id: 'norte', name: 'Empresa Norte', tax_id: '30111111118', is_active: true, phone: '011-4444-5555', email: 'info@norte.ar', contact_person: 'Carlos', website: 'norte.ar', address: 'Av. Corrientes 1000' },
        { id: 'sur', name: 'Empresa Sur', tax_id: '30222222228', is_active: true }
    ],
    users: [
        { id: 'user1', email: 'carlos@norte.ar', is_active: true },
        { id: 'user2', email: 'ana@norte.ar', is_active: true }
    ],
    presets: [{ id: 'admin-preset', name: 'Administrador', scope: 'ORGANIZATION', is_active: true }],
    capabilities: [], platform_roles: [],
    memberships: [{ user_profile_id: 'user1', organization_id: 'norte', role_template_id: 'admin-preset', is_active: true }],
    scopes: [], overrides: []
});

describe('DEV-ADMIN-UX-01 Administration UX & Persistent Header', () => {

    test('Configuración defaults to Empresas and renders persistent header', async () => {
        const root = node('root'), snapshot = data();
        const store = { sessionUserId: 'admin', contextGeneration: 1, contextState: 'TENANT_READY', activeOrganizationId: 'norte', subscribe() {}, hasCapability: () => true };
        
        await createAdministrationView(root, store, { read: async () => snapshot }).load();

        const tabs = walk(root).filter(n => n.role === 'tab').map(n => n.textContent);
        expect(tabs).toEqual(['Empresas', 'Usuarios', 'Categorización']);
        expect(walk(root).some(n => n.textContent === '+ Nueva Empresa')).toBe(true);
        expect(walk(root).some(n => n.name === 'operational-company')).toBe(true);
    });

    test('Empresas table renders action icons (View, Edit, Archive)', async () => {
        const root = node('root'), snapshot = data();
        const store = { sessionUserId: 'admin', contextGeneration: 1, contextState: 'TENANT_READY', activeOrganizationId: 'norte', subscribe() {}, hasCapability: () => true };
        
        await createAdministrationView(root, store, { read: async () => snapshot }).load();

        const buttons = walk(root).filter(n => n.tag === 'button' && n.className?.includes('mica-action-btn'));
        expect(buttons.length).toBeGreaterThanOrEqual(3);
        const labels = buttons.map(b => b['aria-label']);
        expect(labels.some(l => l.includes('Ver detalle de Empresa Norte'))).toBe(true);
        expect(labels.some(l => l.includes('Editar Empresa Norte'))).toBe(true);
        expect(labels.some(l => l.includes('Archivar Empresa Norte'))).toBe(true);
    });

    test('View company detail action renders profile fields', async () => {
        const root = node('root'), snapshot = data();
        const store = { sessionUserId: 'admin', contextGeneration: 1, contextState: 'TENANT_READY', activeOrganizationId: 'norte', subscribe() {}, hasCapability: () => true };
        
        await createAdministrationView(root, store, { read: async () => snapshot }).load();

        const viewBtn = walk(root).find(n => n.className?.includes('mica-action-btn') && n['aria-label']?.includes('Ver detalle de Empresa Norte'));
        expect(viewBtn).toBeDefined();
        viewBtn.onclick();

        const texts = walk(root).map(n => n.textContent || '').join(' ');
        expect(texts).toContain('Empresa Norte');
        expect(texts).toContain('30111111118');
        expect(texts).toContain('011-4444-5555');
        expect(texts).toContain('info@norte.ar');
        expect(texts).toContain('Carlos');
        expect(texts).toContain('norte.ar');
        expect(texts).toContain('Av. Corrientes 1000');
    });

    test('Categorización exposes three distinct sub-views (Categorías, Actividades, Impuestos)', async () => {
        const root = node('root'), snapshot = data();
        const store = { sessionUserId: 'admin', contextGeneration: 1, contextState: 'TENANT_READY', activeOrganizationId: 'norte', subscribe() {}, hasCapability: () => true };
        
        const view = createAdministrationView(root, store, { read: async () => snapshot });
        await view.load({ section: 'Categorización' });

        const subTabs = walk(root).filter(n => n.className?.includes('mica-admin-subnav-btn')).map(n => n.textContent);
        expect(subTabs).toEqual(['Categorías', 'Actividades', 'Impuestos']);
    });
});

const primaryTabs = root => walk(root).filter(n => n.role === 'tab').map(n => n.textContent);
const click = (root, text) => walk(root).find(n => n.tag === 'button' && n.textContent === text).onclick();
const storeFixture = org => ({ sessionUserId: 'admin', contextGeneration: 1, contextState: org ? 'TENANT_READY' : 'PLATFORM_READY',
    activeOrganizationId: org, pendingOperations: 0, subscribe(fn) { this.listener = fn; }, hasCapability: () => true,
    reloadOperationalContext: jest.fn(async () => {}) });
const platformRights = { organizations: true, create_organization: true, update_organization: true, archive_organization: true,
    users: true, global_users: true, presets: true, global_presets: true, assignments: true, memberships: true };

test.each(['operational', 'platform'])('%s admin shares Empresas, Usuarios and Categorización and defaults to Empresas', async kind => {
    const root = node('root'), snapshot = data(), store = storeFixture('norte');
    if (kind === 'platform') snapshot.rights = { ...platformRights };
    const rightsBefore = { ...snapshot.rights };
    await createAdministrationView(root, store, { read: async () => snapshot }).load();
    expect(primaryTabs(root)).toEqual(['Empresas', 'Usuarios', 'Categorización']);
    expect(walk(root).find(n => n.role === 'tabpanel').actionHeader.children[0].textContent).toBe('Empresas');
    expect(walk(root).some(n => n['aria-label'] === 'Editar Empresa Norte')).toBe(true);
    expect(snapshot.rights).toEqual(rightsBefore);
    click(root, 'Usuarios');
    expect(walk(root).some(n => n.textContent === 'Permisos avanzados')).toBe(kind === 'platform');
    expect(walk(root).filter(n => n.type === 'checkbox')).toHaveLength(0);
    if (kind === 'platform') {
        click(root, 'Permisos avanzados');
        expect(walk(root).find(n => n.className === 'mica-admin-advanced-nav').children.map(n => n.textContent))
            .toEqual(['Usuarios de plataforma', 'Roles y permisos', 'Asignaciones']);
        expect(primaryTabs(root)).toEqual(['Empresas', 'Usuarios', 'Categorización']);
    }
});

test.each(['create', 'edit'])('platform company %s persists all profile fields, including clearing existing values', async mode => {
    const oldFormData = global.FormData;
    global.FormData = class {
        constructor(form) { this.values = new Map(walk(form).filter(n => n.name).map(n => [n.name, n.value])); }
        get(key) { return this.values.get(key); }
    };
    try {
        const root = node('root'), snapshot = data(), store = storeFixture('norte');
        snapshot.rights = { ...platformRights };
        const service = { read: jest.fn(async () => snapshot), apply: jest.fn(async () => 'saved') };
        await createAdministrationView(root, store, service).load();
        if (mode === 'create') click(root, '+ Nueva Empresa');
        else walk(root).find(n => n['aria-label'] === 'Editar Empresa Norte').onclick();
        const form = walk(root).find(n => n.tag === 'form');
        const payload = mode === 'edit' ? { id: 'norte' } : {};
        for (const field of ['name', 'legal_name', 'trade_name', 'tax_id', 'phone', 'email', 'contact_person', 'website', 'address']) {
            const input = walk(form).find(n => n.name === field);
            expect(input).toBeDefined();
            input.value = field === 'phone' ? '' : 'value-' + field;
            payload[field] = input.value;
        }
        await form.events.submit({ preventDefault() {} });
        expect(service.apply).toHaveBeenCalledWith('organization', payload);
        expect(store.reloadOperationalContext).toHaveBeenCalledTimes(1);
        expect(service.read).toHaveBeenCalledTimes(2);
    } finally { global.FormData = oldFormData; }
});

test.each(['operational', 'platform'])('%s categorization retains cards, header and active organization across route changes', async kind => {
    const root = node('root'), snapshot = data(), store = storeFixture('norte');
    if (kind === 'platform') snapshot.rights = { ...platformRights };
    const cards = new Map(['card-tax-categories', 'card-economic-activities', 'card-iibb-rates', 'card-iva-rates'].map(id => [id, node(id)]));
    document.getElementById = jest.fn(id => cards.get(id));
    store.loadTaxCategories = jest.fn(); store.loadEconomicActivities = jest.fn(); store.loadIibbRates = jest.fn();
    const view = createAdministrationView(root, store, { read: async () => snapshot });
    await view.load({ section: 'Categorización' });
    const body = () => walk(root).find(n => n.id === 'mica-categorizacion-subview');
    expect(body().children).toEqual([cards.get('card-tax-categories')]);
    click(root, 'Actividades'); expect(body().children).toEqual([cards.get('card-economic-activities')]);
    click(root, 'Impuestos'); expect(body().children).toEqual([cards.get('card-iibb-rates'), cards.get('card-iva-rates')]);
    // Detached card IDs are no longer discoverable; reuse the original nodes.
    document.getElementById = jest.fn(() => null);
    click(root, 'Categorías'); expect(body().children).toEqual([cards.get('card-tax-categories')]);
    expect(walk(root).find(n => n.name === 'operational-company').value).toBe('norte');
    await view.load({ section: 'Empresas' });
    expect(walk(root).find(n => n.role === 'tabpanel').actionHeader.children[0].textContent).toBe('Empresas');
});

test('Users defaults to the selected organization and never substitutes global users for an empty membership list', async () => {
    const root = node('root'), snapshot = data(); snapshot.rights = { ...platformRights }; snapshot.memberships = [];
    const view = createAdministrationView(root, storeFixture('norte'), { read: async () => snapshot });
    await view.load({ section: 'Usuarios' });
    expect(walk(root).filter(n => n.tag === 'td').map(n => n.textContent)).toEqual(['Sin resultados.']);
    expect(walk(root).some(n => n.className === 'mica-admin-advanced')).toBe(false);
});

test('selector switches confirmed organization and reads the new context without losing primary navigation', async () => {
    const root = node('root'), snapshot = data(), store = storeFixture('norte');
    const read = jest.fn(async () => snapshot);
    store.switchOrganizationContext = jest.fn(async id => { store.activeOrganizationId = id; store.contextGeneration++; });
    await createAdministrationView(root, store, { read }).load();
    const selector = walk(root).find(n => n.name === 'operational-company');
    selector.value = 'sur'; await selector.onchange();
    expect(store.switchOrganizationContext).toHaveBeenCalledWith('sur');
    expect(read).toHaveBeenLastCalledWith('sur', '');
    expect(walk(root).find(n => n.name === 'operational-company').value).toBe('sur');
    expect(primaryTabs(root)).toEqual(['Empresas', 'Usuarios', 'Categorización']);
});

test('aggregate organization visibility never substitutes for individual create, update or archive rights', async () => {
    const root = node('root'), snapshot = data(); snapshot.rights = { organizations: true, users: true };
    await createAdministrationView(root, storeFixture('norte'), { read: async () => snapshot }).load();
    expect(walk(root).filter(n => n.tag === 'button' && n.className === 'mica-action-btn').map(n => n.title)).toEqual(['Ver detalle', 'Ver detalle']);
    expect(walk(root).some(n => n.textContent === '+ Nueva Empresa')).toBe(false);
    click(root, 'Usuarios'); expect(walk(root).some(n => n.textContent === 'Permisos avanzados')).toBe(false);
});
