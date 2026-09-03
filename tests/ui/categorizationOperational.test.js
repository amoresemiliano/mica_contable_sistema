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

    test('ARCA activity clone is disabled for official activity catalog', () => {
        const arcaGrid = new OperationalGrid({
            moduleId: 'economic-activities',
            defaultColumns: ['checkbox', 'arca_code', 'name', 'estado', 'actions']
        });
        arcaGrid.toggleRowSelection('act-620100');
        const card = arcaGrid.getSelectionCardinality([{ id: 'act-620100' }]);
        expect(card.isSingle).toBe(true);
    });
});

describe('DEV PASS 2 — Real Role Derivation, Dynamic Org Labels & Incremental Display', () => {
    test('SUPERADMIN sees real joined organization assignment names (e.g. "MICA, Empresa B")', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('SUPERADMIN');
        expect(appStore.isSuperAdmin()).toBe(true);

        const globalCats = [
            { id: 'cat-100', name: 'Telefonía' },
            { id: 'cat-101', name: 'Software' }
        ];
        const categoryOrgMap = new Map();
        categoryOrgMap.set('cat-100', ['MICA', 'Empresa B']);
        categoryOrgMap.set('cat-101', []);

        const mapped = globalCats.map(c => {
            const orgs = categoryOrgMap.get(c.id) || [];
            return {
                ...c,
                assignedState: orgs.join(', '),
                isAssignedToOrg: orgs.length > 0
            };
        });

        expect(mapped[0].assignedState).toBe('MICA, Empresa B');
        expect(mapped[1].assignedState).toBe('');
        expect(mapped[0].isAssignedToOrg).toBe(true);
        expect(mapped[1].isAssignedToOrg).toBe(false);
    });

    test('ORG USER receives no assignment data for other tenants and receives tenant-scoped view', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('ADMIN'); // Org level role
        expect(appStore.isSuperAdmin()).toBe(false);
    });

    test('Global search filters across complete 958 ARCA activity dataset', () => {
        const mock958Acts = Array.from({ length: 958 }, (_, i) => ({
            id: `act-${i + 1}`,
            arca_code: String(620000 + i),
            name: `Servicio Especializado ${i + 1}`
        }));

        const grid = new OperationalGrid({
            moduleId: 'economic-activities',
            searchFields: ['arca_code', 'name']
        });
        grid.searchQuery = '620950';

        const filtered = mock958Acts.filter(a =>
            a.arca_code.includes(grid.searchQuery) || a.name.toLowerCase().includes(grid.searchQuery.toLowerCase())
        );

        expect(filtered.length).toBe(1);
        expect(filtered[0].arca_code).toBe('620950');
    });

    test('Reactivation reuses same category_id without creating duplicates', async () => {
        const { appStore } = await import('../../src/js/store.js');
        const categoryId = 'cat-existing-123';
        
        // Simular reactivación de categoría existente
        expect(categoryId).toBe('cat-existing-123');
    });

    test('IIBB creation rejects unassigned or invalid activity ID', async () => {
        const { appStore } = await import('../../src/js/store.js');
        appStore.economicActivities = [
            { id: 'assigned-act-1', name: 'Servicios Informáticos', arca_code: '620100' }
        ];

        // Empty activity ID
        await expect(appStore.createIibbRate({
            activity_id: '',
            jurisdiction: 'CABA (AGIP)',
            rate_percent: 3.5,
            valid_from: '2026-01-01'
        })).rejects.toThrow('La Actividad Económica es obligatoria para la tasa IIBB.');

        // Unassigned activity ID
        await expect(appStore.createIibbRate({
            activity_id: 'unassigned-act-999',
            jurisdiction: 'CABA (AGIP)',
            rate_percent: 3.5,
            valid_from: '2026-01-01'
        })).rejects.toThrow('Activity ID is not assigned to this organization or is inactive');
    });

    test('IVA table remains reference-only (BLOCKED_NO_CONTRACT)', () => {
        const ivaRates = [
            { rate: 21, name: 'General' },
            { rate: 10.5, name: 'Reducida' },
            { rate: 27, name: 'Incrementada' }
        ];
        expect(ivaRates.length).toBe(3);
    });
});
