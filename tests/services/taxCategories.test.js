import { jest } from '@jest/globals';

const mockRpc = jest.fn();

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: mockRpc
    }
}));

const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');

describe('Tax Categories Service Tests', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test('crea una categoría tributaria y la asigna a la organización activa exitosamente', async () => {
        mockRpc
            .mockResolvedValueOnce({ data: 'cat-uuid-123', error: null }) // create_global_tax_category
            .mockResolvedValueOnce({ data: null, error: null }); // assign_tax_category_to_org

        const res = await persistenceService.createTaxCategory({
            name: 'Servicios Digitales',
            description: 'Gastos de software',
            category_type: 'EXPENSE'
        });

        expect(mockRpc).toHaveBeenCalledWith('create_global_tax_category', {
            p_name: 'Servicios Digitales',
            p_description: 'Gastos de software',
            p_category_type: 'EXPENSE'
        });
        expect(mockRpc).toHaveBeenCalledWith('assign_tax_category_to_org', {
            p_category_id: 'cat-uuid-123',
            p_custom_name: null
        });
        expect(res).toEqual({
            id: 'cat-uuid-123',
            name: 'Servicios Digitales',
            description: 'Gastos de software',
            category_type: 'EXPENSE'
        });
    });

    test('lanza error si el nombre está vacío', async () => {
        await expect(persistenceService.createTaxCategory({ name: '   ' }))
            .rejects.toThrow('El nombre de la categoría es obligatorio.');
    });

    test('maneja errores de la RPC de creación', async () => {
        mockRpc.mockResolvedValueOnce({ data: null, error: { message: 'Categoría duplicada' } });

        await expect(persistenceService.createTaxCategory({ name: 'Ventas' }))
            .rejects.toThrow('Error al crear categoría tributaria: Categoría duplicada');
    });

    test('maneja errores de la RPC de asignación', async () => {
        mockRpc
            .mockResolvedValueOnce({ data: 'cat-uuid-123', error: null })
            .mockResolvedValueOnce({ data: null, error: { message: 'Error de permisos' } });

        await expect(persistenceService.createTaxCategory({ name: 'Ventas' }))
            .rejects.toThrow('Error al asignar categoría a la organización: Error de permisos');
    });
});
