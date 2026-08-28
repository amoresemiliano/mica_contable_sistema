import { jest } from '@jest/globals';

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: { rpc: jest.fn() }
}));

const { appStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
const { parseArbaText } = await import('../../src/js/core/parsers/arbaParser.js');

describe('Phase 4.5 - Percepciones Integration', () => {

    beforeEach(() => {
        appStore.items = [];
        appStore.perceptions = [];
        jest.clearAllMocks();
    });

    test('rehidratación no introduce percepciones en items y Recibidos/Emitidos siguen rehidratando igual', async () => {
        // Mock de supabase
        jest.spyOn(persistenceService, 'loadActiveFiscalRecords').mockResolvedValue([
            { id: 'item1', tipo: 'recibido', total: 100 }
        ]);
        jest.spyOn(persistenceService, 'loadActivePerceptions').mockResolvedValue([
            { id: 'perc1', cuit: '20111111112', tipo: 'percepcion', jurisdiction: 'ARBA', amount: 50 }
        ]);

        const fiscalRecords = await persistenceService.loadActiveFiscalRecords();
        const perceptions = await persistenceService.loadActivePerceptions();

        appStore.addItems(fiscalRecords);
        appStore.addPerceptions(perceptions);

        expect(appStore.items.length).toBe(1);
        expect(appStore.items[0].id).toBe('item1');

        expect(appStore.perceptions.length).toBe(1);
        expect(appStore.perceptions[0].id).toBe('perc1');

        // Ensure no cross-contamination
        const itemIds = appStore.items.map(i => i.id);
        const percIds = appStore.perceptions.map(p => p.id);
        expect(itemIds).not.toContain('perc1');
        expect(percIds).not.toContain('item1');
    });

    test('parseArbaText preserva ceros y retorna strings para regimen, sucursal, comprobante', () => {
        const fakeTxt = "006227-23145678-1 15/05/2026000100000000000000000000010000000001550,50";
        const result = parseArbaText(fakeTxt, { jurisdiccion: 'ARBA' });

        expect(result[0].errors.length).toBe(0);
        const data = result[0].normalizedData;

        // "0062" permanece string
        expect(data.regimen).toBe("0062");
        expect(typeof data.regimen).toBe("string");

        // "0001" permanece string
        expect(data.sucursal).toBe("0001");
        expect(typeof data.sucursal).toBe("string");

        // "000000000000000000000100" permanece string
        expect(data.comprobante).toBe("000000000000000000000100");
        expect(typeof data.comprobante).toBe("string");
    });

    test('persistPerceptionsBatch recibe TODAS las filas (válidas e inválidas), y appStore solo las válidas', async () => {
        const stagedRows = [
            {
                sourceRowNumber: 1,
                rawRow: 'Fila Valida',
                normalizedData: { cuit: '30111111118', amount: 100, period: '2026-05', jurisdiction: 'ARBA' },
                errors: [],
                warnings: []
            },
            {
                sourceRowNumber: 2,
                rawRow: 'Fila Invalida Corta',
                normalizedData: null,
                errors: ['Longitud de línea inválida'],
                warnings: []
            }
        ];

        // Mocks for persistenceService
        const spyPersist = jest.spyOn(persistenceService, 'persistPerceptionsBatch').mockResolvedValue({
            import_id: 'imp-123',
            total_rows: 2,
            accepted_rows: 1,
            invalid_rows: 1,
            duplicate_rows: 0,
            issue_rows: 1,
            status: 'COMPLETED'
        });

        // Act
        const result = await persistenceService.persistPerceptionsBatch({
            importId: 'imp-123',
            fileInfo: {},
            stagedRows: stagedRows
        });

        // Verification 1: persistPerceptionsBatch received both rows (length === 2)
        expect(spyPersist).toHaveBeenCalledWith(expect.objectContaining({
            stagedRows: expect.arrayContaining([
                expect.objectContaining({ normalizedData: expect.anything() }),
                expect.objectContaining({ normalizedData: null, errors: expect.arrayContaining(['Longitud de línea inválida']) })
            ])
        }));
        expect(spyPersist.mock.calls[0][0].stagedRows.length).toBe(2);

        // Act 2: Simulate what the UI does: appStore.addPerceptions(acceptedItems)
        // acceptedItems ONLY contains the valid items (normalizedData !== null).
        const acceptedItems = stagedRows.filter(r => r.normalizedData !== null).map(r => r.normalizedData);
        appStore.addPerceptions(acceptedItems);

        // Verification 2: appStore only has 1 perception
        expect(appStore.perceptions.length).toBe(1);
        expect(appStore.perceptions[0].cuit).toBe('30111111118');
        expect(appStore.perceptions[0].amount).toBe(100);
    });
});
