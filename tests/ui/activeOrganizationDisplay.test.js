import { AppStore } from '../../src/js/store.js';
import { renderOperationalHeader } from '../../src/js/components/operationalOrgSelector.js';

describe('UI: confirmed organization and effective profile header', () => {
    test.each(['NORTE', 'SUR', 'OESTE'])('email and canonical %s label are rendered by the real header', name => {
        const store = new AppStore();
        store.sessionUserId = 'user';
        store.sessionEmail = 'user@example.com';
        store.effectiveProfileName = 'Administrador';
        store.currentUserRole = 'LEGACY_ROLE';
        store.activeOrganizationId = name + '-id';
        store.confirmedOrganizationName = name;
        const nodes = { 'user-header-info': {}, 'current-entity-label': {} };
        renderOperationalHeader(store, { getElementById: id => nodes[id] });
        expect(nodes['user-header-info'].innerText).toBe(`user@example.com · ${name} · Administrador`);
        expect(nodes['current-entity-label'].innerText).toBe(`Organización: ${name}`);
    });

    test('platform header does not invent a membership and logout clears identity', () => {
        const store = new AppStore();
        store.sessionUserId = 'owner';
        store.sessionEmail = 'owner@example.com';
        store.effectiveProfileName = 'Platform owner';
        store.activeOrganizationId = null;
        const header = {};
        const document = { getElementById: id => id === 'user-header-info' ? header : null };
        renderOperationalHeader(store, document);
        expect(header.innerText).toBe('owner@example.com · MICA / Plataforma · Platform owner');
        store.endSession();
        renderOperationalHeader(store, document);
        expect(header.innerText).toBe('');
    });
});
