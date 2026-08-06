import crypto from 'crypto';

/**
 * Normalización decimal determinista.
 * Distingue nulo, vacío, y cero explícito.
 * Escala 2 por defecto.
 */
export function normalizeDecimal(value, scale = 2) {
    if (value === null || value === undefined) return 'null';
    if (value === '') return 'empty';
    const num = Number(value);
    if (Number.isNaN(num)) return 'invalid';
    return num.toFixed(scale);
}

/**
 * Identidad ARCA
 */
/**
 * Normaliza y valida un CUIT de forma estricta.
 */
function normalizeCuit(value) {
    const str = (value || '').toString().trim();
    if (!str) throw new Error("CUIT obligatorio");
    
    // Acepta sólo 11 dígitos continuos o el formato XX-XXXXXXXX-X
    const validFormat = /^(?:\d{11}|\d{2}-\d{8}-\d{1})$/;
    if (!validFormat.test(str)) {
        throw new Error("CUIT de contraparte inválido (debe tener 11 dígitos continuos o formato XX-XXXXXXXX-X)");
    }
    
    return str.replace(/-/g, '');
}

/**
 * Normaliza identificadores fiscales numéricos sin perder precisión.
 */
export function normalizeUnsignedIntegerIdentifier(value, fieldName) {
    if (value === undefined || value === null) return null;
    const str = value.toString().trim();
    if (str === '') return null;
    
    if (!/^\d+$/.test(str)) {
        throw new Error(`Campo ${fieldName} inválido: debe contener sólo dígitos enteros (se rechazan letras, decimales, notación científica y signos)`);
    }
    
    const stripped = str.replace(/^0+/, '');
    return stripped === '' ? '0' : stripped;
}

/**
 * Identidad ARCA
 */
export function buildRecordIdentity(normalizedData, context) {
    if (!context || !context.tenant) {
        throw new Error("Contexto con 'tenant' es obligatorio.");
    }
    
    const tenantId = context.tenant.trim();
    if (!tenantId) throw new Error("tenantId obligatorio");

    const direccionOperacion = context.tipoOperacion === 'VENTA' ? 'VENTA' : (context.tipoOperacion === 'COMPRA' ? 'COMPRA' : null);
    if (!direccionOperacion) throw new Error("direccionOperacion obligatoria y debe ser COMPRA o VENTA");
    
    const cuitContraparte = normalizeCuit(normalizedData.cuit);
    
    const tipoComprobante = normalizeUnsignedIntegerIdentifier(normalizedData.tipo_cbte, 'tipoComprobante');
    if (!tipoComprobante) throw new Error("tipo de comprobante obligatorio");
    
    const puntoDeVenta = normalizeUnsignedIntegerIdentifier(normalizedData.pdv, 'puntoDeVenta');
    if (!puntoDeVenta) throw new Error("punto de venta obligatorio");
    
    const numeroDesde = normalizeUnsignedIntegerIdentifier(normalizedData.nroDesde, 'numeroDesde');
    if (!numeroDesde) throw new Error("número desde obligatorio");
    
    let numeroHastaFinal = normalizeUnsignedIntegerIdentifier(normalizedData.nroHasta, 'numeroHasta');
    if (!numeroHastaFinal) {
        numeroHastaFinal = numeroDesde;
    }
    
    const moneda = (normalizedData.moneda || 'PES').toString().toUpperCase().trim();

    return JSON.stringify([
        tenantId,
        direccionOperacion,
        cuitContraparte,
        tipoComprobante,
        puntoDeVenta,
        numeroDesde,
        numeroHastaFinal,
        moneda
    ]);
}

/**
 * Política de Hash:
 * - Serialización: JSON.stringify de un array canónico.
 * - Campos: netoGravadoTotal, netoNoGravado, exento, otrosTributos, totalIva, importeTotal, moneda, tipoCambio, alicuotas.
 * - Orden: Fijo en el array. Alícuotas ordenadas por tasa, base, importe.
 * - Separación: Estructura JSON.
 * - Algoritmo Final: SHA-256 en formato hexadecimal.
 */
export function buildFiscalFingerprint(rowData) {
    if (!rowData) return crypto.createHash('sha256').update('null').digest('hex');
    
    let alicuotas = rowData.alicuotas || [];
    
    // Canonicalize alicuotas and sort
    const canonicalAlicuotas = alicuotas.map(a => ({
        tasa: normalizeDecimal(a.tasa, 4),
        baseImponible: normalizeDecimal(a.baseImponible, 2),
        importeIva: normalizeDecimal(a.importeIva, 2)
    })).sort((a, b) => {
        if (a.tasa !== b.tasa) return a.tasa.localeCompare(b.tasa);
        if (a.baseImponible !== b.baseImponible) return a.baseImponible.localeCompare(b.baseImponible);
        return a.importeIva.localeCompare(b.importeIva);
    });
    
    const canonicalArray = [
        normalizeDecimal(rowData.netoGravadoTotal, 2),
        normalizeDecimal(rowData.netoNoGravado, 2),
        normalizeDecimal(rowData.exento, 2),
        normalizeDecimal(rowData.otrosTributos, 2),
        normalizeDecimal(rowData.totalIva, 2),
        normalizeDecimal(rowData.importeTotal || rowData.total, 2),
        rowData.moneda || 'PES',
        normalizeDecimal(rowData.tipoCambio, 6),
        canonicalAlicuotas
    ];
    
    const serialized = JSON.stringify(canonicalArray);
    return crypto.createHash('sha256').update(serialized).digest('hex');
}

/**
 * Crea una vista segura del registro (trazabilidad)
 */
export function toSafeTrace(record) {
    if (!record) return null;
    return {
        batchId: record.batchId,
        sourceFileId: record.sourceFileId,
        sourceDisplayName: record.sourceDisplayName || null,
        sourceRowNumber: record.sourceRowNumber,
        errors: record.errors || [],
        warnings: record.warnings || [],
        status: record.status,
        identityKey: record.identityKey
    };
}

/**
 * Orquestador puro de importación (staging).
 */
export function stageImport({ incomingRows, existingRecords, context }) {
    if (!context || !context.tenant) {
        throw new Error("Contexto con 'tenant' es obligatorio.");
    }
    
    const existingIndex = {};
    (existingRecords || []).forEach(record => {
        // En staging se asume que existents tienen datos listos
        const idKey = buildRecordIdentity(record, { tenant: record.tenant, tipoOperacion: record.tipoOperacion });
        existingIndex[idKey] = record;
    });

    const stagedResults = [];

    incomingRows.forEach(row => {
        if (row.errors && row.errors.length > 0) {
            stagedResults.push({ ...row, status: 'INVALID' });
            return;
        }

        const data = row.normalizedData;
        if (!data) {
            stagedResults.push({ ...row, status: 'INVALID' });
            return;
        }

        const identityKey = buildRecordIdentity(data, context);
        const incomingHash = buildFiscalFingerprint(data);
        const existing = existingIndex[identityKey];

        if (existing) {
            const existingHash = buildFiscalFingerprint(existing);
            
            if (incomingHash === existingHash) {
                stagedResults.push({ ...row, status: 'EXACT_DUPLICATE', identityKey });
            } else {
                stagedResults.push({ ...row, status: 'POSSIBLE_AMENDMENT', identityKey, previousHash: existingHash, newHash: incomingHash });
            }
        } else {
            stagedResults.push({ ...row, status: 'ACCEPTED', identityKey });
            existingIndex[identityKey] = {
                ...data,
                tenant: context.tenant,
                tipoOperacion: context.tipoOperacion
            };
        }
    });

    return stagedResults;
}
