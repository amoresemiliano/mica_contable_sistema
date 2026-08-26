import { parseDelimitedText } from '../src/js/adapters/textAdapter.js';
import { parseArcaRows } from '../src/js/core/parsers/arcaParser.js';
import { parseArbaText } from '../src/js/core/parsers/arbaParser.js';
import { parseIvaPerceptions } from '../src/js/core/parsers/ivaPerceptionParser.js';
import { parseBankRows } from '../src/js/core/parsers/bankParser.js';
import { parseSalaryRows } from '../src/js/core/parsers/salaryParser.js';
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

    const csvEmitidosSemicolons = `Fecha;Tipo;Punto de Venta;Numero Desde;Numero Hasta;Doc. Receptor Tipo;Doc. Receptor Nro;Denominacion Receptor;Imp. Total;Total IVA;Moneda;Tipo Cambio
05/07/2026;1;1;123;123;80;30799999999;CLIENTE S.A.;2420,00;420,00;PES;1,000000`;

    const csvEmitidosCompradorCommas = `Fecha,Tipo,Punto de Venta,Numero Desde,Numero Hasta,Doc. Comprador Tipo,Doc. Comprador Nro,Denominacion Comprador,Imp. Total,Total IVA,Moneda,Tipo Cambio
05/07/2026,1,1,123,123,80,30799999999,CLIENTE S.A.,2420.00,420.00,PES,1.000000`;

    test('G. CSV ARCA Emitidos (Ventas) separado por ; autodetecta delimitador y mapea receptor', () => {
        const rows = parseDelimitedText(csvEmitidosSemicolons);
        const parsed = parseArcaRows(rows, { tipoOperacion: 'VENTA', batchId: 200 });

        expect(parsed.length).toBe(1);
        expect(parsed[0].errors).toEqual([]);
        const data = parsed[0].normalizedData;
        expect(data.fecha).toBe('05/07/2026');
        expect(data.cuit).toBe('30799999999');
        expect(data.razonSocial).toBe('CLIENTE S.A.');
        expect(data.total).toBe(2420);
        expect(data.netoGravado).toBe(2000);
    });

    test('H. CSV ARCA Emitidos separado por , autodetecta delimitador y mapea comprador', () => {
        const rows = parseDelimitedText(csvEmitidosCompradorCommas);
        const parsed = parseArcaRows(rows, { tipoOperacion: 'VENTA', batchId: 201 });

        expect(parsed.length).toBe(1);
        expect(parsed[0].errors).toEqual([]);
        const data = parsed[0].normalizedData;
        expect(data.cuit).toBe('30799999999');
        expect(data.razonSocial).toBe('CLIENTE S.A.');
        expect(data.total).toBe(2420);
    });

    test('I y J. stageImport para VENTA genera ACCEPTED y detecta EXACT_DUPLICATE en re-upload', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const rows = parseDelimitedText(csvEmitidosSemicolons);
        const incomingRows = parseArcaRows(rows, { tipoOperacion: 'VENTA', batchId: 202 });
        const context = { tenant: '30710536461', tipoOperacion: 'VENTA' };

        const stage1 = await stageImport({
            incomingRows,
            existingRecords: [],
            context,
            fingerprintProvider
        });
        expect(stage1[0].status).toBe('ACCEPTED');

        const existingUIStoreItems = [{
            id: 'test-uuid-venta-1',
            fecha: '05/07/2026',
            tipo: 'emitido',
            tipoOperacion: 'VENTA',
            tenant: '30710536461',
            cuit: '30799999999',
            razonSocial: 'CLIENTE S.A.',
            comprobante: '1-1-123',
            tipo_cbte: 1,
            pdv: 1,
            nroDesde: 123,
            nroHasta: 123,
            moneda: 'PES',
            tipoCambio: 1,
            total: 2420,
            importe: 2420,
            importeTotal: 2420,
            totalIva: 420,
            iva: 420,
            otrosTributos: 0,
            exento: 0,
            netoNoGravado: 0,
            noGravado: 0,
            netoGravado: 2000,
            alicuotas: []
        }];

        const stage2 = await stageImport({
            incomingRows,
            existingRecords: existingUIStoreItems,
            context,
            fingerprintProvider
        });
        expect(stage2[0].status).toBe('EXACT_DUPLICATE');
    });

    test('K. Coexistencia de registros COMPRA y VENTA con mismo comprobante (1-1-123) NO genera falso duplicado', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const rowsVenta = parseDelimitedText(csvEmitidosSemicolons);
        const incomingVentas = parseArcaRows(rowsVenta, { tipoOperacion: 'VENTA', batchId: 203 });
        const contextVenta = { tenant: '30710536461', tipoOperacion: 'VENTA' };

        // Store contiene una COMPRA con el mismo número de comprobante 1-1-123
        const existingCompraItem = [{
            id: 'test-uuid-compra-1',
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

        const staged = await stageImport({
            incomingRows: incomingVentas,
            existingRecords: existingCompraItem,
            context: contextVenta,
            fingerprintProvider
        });

        // Debe ser ACCEPTED, no confundirse con la COMPRA existente
        expect(staged[0].status).toBe('ACCEPTED');
    });

    test('L. Percepciones ARBA TXT de 70 caracteres parsea CUIT, fecha, comprobante y monto sin undefined', () => {
        const arbaLine = "0290230-68273765-016/06/20260015100000000000000426651FA000000028382,92";
        const parsed = parseArbaText(arbaLine, { jurisdiccion: 'ARBA' });
        expect(parsed.length).toBe(1);
        expect(parsed[0].errors).toEqual([]);

        const norm = parsed[0].normalizedData;
        expect(norm.cuit).toBe('30682737650');
        expect(norm.fecha).toBe('16/06/2026');
        expect(norm.period).toBe('2026-06');
        expect(norm.sucursal).toBe('0015');
        expect(norm.comprobante).toBe('100000000000000426651FA0');
        expect(norm.monto).toBe(28382.92);
        expect(norm.tipo).toBe('percepcion');
        expect(norm.fuente).toBe('ARBA');
    });

    test('M. Sueldos Acompy XLSX extrae fila de TOTALES y período de forma limpia', () => {
        const sampleRows = [
            ["BORRADOR SUELDOS"],
            ["Empresa", "JOB TRAINING S R L"],
            ["Periodo", "05/2026"],
            ["Totales por Concepto Agrupado por Empleado"],
            ["Legajo", "Apellido y Nombre", "CUIL", "Sueldo Mensual", "Remunerativo", "Redondeo", "No Remunerativo", "Jubilacion", "Ley 19032", "Obra Social", "Retenciones", "Total"],
            ["00000001", "PIRSCH JORGE ANTONIO", 20163237114, 620000, 620000, 0, 0, 68200, 18600, 37200, 124000, 496000],
            [null, null, "Totales:", 620000, 620000, 0, 0, 68200, 18600, 37200, 124000, 496000]
        ];

        const results = parseSalaryRows(sampleRows);
        expect(results.length).toBe(1);
        expect(results[0].errors).toEqual([]);

        const norm = results[0].normalizedData;
        expect(norm.periodo).toBe('05/2026');
        expect(norm.remunerativo).toBe(620000);
        expect(norm.sueldoNeto).toBe(496000);
        expect(norm.sueldoBrutoCalculado).toBe(620000);
        expect(norm.sueldoBruto).toBe(620000);
        expect(norm.fuente).toBe('PAYROLL');
    });

    test('N. Percepciones IVA XLS parsea CUIT, fecha, certificado y monto correctamente', () => {
        const ivaRows = [
            ["CUIT Agente Ret./Perc.", "Denominación o Razón Social", "Impuesto", "Descripción Impuesto", "Régimen", "Descripción Régimen", "Fecha Ret./Perc.", "Número Certificado", "Descripción Operación", "Importe Ret./Perc.", "Número Comprobante", "Fecha Comprobante", "Descripción Comprobante", "Fecha Registración DJ Ag.Ret."],
            ["30500003193", "BANCO BBVA ARGENTINA S.A.", "767", "SICORE - RETENCIONES Y PERCEPCIONES - IMPUESTO AL VALOR AGRE", "493", "REG.PER.AL VALOR AGREGADO - EMPRESAS PROVEEDORAS.", "29/05/2026", "2137960", "PERCEPCION", 997.27, "0000010918741690", "29/05/2026", "OTRO COMPROBANTE", "12/06/2026"]
        ];

        const results = parseIvaPerceptions(ivaRows);
        expect(results.length).toBe(1);
        expect(results[0].errors).toEqual([]);

        const norm = results[0].normalizedData;
        expect(norm.cuit).toBe('30500003193');
        expect(norm.razonSocial).toBe('BANCO BBVA ARGENTINA S.A.');
        expect(norm.fecha).toBe('29/05/2026');
        expect(norm.comprobante).toBe('2137960');
        expect(norm.monto).toBe(997.27);
        expect(norm.fuente).toBe('IVA');
        expect(norm.jurisdiction).toBe('NACIONAL (IVA)');
    });

    test('O. BBVA Bank XLS parsea montos negativos de débito, números JS y combina concepto y detalle', () => {
        const bbvaRows = [
            ["Empresa: ", "JOB TRAINING S.R.L(30689920779)"],
            ["Cuenta: ", "133-004976/9(CC $)"],
            ["Sucursal: ", "133 - PARQUE INDUSTRIAL PILAR"],
            ["Saldo: ", "-11.404.622,84"],
            ["Movimientos de: ", "Ultimos 60 Días."],
            [],
            ["Fecha", "Fecha Valor", "Concepto", "Codigo", "Número Documento", "Oficina", "Crédito", "Débito", "Detalle"],
            ["29-05-2026", "29-05-2026", "SELLADO", "030", "", "133 - PARQUE INDUSTRIAL PILAR", "", -1073.43, "Saldo Disponible"],
            ["21-05-2026", "21-05-2026", "DEPOSITO", "001", "", "133 - PARQUE INDUSTRIAL PILAR", 50000, "", "CREDITO EN CUENTA"]
        ];

        const results = parseBankRows(bbvaRows);
        expect(results.length).toBe(2);
        expect(results[0].errors).toEqual([]);
        expect(results[1].errors).toEqual([]);

        const debitTx = results[0].normalizedData;
        expect(debitTx.fecha).toBe('29-05-2026');
        expect(debitTx.descripcion).toBe('SELLADO - Saldo Disponible');
        expect(debitTx.monto).toBe(1073.43);
        expect(debitTx.tipo).toBe('debit');

        const creditTx = results[1].normalizedData;
        expect(creditTx.fecha).toBe('21-05-2026');
        expect(creditTx.descripcion).toBe('DEPOSITO - CREDITO EN CUENTA');
        expect(creditTx.monto).toBe(50000);
        expect(creditTx.tipo).toBe('credit');
    });
});
