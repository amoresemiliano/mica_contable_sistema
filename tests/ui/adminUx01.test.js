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

        const buttons = walk(root).filter(n => n.className?.includes('mica-action-btn'));
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
