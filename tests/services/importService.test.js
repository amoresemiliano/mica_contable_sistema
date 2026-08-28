import { stageImport } from '../../src/js/core/services/importService.js';
import { createNodeFingerprintProvider } from '../helpers/nodeFingerprintProvider.js';

describe('Import Service (Staging)', () => {
    it('should identify new, duplicate, and possible amendment records', async () => {
        const provider = createNodeFingerprintProvider();
        const context = { tenant: '30111111118', tipoOperacion: 'COMPRA' };

        // Simulamos registros normalizados
        const existingData = {
            tenant: '30111111118',
            tipoOperacion: 'COMPRA',
            cuit: '20222222224',
            tipo_cbte: 1,
            pdv: 1,
            nroDesde: 100,
            nroHasta: 100,
            moneda: 'PES',
            total: 500,
            netoGravadoTotal: 400
        };

        const existingRecords = [existingData];

        const incomingRows = [
            {
                normalizedData: {
                    cuit: '20222222224',
                    tipo_cbte: 1,
                    pdv: 1,
                    nroDesde: 100,
                    nroHasta: 100,
                    moneda: 'PES',
                    total: 500,
                    netoGravadoTotal: 400 // Exactamente igual
                }
            },
            {
                normalizedData: {
                    cuit: '20222222224',
                    tipo_cbte: 1,
                    pdv: 1,
                    nroDesde: 100,
                    nroHasta: 100,
                    moneda: 'PES',
                    total: 550, // Importe distinto -> Enmienda
                    netoGravadoTotal: 450
                }
            },
            {
                normalizedData: {
                    cuit: '20222222224',
                    tipo_cbte: 1,
                    pdv: 1,
                    nroDesde: 101, // Nuevo comprobante
                    nroHasta: 101,
                    moneda: 'PES',
                    total: 100
                }
            }
        ];

        const staged = await stageImport({
            incomingRows,
            existingRecords,
            context,
            fingerprintProvider: provider
        });

        expect(staged.length).toBe(3);
        expect(staged[0].status).toBe('EXACT_DUPLICATE');
        expect(staged[1].status).toBe('POSSIBLE_AMENDMENT');
        expect(staged[2].status).toBe('ACCEPTED');
    });

    it('should error if provider is missing', async () => {
        await expect(stageImport({ incomingRows: [], existingRecords: [], context: { tenant: '1' } }))
            .rejects.toThrow(/fingerprintProvider es obligatorio/);
    });
});
