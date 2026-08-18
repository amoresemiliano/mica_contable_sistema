

import { buildFiscalFingerprint } from './fiscalFingerprint.js';

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
export async function stageImport({ incomingRows, existingRecords, context, fingerprintProvider }) {
    if (!fingerprintProvider) throw new Error("fingerprintProvider es obligatorio");
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

    for (const row of incomingRows) {
        if (row.errors && row.errors.length > 0) {
            stagedResults.push({ ...row, status: 'INVALID' });
            continue;
        }

        const data = row.normalizedData;
        if (!data) {
            stagedResults.push({ ...row, status: 'INVALID' });
            continue;
        }

        const identityKey = buildRecordIdentity(data, context);
        const incomingHash = await buildFiscalFingerprint(data, fingerprintProvider);
        const existing = existingIndex[identityKey];

        if (existing) {
            const existingHash = await buildFiscalFingerprint(existing, fingerprintProvider);
            
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
    }

    return stagedResults;
}
