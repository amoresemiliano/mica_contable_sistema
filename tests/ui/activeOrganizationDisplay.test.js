import { appStore } from '../../src/js/store.js';

describe('UI: Active Organization Display & Multitenant Tenant Header', () => {
    let mockUserInfoEl;
    let mockEntityLabelEl;

    beforeEach(() => {
        mockUserInfoEl = { innerText: '' };
        mockEntityLabelEl = { innerText: '' };

        global.window = global;
        global.document = {
            getElementById: (id) => {
                if (id === 'user-header-info') return mockUserInfoEl;
                if (id === 'current-entity-label') return mockEntityLabelEl;
                return null;
            }
        };

        appStore.organizations = [
            { id: 'org-norte-uuid', name: 'DEMO NORTE' },
            { id: 'org-sur-uuid', name: 'DEMO SUR' },
            { id: 'org-oeste-uuid', name: 'DEMO OESTE' }
        ];

        window.currentSessionUserIdentity = 'Emiliano Di Rosa';
        window.currentUserRole = 'ADMIN';

        // Definir la función window.updateUserHeaderDisplay bajo prueba
        window.updateUserHeaderDisplay = function() {
            const userInfoEl = document.getElementById('user-header-info');
            const entityLabelEl = document.getElementById('current-entity-label');
            const orgName = appStore.getActiveOrganizationName();
            
            if (entityLabelEl) {
                entityLabelEl.innerText = `Organización: ${orgName}`;
            }

            if (userInfoEl) {
                const userIdentity = window.currentSessionUserIdentity || 'Usuario';
                const role = window.currentUserRole || appStore.currentUserRole || 'USER';
                userInfoEl.innerText = `${orgName} · ${userIdentity} · ${role}`;
            }
        };
    });

    test('1. Usuario en DEMO NORTE muestra DEMO NORTE de forma prioritaria', () => {
        appStore.activeOrganizationId = 'org-norte-uuid';
        appStore.currentUserRole = 'ADMIN';
        window.currentUserRole = 'ADMIN';

        window.updateUserHeaderDisplay();

        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO NORTE');
        expect(mockUserInfoEl.innerText).toBe('DEMO NORTE · Emiliano Di Rosa · ADMIN');
    });

    test('2. Usuario en DEMO OESTE muestra DEMO OESTE y no el texto estático legacy', () => {
        appStore.activeOrganizationId = 'org-oeste-uuid';
        appStore.currentUserRole = 'ADMIN';
        window.currentUserRole = 'ADMIN';
        window.currentSessionUserIdentity = 'Ignacio Emiliano';

        window.updateUserHeaderDisplay();

        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO OESTE');
        expect(mockEntityLabelEl.innerText).not.toContain('VARONE VANESA PAOLA');
        expect(mockUserInfoEl.innerText).toBe('DEMO OESTE · Ignacio Emiliano · ADMIN');
    });

    test('3. Usuario en DEMO SUR muestra DEMO SUR', () => {
        appStore.activeOrganizationId = 'org-sur-uuid';
        appStore.currentUserRole = 'ADMIN';
        window.currentUserRole = 'ADMIN';

        window.updateUserHeaderDisplay();

        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO SUR');
        expect(mockUserInfoEl.innerText).toBe('DEMO SUR · Emiliano Di Rosa · ADMIN');
    });

    test('4. El nombre de Google o email no sustituye el nombre de organización', () => {
        appStore.activeOrganizationId = 'org-oeste-uuid';
        window.currentSessionUserIdentity = 'calleelcalvario16@gmail.com';

        window.updateUserHeaderDisplay();

        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO OESTE');
        expect(mockEntityLabelEl.innerText).not.toContain('calleelcalvario16@gmail.com');
        expect(mockUserInfoEl.innerText).toBe('DEMO OESTE · calleelcalvario16@gmail.com · ADMIN');
    });

    test('5. SUPERADMIN: el cambio de organización activa actualiza inmediatamente el label y header', () => {
        appStore.currentUserRole = 'SUPERADMIN';
        window.currentUserRole = 'SUPERADMIN';
        window.currentSessionUserIdentity = 'Vegen Digital';

        // Inicial: Modo Global
        appStore.activeOrganizationId = null;
        window.updateUserHeaderDisplay();
        expect(mockEntityLabelEl.innerText).toBe('Organización: MICA (Modo Global)');
        expect(mockUserInfoEl.innerText).toBe('MICA (Modo Global) · Vegen Digital · SUPERADMIN');

        // Switch a DEMO OESTE
        appStore.activeOrganizationId = 'org-oeste-uuid';
        window.updateUserHeaderDisplay();
        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO OESTE');
        expect(mockUserInfoEl.innerText).toBe('DEMO OESTE · Vegen Digital · SUPERADMIN');

        // Switch a DEMO SUR
        appStore.activeOrganizationId = 'org-sur-uuid';
        window.updateUserHeaderDisplay();
        expect(mockEntityLabelEl.innerText).toBe('Organización: DEMO SUR');
        expect(mockUserInfoEl.innerText).toBe('DEMO SUR · Vegen Digital · SUPERADMIN');
    });
});
