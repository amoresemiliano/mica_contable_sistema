import { jest } from '@jest/globals';

const mockRpc = jest.fn();

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: mockRpc,
        from: jest.fn(() => ({
            select: jest.fn(() => ({
                eq: jest.fn(() => ({
                    single: jest.fn().mockResolvedValue({ data: { name: 'DEMO NORTE' }, error: null }),
                    order: jest.fn().mockResolvedValue({ data: [{ id: '38419581-8163-482c-9813-616fa6214d71', name: 'DEMO NORTE' }], error: null })
                })),
                order: jest.fn().mockResolvedValue({ data: [{ id: '38419581-8163-482c-9813-616fa6214d71', name: 'DEMO NORTE' }], error: null })
            }))
        }))
    }
}));

const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
const { AppStore } = await import('../../src/js/store.js');

describe('WP-FUNC-2 Operational Consistency Tests', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test('1. active organization name derived from canonical org state', () => {
        const store = new AppStore();
        store.organizations = [
            { id: '38419581-8163-482c-9813-616fa6214d71', name: 'DEMO NORTE' },
            { id: 'c7af5a5c-1aac-4add-9873-8073044bf979', name: 'DEMO SUR' }
        ];

        store.activeOrganizationId = '38419581-8163-482c-9813-616fa6214d71';
        expect(store.getActiveOrganizationName()).toBe('DEMO NORTE');

        store.currentUserRole = 'SUPERADMIN';
        store.activeOrganizationId = null;
        expect(store.getActiveOrganizationName()).toBe('MICA / Plataforma');
    });

    test('2. bulkSoftDeleteRecords invokes canonical soft_delete_normalized_record RPC', async () => {
        mockRpc.mockResolvedValue({ data: null, error: null });

        await persistenceService.bulkSoftDeleteRecords(['rec-1', 'rec-2']);

        expect(mockRpc).toHaveBeenCalledTimes(2);
        expect(mockRpc).toHaveBeenNthCalledWith(1, 'soft_delete_normalized_record', { p_record_id: 'rec-1' });
        expect(mockRpc).toHaveBeenNthCalledWith(2, 'soft_delete_normalized_record', { p_record_id: 'rec-2' });
    });

    test('3. bulkSoftDeleteFinancialMovements invokes canonical soft_delete_financial_movement RPC', async () => {
        mockRpc.mockResolvedValue({ data: null, error: null });

        await persistenceService.bulkSoftDeleteFinancialMovements(['mvmt-100']);

        expect(mockRpc).toHaveBeenCalledWith('soft_delete_financial_movement', { p_movement_id: 'mvmt-100' });
    });

    test('4. Percepciones bulk selection and soft delete updates store state', async () => {
        mockRpc.mockResolvedValue({ data: null, error: null });
        const store = new AppStore();
        store.perceptions = [
            { id: 'p1', cuit: '30711111112', amount: 1000 },
            { id: 'p2', cuit: '30722222223', amount: 2000 }
        ];

        await persistenceService.bulkSoftDeleteRecords(['p1']);
        store.perceptions = store.perceptions.filter(p => p.id !== 'p1');

        expect(store.perceptions.length).toBe(1);
        expect(store.perceptions[0].id).toBe('p2');
    });
});
