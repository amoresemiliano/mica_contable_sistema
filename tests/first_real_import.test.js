import { parseDelimitedText } from '../src/js/adapters/textAdapter.js';
import { parseArcaRows } from '../src/js/core/parsers/arcaParser.js';
import { stageImport } from '../src/js/core/services/importService.js';
import { createNodeFingerprintProvider } from './helpers/nodeFingerprintProvider.js';

describe('First Real Import - Fase 1', () => {
    const csvSemicolons = `Fecha;Tipo;Punto de Venta;Numero Desde;Numero Hasta;Doc. Emisor Tipo;Doc. Emisor Nro;Denominacion Emisor;Imp. Total;Total IVA;Moneda;Tipo Cambio
01/07/2026;1;1;123;123;80;30711111112;PROVEEDOR S.A.;1210,00;210,00;PES;1,000000`;

    const csvCommas = `Fecha,Tipo,Punto de Venta,Numero Desde,Numero Hasta,Doc. Emisor Tipo,Doc. Emisor Nro,Denominacion Emisor,Imp. Total,Total IVA,Moneda,Tipo Cambio
01/07/2026,1,1,123,123,80,30711111112,PROVEEDOR S.A.,1210.00,210.00,PES,1.000000`;

    test('A. CSV ARCA separado por punto y coma (;) autodetecta delimitador', () => {
        const rows = parseDelimitedText(csvSemicolons);
        expect(rows.length).toBe(2);
        expect(rows[0].length).toBeGreaterThan(5);
        expect(rows[0][0]).toBe('Fecha');
        expect(rows[0][1]).toBe('Tipo');
    });

    test('B. CSV ARCA separado por coma (,) autodetecta delimitador', () => {
        const rows = parseDelimitedText(csvCommas);
        expect(rows.length).toBe(2);
        expect(rows[0].length).toBeGreaterThan(5);
        expect(rows[0][0]).toBe('Fecha');
        expect(rows[0][1]).toBe('Tipo');
    });

    test('C. Parse normalizado de ARCA produce contrato explícito (total, cuit, razonSocial, etc)', () => {
        const rows = parseDelimitedText(csvSemicolons);
        const parsed = parseArcaRows(rows, { tipo: 'COMPRAS', batchId: 100 });
        
        expect(parsed.length).toBe(1);
        expect(parsed[0].errors).toEqual([]);
        
        const data = parsed[0].normalizedData;
        expect(data.fecha).toBe('01/07/2026');
        expect(data.cuit).toBe('30711111112');
        expect(data.razonSocial).toBe('PROVEEDOR S.A.');
        expect(data.tipo_cbte).toBe(1);
        expect(data.pdv).toBe(1);
        expect(data.nroDesde).toBe(123);
        expect(data.total).toBe(1210);
        expect(data.totalIva).toBe(210);
    });

    test('D. Transformación normalized -> UI genera todos los campos requeridos por UI y Staging', () => {
        const rows = parseDelimitedText(csvSemicolons);
        const parsed = parseArcaRows(rows, { tipo: 'COMPRAS', batchId: 100 });
        const item = parsed[0].normalizedData;
        const tenant = '30710536461';

        const uiItem = {
            id: 'test-uuid-1',
            fecha: item.fecha,
            tipo: 'recibido',
            tipoOperacion: 'COMPRA',
            tenant: tenant,
            cuit: item.cuit,
            razonSocial: item.razonSocial,
            comprobante: `${item.tipo_cbte}-${item.pdv}-${item.nroDesde}`,
            tipo_cbte: item.tipo_cbte,
            pdv: item.pdv,
            nroDesde: item.nroDesde,
            nroHasta: item.nroHasta,
            moneda: item.moneda,
            tipoCambio: item.tipoCambio,
            total: item.total,
            importe: item.total,
            importeTotal: item.total,
            totalIva: item.totalIva,
            iva: item.totalIva,
            otrosTributos: item.otrosTributos || 0,
            exento: item.exento || 0,
            netoNoGravado: item.netoNoGravado || 0,
            categoria: null,
            sugerida: false,
            confirmada: false,
            rawRecord: item
        };

        expect(uiItem.tenant).toBe('30710536461');
        expect(uiItem.tipoOperacion).toBe('COMPRA');
        expect(uiItem.cuit).toBe('30711111112');
        expect(uiItem.razonSocial).toBe('PROVEEDOR S.A.');
        expect(uiItem.comprobante).toBe('1-1-123');
        expect(uiItem.total).toBe(1210);
        expect(uiItem.importe).toBe(1210);
    });

    test('E y F. stageImport procesa registros previos (existingRecords) y detecta EXACT_DUPLICATE sin fallar por tenant', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const rows = parseDelimitedText(csvSemicolons);
        const incomingRows = parseArcaRows(rows, { tipo: 'COMPRAS', batchId: 101 });
        const context = { tenant: '30710536461', tipoOperacion: 'COMPRA' };

        // Importación 1 (store vacío)
        const stage1 = await stageImport({
            incomingRows,
            existingRecords: [],
            context,
            fingerprintProvider
        });

        expect(stage1[0].status).toBe('ACCEPTED');

        // Simular que el item importado 1 está en appStore.items
        const existingUIStoreItems = [{
            id: 'test-uuid-1',
            fecha: '01/07/2026',
            tipo: 'recibido',
            tipoOperacion: 'COMPRA',
            tenant: '30710536461',
            cuit: '30711111112',
            razonSocial: 'PROVEEDOR S.A.',
            comprobante: '1-1-123',
            tipo_cbte: 1,
            pdv: 1,
            nroDesde: 123,
            nroHasta: 123,
            moneda: 'PES',
            tipoCambio: 1,
            total: 1210,
            importe: 1210,
            importeTotal: 1210,
            totalIva: 210,
            iva: 210,
            otrosTributos: 0,
            exento: 0,
            netoNoGravado: 0,
            alicuotas: []
        }];

        // Importación 2 (mismo archivo subido por segunda vez)
        const stage2 = await stageImport({
            incomingRows,
            existingRecords: existingUIStoreItems,
            context,
            fingerprintProvider
        });

        expect(stage2[0].status).toBe('EXACT_DUPLICATE');
    });
});
