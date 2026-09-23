import { jest } from '@jest/globals';
import { readFileSync } from 'node:fs';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';

const source = readFileSync('src/js/ui.js', 'utf8');

// Execute production rendering and event handlers, not copies of their filters.
function harness(role = 'ADMIN', context = 'org-1') {
    const nodes = new Map();
    const document = { getElementById(id) {
        if (!nodes.has(id)) nodes.set(id, { style: {}, value: 'org-1', innerHTML: '', classList: { add() {}, remove() {} } });
        return nodes.get(id);
    } };
    const rows = Array.from({ length: 16 }, (_, i) => ({
        id: `row-${i + 1}`, name: i === 1 ? 'Excluded' : 'Match', description: '',
        arca_code: `code-${i + 1}`, is_active: i % 2 === 0,
        is_assigned: true, organization_id: 'org-1',
        assignedOrganizationIds: i % 2 === 0 ? ['org-1'] : ['org-2']
    }));
    const appStore = {
        currentUserRole: role, activeOrganizationId: context,
        canManageGlobalCatalog: () => role === 'SUPERADMIN' && context === null,
        canAssignCatalog: () => role === 'SUPERADMIN',
        isSuperAdmin: () => role === 'SUPERADMIN',
        isGlobalMicaMode: () => role === 'SUPERADMIN' && context === null,
        organizations: [{ id: 'org-1', name: 'One' }, { id: 'org-2', name: 'Two' }],
        taxCategories: rows.map(r => ({ ...r })), displayedEconomicActivities: rows.map(r => ({ ...r })),
        economicActivities: [], iibbRates: []
    };
    for (const method of ['bulkAssignTaxCategories', 'bulkUnassignTaxCategories', 'setTaxCategoriesActive',
        'bulkAssignEconomicActivitiesToOrg', 'bulkUnassignEconomicActivitiesFromOrg', 'setEconomicActivitiesActive']) {
        appStore[method] = jest.fn().mockResolvedValue(undefined);
    }
    const tax = new OperationalGrid({ moduleId: 'test-tax' });
    const econ = new OperationalGrid({ moduleId: 'test-econ' });
    const iibb = new OperationalGrid({ moduleId: 'test-iibb' });
    const window = {};
    const methods = source.slice(source.indexOf('    static renderRecordActionToolbar('), source.indexOf('    static renderImportIssues()'));
    const UI = new Function('appStore', 'document', 'window', 'taxCategoriesGrid', 'economicActivitiesGrid', 'iibbRatesGrid',
        `return class { static closeModal() {} ${methods} }`)(appStore, document, window, tax, econ, iibb);
    for (const name of ['toggleMasterTaxCategories', 'toggleMasterEconomicActivities',
        'actionToggleTaxCategories', 'actionDeleteTaxCategories', 'actionAssignEconomicActivities', 'actionUnassignEconomicActivities',
        'handleCatalogTargetChange', 'loadMoreTaxCategories', 'loadMoreEconomicActivities']) {
        const start = source.indexOf(`window.${name} =`);
        const end = source.indexOf('\n};', start) + 3;
        new Function('window', 'appStore', 'document', 'UIManager', 'taxCategoriesGrid', 'economicActivitiesGrid', 'confirm', 'alert',
            source.slice(start, end))(window, appStore, document, UI, tax, econ, () => true, jest.fn());
    }
    return { nodes, document, appStore, window, UI, tax, econ };
}

describe.each([
    ['categories', 'tax', 'toggleMasterTaxCategories', 'table-tax-categories-body', 'toolbar-tax-categories', 'actionToggleTaxCategories', 'actionDeleteTaxCategories', 'setTaxCategoriesActive', 'bulkAssignTaxCategories', 'bulkUnassignTaxCategories', 'select-target-org-tax-cat', 'loadMoreTaxCategories'],
    ['activities', 'econ', 'toggleMasterEconomicActivities', 'table-economic-activities-body', 'toolbar-economic-activities', 'actionAssignEconomicActivities', 'actionUnassignEconomicActivities', 'setEconomicActivitiesActive', 'bulkAssignEconomicActivitiesToOrg', 'bulkUnassignEconomicActivitiesFromOrg', 'select-target-org-econ-act', 'loadMoreEconomicActivities']
])('%s bulk view contract', (kind, gridName, master, table, toolbar, enable, disable, tenantRPC, assign, unassign, target, more) => {
    test.each([
        ['active', ['row-1', 'row-3']],
        ['inactive', ['row-4', 'row-6']],
        ['all', ['row-1', 'row-3']]
    ])('ADMIN %s selects exactly the visible search results within the limit', (filter, expected) => {
        const h = harness();
        const grid = h[gridName];
        grid.setFilterStatus(filter);
        grid.searchQuery = 'MATCH';
        grid.displayLimitCustom = true;
        grid.displayLimit = 2;
        h.UI.renderSettings();
        const rendered = [...h.nodes.get(table).innerHTML.matchAll(/value="(row-\d+)"/g)].map(m => m[1]);
        expect(rendered).toEqual(expected);
        grid.toggleRowSelection('row-16'); // Stale, off-screen selection must be discarded.
        h.window[master](true);
        expect(grid.getSelectedIds()).toEqual(rendered);
        h.window[master](false);
        expect(grid.getSelectedIds()).toEqual([]);
    });

    test('default tenant limit and expanded page match rendering', () => {
        const h = harness();
        h.UI.renderSettings();
        h.window[master](true);
        expect(h[gridName].getSelectedIds()).toHaveLength(5);
        h[gridName].clearSelection();
        h.window[more]();
        h.window[master](true);
        expect(h[gridName].getSelectedIds()).toHaveLength(10);
    });

    test('ADMIN bulk activation/deactivation never calls assignment operations', async () => {
        const h = harness();
        h[gridName].setFilterStatus('inactive');
        h[gridName].displayLimitCustom = true;
        h[gridName].displayLimit = 2;
        h.UI.renderSettings();
        expect(h.nodes.get(toolbar).innerHTML).toContain('Activar');
        expect(h.nodes.get(toolbar).innerHTML).toContain('Desactivar');
        expect(h.nodes.get(toolbar).innerHTML).not.toContain('Desasignar');
        h.window[master](true);
        await h.window[enable]();
        expect(h.appStore[tenantRPC]).toHaveBeenCalledWith(['row-2', 'row-4'], true);
        h.window[master](true);
        await h.window[disable]();
        expect(h.appStore[tenantRPC]).toHaveBeenCalledWith(['row-2', 'row-4'], false);
        expect(h.appStore[assign]).not.toHaveBeenCalled();
        expect(h.appStore[unassign]).not.toHaveBeenCalled();
    });

    test('SUPERADMIN assignment is relative to selected target, independent of activation', async () => {
        const h = harness('SUPERADMIN', null);
        h[gridName].setFilterStatus('unassigned');
        h[gridName].displayLimitCustom = true;
        h[gridName].displayLimit = 2;
        h.UI.renderSettings();
        h.window[master](true);
        expect(h[gridName].getSelectedIds()).toEqual(['row-2', 'row-4']);
        expect(h.nodes.get(toolbar).innerHTML).toContain('Asignar');
        expect(h.nodes.get(toolbar).innerHTML).toContain('Desasignar');
        await h.window[enable]();
        expect(h.appStore[assign]).toHaveBeenCalledWith(['row-2', 'row-4'], 'org-1');
        h.document.getElementById(target).value = 'org-2';
        h.window.handleCatalogTargetChange(kind);
        expect(h[gridName].getSelectedIds()).toEqual([]);
        h.window[master](true);
        expect(h[gridName].getSelectedIds()).toEqual(['row-1', 'row-3']);
        await h.window[disable]();
        expect(h.appStore[unassign]).toHaveBeenCalledWith(['row-1', 'row-3'], 'org-2');
        expect(h.appStore[tenantRPC]).not.toHaveBeenCalled();
    });

    test('SUPERADMIN tenant context uses tenant visibility filters, not global assignment filters', () => {
        const h = harness('SUPERADMIN', 'org-1');
        h[gridName].setFilterStatus('inactive');
        h.UI.renderSettings();
        h.window[master](true);
        expect(h[gridName].getSelectedIds()).toEqual(['row-2', 'row-4', 'row-6', 'row-8', 'row-10']);
    });
});
