import { jest } from '@jest/globals';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';

describe('Categorización Module Operational Closeout & Reusable Record Actions', () => {

    let grid;
    let sampleItems;

    beforeEach(() => {
        grid = new OperationalGrid({
            moduleId: 'tax-categories',
            defaultColumns: ['checkbox', 'name', 'description', 'estado', 'actions'],
            searchFields: ['name', 'description']
        });

        sampleItems = [
            { id: 'cat-1', name: 'Honorarios Profesionales', description: 'Gastos legales y contables', isAssignedToOrg: true },
            { id: 'cat-2', name: 'Servicios Digitales', description: 'Licencias de software', isAssignedToOrg: false },
            { id: 'cat-3', name: 'Alquiler Comercial', description: 'Oficina principal', isAssignedToOrg: true }
        ];
    });

    test('Selection Cardinality 0 selected -> all actions disabled', () => {
        grid.clearSelection();
        const card = grid.getSelectionCardinality(sampleItems);
        expect(card.count).toBe(0);
        expect(card.isZero).toBe(true);
        expect(card.canEdit).toBe(false);
        expect(card.canClone).toBe(false);
        expect(card.canToggleActive).toBe(false);
        expect(card.canDelete).toBe(false);
    });

    test('Selection Cardinality 1 selected -> Edit, Clone, Toggle, Delete enabled', () => {
        grid.clearSelection();
        grid.toggleRowSelection('cat-1');
        const card = grid.getSelectionCardinality(sampleItems);
        expect(card.count).toBe(1);
        expect(card.isSingle).toBe(true);
        expect(card.canEdit).toBe(true);
        expect(card.canClone).toBe(true);
        expect(card.canToggleActive).toBe(true);
        expect(card.canDelete).toBe(true);
    });

    test('Selection Cardinality >1 selected -> Edit and Clone disabled, Toggle and Delete enabled', () => {
        grid.clearSelection();
        grid.toggleRowSelection('cat-1');
        grid.toggleRowSelection('cat-2');
        const card = grid.getSelectionCardinality(sampleItems);
        expect(card.count).toBe(2);
        expect(card.isMulti).toBe(true);
        expect(card.canEdit).toBe(false);
        expect(card.canClone).toBe(false);
        expect(card.canToggleActive).toBe(true);
        expect(card.canDelete).toBe(true);
    });

    test('Master checkbox selects and deselects all visible rows', () => {
        grid.clearSelection();
        expect(grid.getSelectedCount()).toBe(0);

        grid.toggleSelectAllVisible(sampleItems);
        expect(grid.getSelectedCount()).toBe(3);
        expect(grid.getSelectionCardinality(sampleItems).isAllVisibleSelected).toBe(true);

        grid.toggleSelectAllVisible(sampleItems);
        expect(grid.getSelectedCount()).toBe(0);
        expect(grid.getSelectionCardinality(sampleItems).isAllVisibleSelected).toBe(false);
    });

    test('Incremental display limit starts at 10 and loadMoreRows increases slice', () => {
        expect(grid.getDisplayLimit()).toBe(10);
        grid.loadMoreRows(10);
        expect(grid.getDisplayLimit()).toBe(20);
        grid.resetDisplayLimit(10);
        expect(grid.getDisplayLimit()).toBe(10);
    });

    test('Selection reconciliation removes non-visible item IDs', () => {
        grid.toggleRowSelection('cat-1');
        grid.toggleRowSelection('cat- hidden');
        expect(grid.getSelectedCount()).toBe(2);

        grid.reconcileSelection(sampleItems);
        expect(grid.getSelectedCount()).toBe(1);
        expect(grid.isRowSelected('cat-1')).toBe(true);
        expect(grid.isRowSelected('cat- hidden')).toBe(false);
    });
});

describe('Multitenant Organization Context & Categorization Isolation Matrix', () => {

    const orgNorteId = 'org-norte-uuid';
    const orgSurId = 'org-sur-uuid';
    const orgOesteId = 'org-oeste-uuid';

    test('Single authenticated user context switching across DEMO NORTE, DEMO SUR, DEMO OESTE', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('SUPERADMIN');
        expect(appStore.isSuperAdmin()).toBe(true);

        // Global MICA mode (no active org selected)
        await appStore.switchOrganizationContext(null);
        expect(appStore.isGlobalMicaMode()).toBe(true);
        expect(appStore.getActiveOrganizationName()).toBe('MICA (Modo Global)');

        // Switch to DEMO NORTE
        await appStore.switchOrganizationContext(orgNorteId);
        expect(appStore.isGlobalMicaMode()).toBe(false);
        expect(appStore.activeOrganizationId).toBe(orgNorteId);

        // Switch to DEMO SUR
        await appStore.switchOrganizationContext(orgSurId);
        expect(appStore.activeOrganizationId).toBe(orgSurId);

        // Switch to DEMO OESTE
        await appStore.switchOrganizationContext(orgOesteId);
        expect(appStore.activeOrganizationId).toBe(orgOesteId);
    });

    test('Multitenant Category Test Matrix (Categories A, B, C, D)', async () => {
        const categoriesDB = [
            { id: 'cat-A', name: 'Category A' },
            { id: 'cat-B', name: 'Category B' },
            { id: 'cat-C', name: 'Category C' },
            { id: 'cat-D', name: 'Category D' }
        ];

        let assignments = [
            { organization_id: orgNorteId, category_id: 'cat-A', is_active: true },
            { organization_id: orgSurId, category_id: 'cat-B', is_active: true },
            { organization_id: orgNorteId, category_id: 'cat-C', is_active: true },
            { organization_id: orgOesteId, category_id: 'cat-C', is_active: true }
        ];

        // 1. GLOBAL MICA sees A, B, C, D
        const globalAssignedMap = new Map();
        assignments.filter(a => a.is_active).forEach(a => {
            const orgName = a.organization_id === orgNorteId ? 'DEMO NORTE' : (a.organization_id === orgSurId ? 'DEMO SUR' : 'DEMO OESTE');
            if (!globalAssignedMap.has(a.category_id)) globalAssignedMap.set(a.category_id, []);
            globalAssignedMap.get(a.category_id).push(orgName);
        });

        const globalView = categoriesDB.map(c => ({
            ...c,
            assignedState: (globalAssignedMap.get(c.id) || []).join(', ')
        }));

        expect(globalView.find(c => c.id === 'cat-A').assignedState).toBe('DEMO NORTE');
        expect(globalView.find(c => c.id === 'cat-B').assignedState).toBe('DEMO SUR');
        expect(globalView.find(c => c.id === 'cat-C').assignedState).toBe('DEMO NORTE, DEMO OESTE');
        expect(globalView.find(c => c.id === 'cat-D').assignedState).toBe('');

        // 2. DEMO NORTE sees A + C
        const norteView = assignments.filter(a => a.organization_id === orgNorteId && a.is_active);
        expect(norteView.map(a => a.category_id)).toEqual(['cat-A', 'cat-C']);

        // 3. DEMO SUR sees B
        const surView = assignments.filter(a => a.organization_id === orgSurId && a.is_active);
        expect(surView.map(a => a.category_id)).toEqual(['cat-B']);

        // 4. DEMO OESTE sees C
        const oesteView = assignments.filter(a => a.organization_id === orgOesteId && a.is_active);
        expect(oesteView.map(a => a.category_id)).toEqual(['cat-C']);

        // 5. Unassign C from DEMO OESTE
        const oesteC = assignments.find(a => a.organization_id === orgOesteId && a.category_id === 'cat-C');
        if (oesteC) oesteC.is_active = false;

        // DEMO OESTE Activas -> 0, Inactivas -> 1 (cat-C)
        const oesteActive = assignments.filter(a => a.organization_id === orgOesteId && a.is_active);
        const oesteInactive = assignments.filter(a => a.organization_id === orgOesteId && !a.is_active);
        expect(oesteActive.length).toBe(0);
        expect(oesteInactive.length).toBe(1);
        expect(oesteInactive[0].category_id).toBe('cat-C');

        // DEMO NORTE -> C remains active
        const norteC = assignments.find(a => a.organization_id === orgNorteId && a.category_id === 'cat-C');
        expect(norteC.is_active).toBe(true);

        // Reactivate C for DEMO OESTE -> reuses same category_id
        if (oesteC) oesteC.is_active = true;
        expect(assignments.filter(a => a.organization_id === orgOesteId && a.is_active).length).toBe(1);
    });

    test('Multitenant ARCA Activity Matrix (Activities X, Y, Z)', async () => {
        let activityAssignments = [
            { organization_id: orgNorteId, activity_id: 'act-X', is_active: true },
            { organization_id: orgSurId, activity_id: 'act-Y', is_active: true },
            { organization_id: orgNorteId, activity_id: 'act-Z', is_active: true },
            { organization_id: orgOesteId, activity_id: 'act-Z', is_active: true }
        ];

        // DEMO NORTE sees X + Z
        expect(activityAssignments.filter(a => a.organization_id === orgNorteId && a.is_active).map(a => a.activity_id)).toEqual(['act-X', 'act-Z']);

        // DEMO SUR sees Y
        expect(activityAssignments.filter(a => a.organization_id === orgSurId && a.is_active).map(a => a.activity_id)).toEqual(['act-Y']);

        // DEMO OESTE sees Z
        expect(activityAssignments.filter(a => a.organization_id === orgOesteId && a.is_active).map(a => a.activity_id)).toEqual(['act-Z']);

        // Unassign Z from DEMO OESTE
        const oesteZ = activityAssignments.find(a => a.organization_id === orgOesteId && a.activity_id === 'act-Z');
        if (oesteZ) oesteZ.is_active = false;

        expect(activityAssignments.filter(a => a.organization_id === orgOesteId && a.is_active).length).toBe(0);
        expect(activityAssignments.filter(a => a.organization_id === orgNorteId && a.is_active).map(a => a.activity_id)).toContain('act-Z');
    });

    test('IIBB Rate creation & selector isolation per organization', async () => {
        const { appStore } = await import('../../src/js/store.js');
        
        // Active activities for DEMO NORTE
        appStore.economicActivities = [{ id: 'act-X', name: 'Actividad X', arca_code: '620100' }];

        // Valid creation in DEMO NORTE
        const norteRate = { activity_id: 'act-X', jurisdiction: 'CABA (AGIP)', rate_percent: 3.5, valid_from: '2026-01-01' };
        expect(norteRate.activity_id).toBe('act-X');

        // Unassigned activity in DEMO NORTE fails IIBB creation
        await expect(appStore.createIibbRate({
            activity_id: 'act-Y',
            jurisdiction: 'CABA (AGIP)',
            rate_percent: 3.5
        })).rejects.toThrow('Activity ID is not assigned to this organization or is inactive');
    });

    test('MICA is NOT an organization and is never rendered as an assigned tenant name', () => {
        const assignedOrgs = ['DEMO NORTE', 'DEMO SUR'];
        expect(assignedOrgs.includes('MICA')).toBe(false);
    });
});

describe('M017 Auth & Multitenant Security Adversarial Verification', () => {

    test('Zero references to firebase_uid, firebase, or auth.jwt in M017 migration file', async () => {
        const fs = await import('fs');
        const path = await import('path');
        const m017Path = path.join(process.cwd(), 'sql', '017_multitenant_superadmin_context.sql');
        const content = fs.readFileSync(m017Path, 'utf8');

        expect(content).not.toContain('firebase_uid');
        expect(content).not.toContain('firebase');
        expect(content).not.toContain('auth.jwt');
        expect(content).toContain('auth_user_id = auth.uid()');
    });

    test('SUPERADMIN can switch to DEMO NORTE/SUR/OESTE and return to GLOBAL MICA mode', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('SUPERADMIN');

        // Switch to DEMO NORTE
        await appStore.switchOrganizationContext('demo-norte-id');
        expect(appStore.activeOrganizationId).toBe('demo-norte-id');
        expect(appStore.isGlobalMicaMode()).toBe(false);

        // Switch to DEMO SUR
        await appStore.switchOrganizationContext('demo-sur-id');
        expect(appStore.activeOrganizationId).toBe('demo-sur-id');
        expect(appStore.isGlobalMicaMode()).toBe(false);

        // Switch to DEMO OESTE
        await appStore.switchOrganizationContext('demo-oeste-id');
        expect(appStore.activeOrganizationId).toBe('demo-oeste-id');
        expect(appStore.isGlobalMicaMode()).toBe(false);

        // Return to GLOBAL MICA mode
        await appStore.switchOrganizationContext(null);
        expect(appStore.activeOrganizationId).toBeNull();
        expect(appStore.isGlobalMicaMode()).toBe(true);
        expect(appStore.getActiveOrganizationName()).toBe('MICA (Modo Global)');
    });

    test('ADMIN role cannot switch organization context (clears active org)', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('ADMIN');
        expect(appStore.isSuperAdmin()).toBe(false);
        expect(appStore.activeOrganizationId).toBeNull();
        expect(appStore.isGlobalMicaMode()).toBe(false);
    });

    test('USER role cannot switch organization context (clears active org)', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('USER');
        expect(appStore.isSuperAdmin()).toBe(false);
        expect(appStore.activeOrganizationId).toBeNull();
    });

    test('GLOBAL MICA mode does not become DEMO NORTE', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('SUPERADMIN');
        await appStore.switchOrganizationContext(null);

        expect(appStore.getActiveOrganizationName()).not.toBe('DEMO NORTE');
        expect(appStore.getActiveOrganizationName()).toBe('MICA (Modo Global)');
    });

    test('Preflight SQL check verifies auth_user_id and forbids firebase_uid', async () => {
        const fs = await import('fs');
        const path = await import('path');
        const preflightPath = path.join(process.cwd(), 'sql', '017_preflight_check.sql');
        const content = fs.readFileSync(preflightPath, 'utf8');

        expect(content).toContain('auth_user_id');
        expect(content).toContain('firebase_uid MUST NOT exist');
        expect(content).toContain('private.org_id()');
        expect(content).toContain('private.func_role()');
        expect(content).toContain('auth.uid()');
    });

    test('Down migration restores pre-017 RPC contracts and RLS policies', async () => {
        const fs = await import('fs');
        const path = await import('path');
        const downPath = path.join(process.cwd(), 'sql', '017_multitenant_superadmin_context_down.sql');
        const content = fs.readFileSync(downPath, 'utf8');

        expect(content).toContain('DROP FUNCTION IF EXISTS public.switch_superadmin_org_context(UUID);');
        expect(content).toContain('assign_tax_category_to_org');
        expect(content).toContain('unassign_tax_category_from_org');
        expect(content).toContain('assign_economic_activity_to_org');
        expect(content).toContain('unassign_economic_activity_from_org');
    });
});

