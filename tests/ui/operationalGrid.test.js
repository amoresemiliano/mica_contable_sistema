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

    describe('Filtros de fecha robustos para Extractos Bancarios', () => {
        const bankItems = [
            { id: 'b1', fecha: '2026-06-01', descripcion: 'Depósito inicio junio', monto: 1000, tipo: 'credit' },
            { id: 'b2', fecha: '30-06-2026', descripcion: 'Transf fin junio DD-MM-YYYY', monto: -500, tipo: 'debit' },
            { id: 'b3', fecha: '15/06/2026', descripcion: 'Cobro medio junio DD/MM/YYYY', monto: 2000, tipo: 'credit' },
            { id: 'b4', fecha: '2026-05-31', descripcion: 'Fin de mayo ISO', monto: -100, tipo: 'debit' },
            { id: 'b5', fecha: '15-05-2026', descripcion: 'Medio de mayo DD-MM-YYYY', monto: 300, tipo: 'credit' },
            { id: 'b6', fecha: '2025-06-15', descripcion: 'Junio del año anterior', monto: 400, tipo: 'credit' }
        ];

        let bankGrid;
        beforeEach(() => {
            bankGrid = new OperationalGrid({
                moduleId: 'extractos',
                defaultColumns: ['fecha', 'descripcion', 'monto', 'tipo'],
                searchFields: ['descripcion']
            });
        });

        test('filtrar por Junio 2026 incluye movimientos 2026-06-01, 30-06-2026 y 15/06/2026', () => {
            bankGrid.setPeriod('2026-06');
            const res = bankGrid.filterAndSort(bankItems);
            expect(res.map(i => i.id)).toEqual(['b1', 'b2', 'b3']);
        });

        test('filtrar por Mayo 2026 incluye movimientos de mayo y excluye junio', () => {
            bankGrid.setPeriod('2026-05');
            const res = bankGrid.filterAndSort(bankItems);
            expect(res.map(i => i.id)).toEqual(['b4', 'b5']);
        });

        test('filtrar por rango de fecha personalizado (límites 2026-06-01 a 2026-06-30)', () => {
            bankGrid.setCustomRange('2026-06-01', '2026-06-30');
            const res = bankGrid.filterAndSort(bankItems);
            expect(res.map(i => i.id)).toEqual(['b1', 'b2', 'b3']);
        });

        test('sin período seleccionado (clearPeriod) devuelve todos los movimientos', () => {
            bankGrid.setPeriod('2026-06');
            expect(bankGrid.filterAndSort(bankItems).length).toBe(3);
            bankGrid.clearPeriod();
            expect(bankGrid.filterAndSort(bankItems).length).toBe(6);
        });

        test('diferencia correctamente años (2025-06 vs 2026-06)', () => {
            bankGrid.setPeriod('2025-06');
            const res = bankGrid.filterAndSort(bankItems);
            expect(res.map(i => i.id)).toEqual(['b6']);
        });
    });

    describe('Composición de filtros de Extractos Bancarios (AND Semantics)', () => {
        const bankItems = [
            { id: 'b1', fecha: '2026-06-01', descripcion: 'Depósito sueldo DataNet', monto: 1000, tipo: 'credit' },
            { id: 'b2', fecha: '30-06-2026', descripcion: 'Pago servicio DataNet', monto: -500, tipo: 'debit' },
            { id: 'b3', fecha: '15/06/2026', descripcion: 'Transferencia cliente', monto: 2000, tipo: 'credit' },
            { id: 'b4', fecha: '2026-05-31', descripcion: 'Pago proveedor mayo', monto: -100, tipo: 'DEBITO' },
            { id: 'b5', fecha: '15-05-2026', descripcion: 'Acreditación mayo', monto: 300, tipo: 'CREDITO' },
            { id: 'b6', fecha: '2025-06-15', descripcion: 'Abono antiguo', monto: 400, tipo: 'credit' }
        ];

        let bankGrid;
        const extractor = {
            fecha: t => t.fecha,
            descripcion: t => t.descripcion,
            monto: t => t.monto
        };

        beforeEach(() => {
            bankGrid = new OperationalGrid({
                moduleId: 'extractos',
                defaultColumns: ['fecha', 'descripcion', 'monto', 'tipo'],
                searchFields: ['descripcion'],
                dateField: 'fecha',
                amountField: 'monto'
            });
        });

        test('June 2026 + Todos -> devuelve todos los de junio 2026', () => {
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('all');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b1', 'b2', 'b3']);
        });

        test('June 2026 + Débitos -> sólo movimientos de débito de junio 2026', () => {
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('debitos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b2']);
        });

        test('June 2026 + Créditos -> sólo movimientos de crédito de junio 2026', () => {
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('creditos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b1', 'b3']);
        });

        test('May 2026 + Débitos -> sólo movimientos de débito de mayo 2026', () => {
            bankGrid.setPeriod('2026-05');
            bankGrid.setPrimaryFilter('debitos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b4']);
        });

        test('May 2026 + Créditos -> sólo movimientos de crédito de mayo 2026', () => {
            bankGrid.setPeriod('2026-05');
            bankGrid.setPrimaryFilter('creditos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b5']);
        });

        test('Custom Range + Débitos -> sólo débitos dentro del rango', () => {
            bankGrid.setCustomRange('2026-05-01', '2026-06-15');
            bankGrid.setPrimaryFilter('debitos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b4']);
        });

        test('Custom Range + Créditos -> sólo créditos dentro del rango', () => {
            bankGrid.setCustomRange('2026-06-01', '2026-06-30');
            bankGrid.setPrimaryFilter('creditos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b1', 'b3']);
        });

        test('Search + Period + Débitos -> intersección estricta AND', () => {
            bankGrid.setSearch('datanet');
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('debitos');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b2']);
        });

        test('Clear All -> devuelve todos los elementos sin filtros', () => {
            bankGrid.setSearch('datanet');
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('debitos');
            expect(bankGrid.filterAndSort(bankItems, extractor).length).toBe(1);

            bankGrid.clearSearch();
            bankGrid.clearPeriod();
            bankGrid.setPrimaryFilter('all');
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.length).toBe(6);
        });

        test('Ordenamiento respeta la composición de filtros previa', () => {
            bankGrid.setPeriod('2026-06');
            bankGrid.setPrimaryFilter('creditos');
            bankGrid.toggleSort('monto', 'numeric'); // asc
            const res = bankGrid.filterAndSort(bankItems, extractor);
            expect(res.map(i => i.id)).toEqual(['b1', 'b3']);
        });
    });
});
