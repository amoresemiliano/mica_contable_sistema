import { normalizeDecimal } from './importService.js';

/**
 * Política de Hash:
 * - Serialización: JSON.stringify de un array canónico.
 * - Campos: netoGravadoTotal, netoNoGravado, exento, otrosTributos, totalIva, importeTotal, moneda, tipoCambio, alicuotas.
 * - Orden: Fijo en el array. Alícuotas ordenadas por tasa, base, importe.
 * - Separación: Estructura JSON.
 */
export function buildCanonicalFiscalPayload(rowData) {
    if (!rowData) return 'null';
    
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
    
    return JSON.stringify(canonicalArray);
}

export async function buildFiscalFingerprint(
    normalizedData,
    fingerprintProvider
) {
    if (!fingerprintProvider?.digest) {
        throw new Error("Fingerprint provider obligatorio (se requiere función digest)");
    }

    const payload = buildCanonicalFiscalPayload(normalizedData);
    return fingerprintProvider.digest(payload);
}
