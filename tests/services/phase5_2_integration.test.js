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
});
