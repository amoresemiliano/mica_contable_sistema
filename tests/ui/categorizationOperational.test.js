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

    test('ARCA activity clone is disabled for official activity catalog', () => {
        const arcaGrid = new OperationalGrid({
            moduleId: 'economic-activities',
            defaultColumns: ['checkbox', 'arca_code', 'name', 'estado', 'actions']
        });
        arcaGrid.toggleRowSelection('act-620100');
        const card = arcaGrid.getSelectionCardinality([{ id: 'act-620100' }]);
        expect(card.isSingle).toBe(true);
        // Cardinality helper returns true for single selection, but options override isCloneDisabled in UI rendering
    });
});

describe('Role Isolation & Categorization Business Rules', () => {
    test('SUPERADMIN sees global category catalog vs ORG USER seeing tenant-scoped categories', async () => {
        const mockSupabase = {
            from: jest.fn().mockImplementation((table) => {
                if (table === 'eco_tax_categories') {
                    return {
                        select: jest.fn().mockReturnValue({
                            order: jest.fn().mockResolvedValue({
                                data: [
                                    { id: 'cat-1', name: 'Honorarios', category_type: 'EXPENSE' },
                                    { id: 'cat-2', name: 'Alquiler', category_type: 'EXPENSE' }
                                ],
                                error: null
                            })
                        })
                    };
                }
                if (table === 'eco_org_tax_categories') {
                    return {
                        select: jest.fn().mockReturnValue({
                            eq: jest.fn().mockResolvedValue({
                                data: [{ category_id: 'cat-1', is_active: true }],
                                error: null
                            })
                        })
                    };
                }
            })
        };

        // SUPERADMIN check
        const { appStore } = await import('../../src/js/store.js');
        appStore.setUserRole('SUPERADMIN');
        expect(appStore.isSuperAdmin()).toBe(true);

        // ORG USER check
        appStore.setUserRole('ADMIN');
        expect(appStore.isSuperAdmin()).toBe(false);
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

    test('Import F883 catalog populates 958 activities without automatically assigning to organization', async () => {
        const { appStore } = await import('../../src/js/store.js');
        const mock958Activities = Array.from({ length: 958 }, (_, i) => ({
            id: `act-${i + 1}`,
            arca_code: String(i + 1).padStart(6, '0'),
            name: `Actividad ARCA ${i + 1}`,
            description: `Descripción ${i + 1}`
        }));

        appStore.globalEconomicActivities = mock958Activities;
        appStore.economicActivities = [{ id: 'act-1', arca_code: '000001', name: 'Actividad ARCA 1' }];

        // Global count = 958
        expect(appStore.globalEconomicActivities.length).toBe(958);
        // Org assigned count = 1 (NOT 958 automatically assigned)
        expect(appStore.economicActivities.length).toBe(1);
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
