import { parseDelimitedText } from '../src/js/adapters/textAdapter.js';
import { parseArcaRows } from '../src/js/core/parsers/arcaParser.js';
import { parseArbaText } from '../src/js/core/parsers/arbaParser.js';
import { parseSalaryRows } from '../src/js/core/parsers/salaryParser.js';
import { parseBankRows } from '../src/js/core/parsers/bankParser.js';
import { normalizeDecimal, stageImport, toSafeTrace, buildRecordIdentity } from '../src/js/core/services/importService.js';
import { createTenantConfig, TIPO_IVA, PERIODO_CONTABLE } from '../src/js/core/config/tenantConfig.js';
import { createNodeFingerprintProvider } from './helpers/nodeFingerprintProvider.js';
import {
    ARBA_FIXTURES,
    ARCA_COMPRAS_30,
    ARCA_VENTAS_19,
    ARCA_SIN_HEADER,
    ARCA_COL_AUSENTE,
    ARCA_IMPORTE_INVALIDO,
    ARCA_CAMPO_OBLIGATORIO_VACIO,
    ARCA_VARIAS_ALICUOTAS,
    ARCA_MONEDA_EXTRANJERA_SIN_TC,
    BBVA_DESPLAZADO,
    BBVA_SIMULTANEO,
    BBVA_VACIOS,
    BBVA_SOLO_CREDITO,
    BBVA_SIN_ENCABEZADO,
    BBVA_DOS_CANDIDATOS,
    BBVA_SIRCREB,
    BBVA_COMISION,
    ACOMPY_JUNIO_SAC,
    ACOMPY_MAYO_SIN_SAC,
    ACOMPY_SIN_TOTALES,
    ACOMPY_MULTIPLES_TOTALES,
    ACOMPY_TOTALES_FUERA_DE_COLUMNA_1,
    ACOMPY_COLUMNA_OPCIONAL_AUSENTE,
    ACOMPY_SUBTOTAL
} from './fixtures/synthetic.js';

describe('ARBA Parser', () => {
    test('ARBA válida de 70 caracteres', () => {
        const result = parseArbaText(ARBA_FIXTURES.valid)[0];
        expect(result.errors.length).toBe(0);
        expect(result.normalizedData.cuit).toBe("30711111112");
    });
    test('Línea corta arroja error', () => {
        expect(parseArbaText(ARBA_FIXTURES.short)[0].errors.length).toBeGreaterThan(0);
    });
    test('Línea larga arroja error', () => {
        expect(parseArbaText(ARBA_FIXTURES.long)[0].errors.length).toBeGreaterThan(0);
    });
    test('CUIT inválido detectado', () => {
        expect(parseArbaText(ARBA_FIXTURES.invalidCuit)[0].errors).toContain("Formato de CUIT inválido");
    });
    test('Fecha inválida', () => {
        expect(parseArbaText(ARBA_FIXTURES.invalidDate)[0].errors.length).toBeGreaterThan(0);
    });
    test('Monto con formato inválido', () => {
        expect(parseArbaText(ARBA_FIXTURES.invalidMonto)[0].errors.length).toBeGreaterThan(0);
    });
    test('Padding conservado', () => {
        // En ARBA, la fila misma es el padding (se guarda como rowString / rawRow)
        const res = parseArbaText(ARBA_FIXTURES.valid)[0];
        expect(res.rawRow).toBe(ARBA_FIXTURES.valid);
    });
    test('Código inicial conservado', () => {
        const res = parseArbaText(ARBA_FIXTURES.valid)[0];
        expect(res.rawRow.substring(0,8)).toBe("00000000"); // Asumiendo que asi es el string
    });
});

describe('ARCA Parser', () => {
    test('ARCA Compras 30', () => {
        const results = parseArcaRows(ARCA_COMPRAS_30, { tipo: 'COMPRAS' });
        expect(results[0].normalizedData.cuit).toBe("30711111112");
    });
    test('ARCA Ventas 19', () => {
        const results = parseArcaRows(ARCA_VENTAS_19, { tipo: 'VENTAS' });
        expect(results[0].normalizedData.cuit).toBe("30722222223");
    });
    test('Sin Encabezado devuelve error', () => {
        expect(parseArcaRows(ARCA_SIN_HEADER)[0].errors).toContain("No se encontró el encabezado estructural de ARCA (Fecha, Punto de Venta, Imp. Total)");
    });
    test('Columna obligatoria ausente', () => {
        expect(parseArcaRows(ARCA_COL_AUSENTE)[0].errors).toContain("No se encontró el encabezado estructural de ARCA (Fecha, Punto de Venta, Imp. Total)");
    });
    test('Importe inválido', () => {
        const res = parseArcaRows(ARCA_IMPORTE_INVALIDO, { tipo: 'COMPRAS' });
        expect(res[0].errors.some(e => e.includes('Imp. Total contiene un valor no numérico inválido'))).toBeTruthy();
    });
    test('Campo obligatorio vacío', () => {
        const res = parseArcaRows(ARCA_CAMPO_OBLIGATORIO_VACIO, { tipo: 'COMPRAS' });
        expect(res[0].errors.some(e => e.includes('está vacío o es nulo'))).toBeTruthy();
    });
    test('Varias alícuotas', () => {
        const res = parseArcaRows(ARCA_VARIAS_ALICUOTAS, { tipo: 'COMPRAS' });
        expect(res[0].normalizedData.alicuotas.length).toBeGreaterThan(1);
    });
    test('Trazabilidad por fila', () => {
        const res = parseArcaRows(ARCA_COMPRAS_30, { tipo: 'COMPRAS' });
        expect(res[0].sourceRowNumber).toBe(2);
    });
    test('Moneda extranjera sin tipo de cambio', () => {
        const res = parseArcaRows(ARCA_MONEDA_EXTRANJERA_SIN_TC, { tipo: 'COMPRAS' });
        expect(res[0].errors).toContain("Tipo de cambio es obligatorio para moneda extranjera.");
    });
});

describe('BBVA Parser', () => {
    test('BBVA encabezado desplazado', () => {
        const res = parseBankRows(BBVA_DESPLAZADO);
        expect(res[0].normalizedData.monto).toBe(1000.50);
    });
    test('Ambos informados produce error', () => {
        const res = parseBankRows(BBVA_SIMULTANEO);
        expect(res[0].errors).toContain("Débito y Crédito informados simultáneamente.");
    });
    test('Ambos vacíos produce error', () => {
        const res = parseBankRows(BBVA_VACIOS);
        expect(res[0].errors).toContain("Débito y Crédito vacíos o inválidos.");
    });
    test('Solo crédito', () => {
        const res = parseBankRows(BBVA_SOLO_CREDITO);
        expect(res[0].normalizedData.tipo).toBe("credit");
        expect(res[0].normalizedData.monto).toBe(1000);
    });
    test('Sin encabezado (fallback 0) falla al no mapear cols correctas', () => {
        const res = parseBankRows(BBVA_SIN_ENCABEZADO);
        expect(res.length).toBe(0);
    });
    test('BBVA con dos candidatos', () => {
        const res = parseBankRows(BBVA_DOS_CANDIDATOS);
        expect(res[0].normalizedData.monto).toBe(100);
    });
    test('Señal SIRCREB', () => {
        const res = parseBankRows(BBVA_SIRCREB);
        expect(res[0].normalizedData.signals).toContain("SIRCREB");
    });
    test('Señal COMISION', () => {
        const res = parseBankRows(BBVA_COMISION);
        expect(res[0].normalizedData.signals).toContain("COMISION");
    });
    test('Preservación de sourceRowNumber', () => {
        const res = parseBankRows(BBVA_COMISION);
        expect(res[0].sourceRowNumber).toBeGreaterThan(0);
    });
});

describe('Salary Parser (Acompy)', () => {
    test('Totales normal', () => {
        const results = parseSalaryRows(ACOMPY_JUNIO_SAC);
        expect(results[0].normalizedData.sueldoBrutoCalculado).toBe(1700);
    });
    test('Sin Totales', () => {
        expect(parseSalaryRows(ACOMPY_SIN_TOTALES)[0].errors).toContain("No se encontró ninguna fila con 'TOTALES' o 'TOTALES:'");
    });
    test('Multiples Totales', () => {
        expect(parseSalaryRows(ACOMPY_MULTIPLES_TOTALES)[0].errors.length).toBeGreaterThan(0);
    });
    test('Totales fuera de columna 1', () => {
        const results = parseSalaryRows(ACOMPY_TOTALES_FUERA_DE_COLUMNA_1);
        expect(results[0].normalizedData.sueldoBrutoCalculado).toBe(1000);
    });
    test('Columna opcional ausente', () => {
        const results = parseSalaryRows(ACOMPY_COLUMNA_OPCIONAL_AUSENTE);
        // Debe funcionar asumiendo q la opcional no aportó al sueldoBruto
        expect(results[0].errors.length).toBe(0);
    });
    test('Componentes fuente conservados', () => {
        const results = parseSalaryRows(ACOMPY_JUNIO_SAC);
        expect(results[0].normalizedData.remunerativo).toBeDefined();
    });
    test('Derivados calculados', () => {
        const results = parseSalaryRows(ACOMPY_JUNIO_SAC);
        expect(results[0].normalizedData.sueldoBrutoCalculado).toBeDefined();
    });
    test('Subtotal y Totales coexistiendo (selecciona Totales)', () => {
        const results = parseSalaryRows(ACOMPY_SUBTOTAL);
        expect(results[0].errors.length).toBe(0);
        expect(results[0].normalizedData.sueldoNeto).toBe(1200);
        expect(results[0].normalizedData.remunerativo).toBe(1000);
    });

    test('SAC conservado sin doble suma', () => {
        // En parser puro de sueldos no se deduce ni suma SAC.
        const results = parseSalaryRows(ACOMPY_JUNIO_SAC);
        expect(results[0].normalizedData.sacProporcional).toBeDefined();
    });
});

describe('Tenant Config', () => {
    test('Configuración válida', () => {
        const config = createTenantConfig({
            condicionIva: TIPO_IVA.RESPONSABLE_INSCRIPTO,
            periodoContableDefault: PERIODO_CONTABLE.FECHA_MOVIMIENTO
        });
        expect(config.condicionIva).toBe(TIPO_IVA.RESPONSABLE_INSCRIPTO);
        expect(config.toleranciaTributos).toBe(5.0);
    });
    test('Valores por defecto se asignan correctamente', () => {
        const config = createTenantConfig({
            condicionIva: TIPO_IVA.MONOTRIBUTO,
            periodoContableDefault: PERIODO_CONTABLE.MANUAL
        });
        expect(config.toleranciaTributos).toBe(5.0);
        expect(config.tratamientoIvaComisiones).toBe(false);
    });
    test('Tolerancia negativa lanza error', () => {
        expect(() => createTenantConfig({
            condicionIva: TIPO_IVA.EXENTO,
            periodoContableDefault: PERIODO_CONTABLE.MANUAL,
            toleranciaTributos: -1.0
        })).toThrow("toleranciaTributos debe ser un número finito mayor o igual a 0");
    });
    test('Tolerancia NaN lanza error', () => {
        expect(() => createTenantConfig({
            condicionIva: TIPO_IVA.EXENTO,
            periodoContableDefault: PERIODO_CONTABLE.MANUAL,
            toleranciaTributos: NaN
        })).toThrow("toleranciaTributos debe ser un número finito mayor o igual a 0");
    });
    test('Tolerancia infinita lanza error', () => {
        expect(() => createTenantConfig({
            condicionIva: TIPO_IVA.EXENTO,
            periodoContableDefault: PERIODO_CONTABLE.MANUAL,
            toleranciaTributos: Infinity
        })).toThrow("toleranciaTributos debe ser un número finito mayor o igual a 0");
    });
    test('Propiedad desconocida lanza error identificando la propiedad', () => {
        expect(() => createTenantConfig({
            condicionIva: TIPO_IVA.EXENTO,
            periodoContableDefault: PERIODO_CONTABLE.MANUAL,
            propiedadInvalida123: true
        })).toThrow("Propiedad desconocida o no autorizada: propiedadInvalida123");
    });
});

describe('Import Service (Staging & Identity)', () => {
    const existing = [
        { tenant: 'TenantA', tipoOperacion: 'COMPRA', cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES', importeTotal: 100, totalIva: 21, alicuotas: [{tasa: 21, baseImponible: 100, importeIva: 21}] }
    ];

    test('Tenant ausente lanza error', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        await expect(stageImport({ incomingRows: [], existingRecords: [], context: {}, fingerprintProvider })).rejects.toThrow();
    });
    test('Estado INVALID', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const res = await stageImport({
            incomingRows: [{ errors: ['error grave'] }],
            existingRecords: [], context: { tenant: 'TenantA', tipoOperacion: 'COMPRA' }, fingerprintProvider
        });
        expect(res[0].status).toBe('INVALID');
    });
    
    // TESTS IDENTIDAD CANÓNICA
    test('15 y 00015 generan la misma identidad', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: '15', nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: '00015', nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toBe(id2);
    });
    test('pes y PES generan la misma identidad', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: ' pes ' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toBe(id2);
    });
    test('Espacios normalizables no cambian la identidad', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: ' 1 ', pdv: ' 15 ', nroDesde: ' 100 ', nroHasta: 100, moneda: 'PES' }, { tenant: ' T ', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toBe(id2);
    });
    test('Mismo contenido ejecutado dos veces produce el mismo resultado', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toBe(id2);
    });
    test('Tenant distinto produce identidad distinta', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T1', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T2', tipoOperacion: 'COMPRA' });
        expect(id1).not.toBe(id2);
    });
    test('Dirección distinta produce identidad distinta', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'VENTA' });
        expect(id1).not.toBe(id2);
    });
    test('Punto de venta realmente distinto produce identidad distinta', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const id2 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 16, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).not.toBe(id2);
    });
    test('CUIT inválido produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("CUIT de contraparte inválido");
    });
    test('Campo obligatorio ausente produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("tipo de comprobante obligatorio");
    });

    test('Número largo superior a MAX_SAFE_INTEGER se conserva exactamente', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: '9007199254740993', nroHasta: '9007199254740993', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toContain('9007199254740993');
    });
    test('1e3 produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: '1e3', nroHasta: '1e3', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("inválido: debe contener sólo dígitos enteros");
    });
    test('decimal produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: '15.5', nroHasta: '15.5', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("inválido: debe contener sólo dígitos enteros");
    });
    test('negativo produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: '-15', nroHasta: '-15', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("inválido: debe contener sólo dígitos enteros");
    });
    test('letras producen error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 'ABC', nroHasta: 'ABC', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("inválido: debe contener sólo dígitos enteros");
    });
    test('numeroHasta ausente usa numeroDesde', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        const parsed = JSON.parse(id1);
        expect(parsed[5]).toBe("100"); // numeroDesde
        expect(parsed[6]).toBe("100"); // numeroHastaFinal
    });
    test('numeroHasta presente pero inválido produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 'ABC', moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("inválido: debe contener sólo dígitos enteros");
    });
    test('CUIT de once dígitos es válido', () => {
        const id1 = buildRecordIdentity({ cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toContain('30711111112');
    });
    test('CUIT con guiones admitidos se normaliza', () => {
        const id1 = buildRecordIdentity({ cuit: '30-71111111-2', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' });
        expect(id1).toContain('30711111112');
        expect(id1).not.toContain('-');
    });
    test('CUIT con letras produce error', () => {
        expect(() => buildRecordIdentity({ cuit: '3071111111A', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("CUIT de contraparte inválido");
    });
    test('texto con CUIT embebido produce error', () => {
        expect(() => buildRecordIdentity({ cuit: 'CUIT 30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES' }, { tenant: 'T', tipoOperacion: 'COMPRA' }))
        .toThrow("CUIT de contraparte inválido");
    });

    test('Identidad exacta desde archivos diferentes (EXACT_DUPLICATE)', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const res = await stageImport({
            incomingRows: [{ normalizedData: { cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES', importeTotal: 100, totalIva: 21, alicuotas: [{tasa: 21, baseImponible: 100, importeIva: 21}] } }],
            existingRecords: existing, context: { tenant: 'TenantA', tipoOperacion: 'COMPRA' }, fingerprintProvider
        });
        expect(res[0].status).toBe('EXACT_DUPLICATE');
    });
    test('Misma identidad y distinta base imponible (POSSIBLE_AMENDMENT)', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const res = await stageImport({
            incomingRows: [{ normalizedData: { cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES', importeTotal: 100, totalIva: 21, alicuotas: [{tasa: 21, baseImponible: 50, importeIva: 21}] } }],
            existingRecords: existing, context: { tenant: 'TenantA', tipoOperacion: 'COMPRA' }, fingerprintProvider
        });
        expect(res[0].status).toBe('POSSIBLE_AMENDMENT');
    });
    test('Huella con diferente distribución por alícuota (POSSIBLE_AMENDMENT)', async () => {
        const fingerprintProvider = createNodeFingerprintProvider();
        const res = await stageImport({
            incomingRows: [{ normalizedData: { cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES', importeTotal: 121, netoGravadoTotal: 100, totalIva: 21, alicuotas: [{tasa: 10.5, baseImponible: 200, importeIva: 21}] } }],
            existingRecords: [{ tenant: 'TenantA', tipoOperacion: 'COMPRA', cuit: '30711111112', tipo_cbte: 1, pdv: 15, nroDesde: 100, nroHasta: 100, moneda: 'PES', importeTotal: 121, netoGravadoTotal: 100, totalIva: 21, alicuotas: [{tasa: 21, baseImponible: 100, importeIva: 21}] }], 
            context: { tenant: 'TenantA', tipoOperacion: 'COMPRA' }, fingerprintProvider
        });
        expect(res[0].status).toBe('POSSIBLE_AMENDMENT');
    });
    test('Normalización decimal distingue null, vacío y cero', () => {
        expect(normalizeDecimal(null)).toBe('null');
        expect(normalizeDecimal("")).toBe('empty');
        expect(normalizeDecimal(0)).toBe('0.00');
        expect(normalizeDecimal("10")).toBe('10.00');
        expect(normalizeDecimal("10.00")).toBe('10.00');
    });
    test('toSafeTrace preserva metadata segura y purga datos sensibles', () => {
        const record = { 
            rawRow: "SECRETO_BANCARIO_O_IMPOSITIVO", 
            sourceRowNumber: 1, 
            batchId: 10, 
            sourceFileName: "C:/datos/cliente_secreto.csv",
            sourceFileId: "FILE-1234",
            sourceDisplayName: "lote_ventas_001",
            cuit: "30711111112",
            nombresPersonales: "Juan Perez"
        };
        const safe = toSafeTrace(record);
        expect(safe.rawRow).toBeUndefined();
        expect(safe.sourceFileName).toBeUndefined();
        expect(safe.cuit).toBeUndefined();
        expect(safe.nombresPersonales).toBeUndefined();
        
        // No deben aparecer rutas locales
        expect(Object.values(safe).some(v => typeof v === 'string' && v.includes('C:/'))).toBe(false);
        
        expect(safe.sourceRowNumber).toBe(1);
        expect(safe.sourceFileId).toBe("FILE-1234");
        expect(safe.sourceDisplayName).toBe("lote_ventas_001");
    });
    test('toSafeTrace sin sourceDisplayName lo asigna null', () => {
        const record = { batchId: 10 };
        const safe = toSafeTrace(record);
        expect(safe.sourceDisplayName).toBeNull();
    });
});
