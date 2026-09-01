import { OperationalGrid } from '../../src/js/core/operationalGrid.js';

describe('Operational Grid System Tests', () => {
    let grid;
    let mockStorage = {};

    beforeAll(() => {
        if (typeof global.localStorage === 'undefined') {
            global.localStorage = {
                getItem: (key) => mockStorage[key] || null,
                setItem: (key, value) => { mockStorage[key] = String(value); },
                clear: () => { mockStorage = {}; },
                removeItem: (key) => { delete mockStorage[key]; }
            };
        }
    });

    const sampleItems = [
        { id: '1', fecha: '2026-08-01', comprobante: 'FC-A 0001-00000001', cuit: '30710536461', razonSocial: 'Pérez e Hijos', total: 1500.50, tipo: 'emitido', categoria: 'Ventas' },
        { id: '2', fecha: '2026-08-15', comprobante: 'FC-A 0001-00000002', cuit: '20263235550', razonSocial: 'Álvarez Tech', total: 200.00, tipo: 'recibido', categoria: 'Sin Categorizar' },
        { id: '3', fecha: '2026-07-20', comprobante: 'FC-B 0002-00000005', cuit: '30506733524', razonSocial: 'YPF S.A.', total: 10000.00, tipo: 'emitido', categoria: 'Combustibles' }
    ];

    beforeEach(() => {
        global.localStorage.clear();
        grid = new OperationalGrid({
            moduleId: 'comprobantes',
            defaultColumns: ['fecha', 'comprobante', 'cuit', 'razonSocial', 'total', 'categoria'],
            searchFields: ['comprobante', 'cuit', 'razonSocial', 'categoria']
        });
    });

    test('ordena numéricamente por total y no alfabéticamente', () => {
        grid.toggleSort('total', 'numeric'); // asc
        let res = grid.filterAndSort(sampleItems);
        expect(res.map(i => i.total)).toEqual([200.00, 1500.50, 10000.00]);

        grid.toggleSort('total', 'numeric'); // desc
        res = grid.filterAndSort(sampleItems);
        expect(res.map(i => i.total)).toEqual([10000.00, 1500.50, 200.00]);
    });

    test('ordena cronológicamente por fecha', () => {
        grid.toggleSort('fecha', 'date'); // asc
        let res = grid.filterAndSort(sampleItems);
        expect(res.map(i => i.id)).toEqual(['3', '1', '2']);
    });

    test('ordena alfabéticamente por texto ignorando acentos', () => {
        grid.toggleSort('razonSocial', 'text'); // asc
        let res = grid.filterAndSort(sampleItems);
        expect(res.map(i => i.razonSocial)).toEqual(['Álvarez Tech', 'Pérez e Hijos', 'YPF S.A.']);
    });

    test('filtra por período YYYY-MM', () => {
        grid.setPeriod('2026-08');
        let res = grid.filterAndSort(sampleItems);
        expect(res.length).toBe(2);
        expect(res.map(i => i.id)).toEqual(['1', '2']);
    });

    test('búsqueda insensible a mayúsculas y acentos', () => {
        grid.setSearch('perez');
        let res = grid.filterAndSort(sampleItems);
        expect(res.length).toBe(1);
        expect(res[0].id).toBe('1');
    });

    test('limpiar búsqueda restaura el listado sin perder otros filtros', () => {
        grid.setPeriod('2026-08');
        grid.setSearch('alvarez');
        let res1 = grid.filterAndSort(sampleItems);
        expect(res1.length).toBe(1);

        grid.clearSearch();
        let res2 = grid.filterAndSort(sampleItems);
        expect(res2.length).toBe(2);
    });

    test('filtro principal Emitidos / Recibidos / Sin Categorizar', () => {
        grid.setPrimaryFilter('emitidos');
        let res = grid.filterAndSort(sampleItems);
        expect(res.length).toBe(2);

        grid.setPrimaryFilter('pending');
        res = grid.filterAndSort(sampleItems);
        expect(res.length).toBe(1);
        expect(res[0].id).toBe('2');
    });

    test('persistencia local de preferencia de columnas', () => {
        expect(grid.isColumnVisible('fecha')).toBe(true);
        grid.toggleColumnVisibility('fecha'); // oculta fecha
        expect(grid.isColumnVisible('fecha')).toBe(false);

        // Crear una nueva instancia y comprobar rehidratación
        const grid2 = new OperationalGrid({
            moduleId: 'comprobantes',
            defaultColumns: ['fecha', 'comprobante']
        });
        expect(grid2.isColumnVisible('fecha')).toBe(false);

        grid2.resetColumns();
        expect(grid2.isColumnVisible('fecha')).toBe(true);
    });

    test('selección de filas visibles solo selecciona las filtradas actualmente', () => {
        grid.setPrimaryFilter('recibidos'); // Solo item 2 visible
        const visible = grid.filterAndSort(sampleItems);
        expect(visible.length).toBe(1);

        grid.toggleSelectAllVisible(visible);
        expect(grid.selectedRowIds.has('2')).toBe(true);
        expect(grid.selectedRowIds.has('1')).toBe(false);
        expect(grid.selectedRowIds.has('3')).toBe(false);
    });
});
