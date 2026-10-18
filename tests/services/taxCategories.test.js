import { jest } from '@jest/globals';

const mockRpc = jest.fn();
const lookup=jest.fn();
const query={select:jest.fn(),eq:jest.fn(),maybeSingle:lookup};
query.select.mockReturnValue(query);query.eq.mockReturnValue(query);

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: mockRpc,from:()=>query
    }
}));

const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');

describe('Tax Categories Service Tests', () => {
    beforeEach(() => {
        jest.resetAllMocks();
        query.select.mockReturnValue(query);query.eq.mockReturnValue(query);
        lookup.mockResolvedValue({data:null,error:null});
    });

    test('crea una categoría tributaria y la asigna a la organización activa exitosamente', async () => {
        mockRpc
            .mockResolvedValueOnce({ data: 'cat-uuid-123', error: null }) // create_global_tax_category
            .mockResolvedValueOnce({ data: null, error: null }); // assign_tax_category_to_org

        const res = await persistenceService.createTaxCategory({
            name: 'Servicios Digitales',
            description: 'Gastos de software',
            category_type: 'EXPENSE'
        }, 'target-org');

        expect(mockRpc).toHaveBeenCalledWith('create_global_tax_category', {
            p_name: 'Servicios Digitales',
            p_description: 'Gastos de software',
            p_category_type: 'EXPENSE'
        });
        expect(mockRpc).toHaveBeenCalledWith('assign_tax_category_to_org', {
            p_category_id: 'cat-uuid-123',
            p_custom_name: null,
            p_target_org_id: 'target-org'
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

        await expect(persistenceService.createTaxCategory({ name: 'Ventas' }, 'target-org'))
            .rejects.toThrow('Error al asignar categoría a la organización: Error de permisos');
    });
    test('normalizes display whitespace and queries the generated canonical key',async()=>{
        mockRpc.mockResolvedValue({data:'new',error:null});
        await persistenceService.createTaxCategory({name:'  TELEFONÍA\t  móvil ',category_type:'EXPENSE'});
        expect(query.eq).toHaveBeenCalledWith('canonical_name_key','telefonia movil');
        expect(mockRpc).toHaveBeenCalledWith('create_global_tax_category',expect.objectContaining({p_name:'TELEFONÍA móvil'}));
    });
    test('existing equivalent prevents RPC and organization assignment',async()=>{
        lookup.mockResolvedValue({data:{id:'canonical'},error:null});
        await expect(persistenceService.createTaxCategory({name:' Telefonia '},'tenant')).rejects.toThrow('Esta categoría ya existe en el catálogo global.');
        expect(mockRpc).not.toHaveBeenCalled();
    });
    test('DB uniqueness race produces the same clear message',async()=>{
        mockRpc.mockResolvedValue({data:null,error:{code:'23505',message:'unique constraint'}});
        await expect(persistenceService.createTaxCategory({name:'Telefonía'})).rejects.toThrow('Esta categoría ya existe en el catálogo global.');
    });
    test('lookup failure aborts instead of creating against an unknown catalog',async()=>{
        lookup.mockResolvedValue({data:null,error:{message:'missing migration'}});
        await expect(persistenceService.createTaxCategory({name:'Telefonía'})).rejects.toThrow('No se pudo verificar');
        expect(mockRpc).not.toHaveBeenCalled();
    });
});
