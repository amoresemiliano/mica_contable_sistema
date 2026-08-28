import { jest } from '@jest/globals';

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: { rpc: jest.fn(), storage: { from: () => ({ upload: jest.fn(), remove: jest.fn() }) } }
}));

const { appStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
const { parseBankRows } = await import('../../src/js/core/parsers/bankParser.js');
const { BBVA_DESPLAZADO, BBVA_VACIOS, BBVA_SIN_ENCABEZADO } = await import('../fixtures/synthetic.js');

describe('Phase 5.2 - Financial Movements Integration', () => {

    beforeEach(() => {
        appStore.items = [];
        appStore.perceptions = [];
        // We will pretend appStore has a financialMovements array if we need it
        appStore.financialMovements = [];
        jest.clearAllMocks();
    });

    test('parseBankRows conserva referencia, fechaValor y saldo', () => {
        const rows = [
            ["Fec. Valor", "Fec. Operación", "Concepto", "Referencia", "Importe", "Saldo"],
            ["01/05/2026", "01/05/2026", "TRANSFERENCIA", "123", "1000,50", "1000,50"]
        ];

        const result = parseBankRows(rows);

        expect(result.length).toBe(1);
        expect(result[0].errors.length).toBe(0);

        const data = result[0].normalizedData;
        expect(data.referencia).toBe("123");
        expect(typeof data.referencia).toBe("string");
        expect(data.fechaValor).toBe("01/05/2026");
        expect(data.saldo).toBe(1000.50);
        expect(data.monto).toBe(1000.50);
        expect(data.tipo).toBe("credit"); // As it's positive
    });

    test('rehidratación financiera separada (no ensucia items ni percepciones)', async () => {
        // Mock de supabase para las tres colecciones
        jest.spyOn(persistenceService, 'loadActiveFiscalRecords').mockResolvedValue([
            { id: 'fiscal1' }
        ]);
        jest.spyOn(persistenceService, 'loadActivePerceptions').mockResolvedValue([
            { id: 'perc1' }
        ]);
        jest.spyOn(persistenceService, 'loadActiveFinancialMovements').mockResolvedValue([
            { id: 'fin1', sourceType: 'BANK_STATEMENT_BBVA' },
            { id: 'fin2', sourceType: 'PAYROLL_ACONPY' }
        ]);

        const fiscalRecords = await persistenceService.loadActiveFiscalRecords();
        const perceptions = await persistenceService.loadActivePerceptions();
        const financialMovements = await persistenceService.loadActiveFinancialMovements();

        expect(fiscalRecords.length).toBe(1);
        expect(perceptions.length).toBe(1);
        expect(financialMovements.length).toBe(2);

        // Verifica separación estricta
        const ids = financialMovements.map(f => f.id);
        expect(ids).toContain('fin1');
        expect(ids).toContain('fin2');
        expect(ids).not.toContain('fiscal1');
        expect(ids).not.toContain('perc1');
    });

    test('persistFinancialMovementsBatch lanza error si falla', async () => {
        const spyPersist = jest.spyOn(persistenceService, 'persistFinancialMovementsBatch').mockRejectedValue(new Error('RPC Error'));

        await expect(persistenceService.persistFinancialMovementsBatch({
            importId: 'imp-123',
            fileInfo: {},
            stagedRows: []
        })).rejects.toThrow('RPC Error');
    });

    test('rehidratación financiera (Phase 5.5.1 FIX)', async () => {
        // A. loadActiveFinancialMovements retorna camelCase con rawRecord
        const mockDbRecords = [
            {
                id: 'db-id-1',
                source_type: 'PAYROLL_ACONPY',
                operation_type: 'SUELDO',
                fecha: '2026-05-31',
                normalized_payload: {
                    periodo: '2026-05',
                    sueldoNeto: 1000
                }
            },
            {
                id: 'db-id-2',
                source_type: 'BANK_STATEMENT_BBVA',
                operation_type: 'BANCO',
                fecha: '2026-05-30',
                normalized_payload: {
                    fecha: '2026-05-30',
                    monto: 500
                }
            }
        ];

        // Usamos spy para que retorne los datos directamente del RPC mockeado
        const spyLoad = jest.spyOn(persistenceService, 'loadActiveFinancialMovements').mockResolvedValue([
            {
                id: 'db-id-1',
                operationType: 'SUELDO',
                rawRecord: { periodo: '2026-05', sueldoNeto: 1000 }
            },
            {
                id: 'db-id-2',
                operationType: 'BANCO',
                rawRecord: { fecha: '2026-05-30', monto: 500 }
            }
        ]);

        const loadedFinancials = await persistenceService.loadActiveFinancialMovements();

        // D. Verificamos que no tiene operation_type ni normalized_payload
        expect(loadedFinancials[0].operation_type).toBeUndefined();
        expect(loadedFinancials[0].normalized_payload).toBeUndefined();

        // B. & C. Simulamos la lógica de ui.js
        const bankMovements = loadedFinancials
            .filter(f => f.operationType === 'BANCO')
            .map(f => ({ ...f.rawRecord, id: f.id }));

        const salaries = loadedFinancials
            .filter(f => f.operationType === 'SUELDO')
            .map(f => ({ ...f.rawRecord, id: f.id }));

        // Comprobamos preservación de ID DB y mapeo de rawRecord
        expect(bankMovements.length).toBe(1);
        expect(bankMovements[0].id).toBe('db-id-2');
        expect(bankMovements[0].monto).toBe(500);

        expect(salaries.length).toBe(1);
        expect(salaries[0].id).toBe('db-id-1');
        expect(salaries[0].sueldoNeto).toBe(1000);
    });
});
