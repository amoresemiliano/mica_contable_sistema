/**
 * Parser para archivos de Percepciones/Retenciones IVA (.xls / .xlsx / .csv).
 * Soporta exportaciones de SICORE y de AFIP / ARCA (Impuesto 767 IVA).
 * 
 * @param {Array<Array<any>>} rows - Matriz de filas extraídas con SheetJS o parser CSV
 * @param {Object} context - Contexto opcional
 * @returns {Array<{sourceRowNumber: number, rawRow: Array<any>, errors: Array<string>, warnings: Array<string>, normalizedData: Object|null}>}
 */
export function parseIvaPerceptions(rows, context = {}) {
    const results = [];
    if (!rows || !Array.isArray(rows) || rows.length === 0) return results;

    let headerRowIdx = -1;
    let mapping = {};

    // Buscar fila de encabezado que contenga CUIT e Importe / Ret. / Perc.
    for (let i = 0; i < Math.min(rows.length, 10); i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row)) continue;
        const rowStr = row.map(cell => String(cell || '').toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")).join(' ');
        if (rowStr.includes('cuit') && (rowStr.includes('importe') || rowStr.includes('ret') || rowStr.includes('perc'))) {
            headerRowIdx = i;
            break;
        }
    }

    if (headerRowIdx === -1) {
        headerRowIdx = 0;
    }

    const headers = (rows[headerRowIdx] || []).map(cell => 
        String(cell || '').toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim()
    );

    headers.forEach((h, idx) => {
        if (h.includes('cuit')) mapping.cuit = idx;
        else if (h.includes('denominacion') || h.includes('razon social') || h.includes('agente')) {
            if (mapping.razonSocial === undefined) mapping.razonSocial = idx;
        }
        else if (h.includes('fecha ret') || h.includes('fecha perc') || h === 'fecha') {
            if (mapping.fecha === undefined) mapping.fecha = idx;
        }
        else if (h.includes('fecha comp') && mapping.fecha === undefined) mapping.fecha = idx;
        else if (h.includes('certificado')) mapping.certificado = idx;
        else if (h.includes('comprobante')) mapping.comprobante = idx;
        else if (h.includes('importe') || h.includes('monto')) mapping.importe = idx;
        else if (h.includes('impuesto') || h.includes('descripcion impuesto')) mapping.impuesto = idx;
        else if (h.includes('operacion') || h.includes('descripcion operacion')) mapping.operacion = idx;
    });

    for (let i = headerRowIdx + 1; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row) || row.length === 0) continue;

        const res = {
            sourceRowNumber: i + 1,
            rawRow: row,
            errors: [],
            warnings: [],
            normalizedData: null
        };

        const rawCuit = mapping.cuit !== undefined ? row[mapping.cuit] : null;
        const rawFecha = mapping.fecha !== undefined ? row[mapping.fecha] : null;
        const rawImporte = mapping.importe !== undefined ? row[mapping.importe] : null;

        if (!rawCuit && !rawFecha && !rawImporte) continue;

        const cleanCuit = String(rawCuit || '').replace(/\D/g, '');
        if (!/^\d{11}$/.test(cleanCuit)) {
            res.errors.push("CUIT inválido (debe tener 11 dígitos).");
        }

        let fechaStr = String(rawFecha || '').trim();
        if (!/^\d{2}\/\d{2}\/\d{4}$/.test(fechaStr)) {
            res.errors.push("Fecha inválida.");
        }

        let monto = 0;
        if (typeof rawImporte === 'number') {
            monto = rawImporte;
        } else if (rawImporte !== null && rawImporte !== undefined && rawImporte !== '') {
            let str = String(rawImporte).trim();
            if (str.includes('.') && str.includes(',')) str = str.replace(/\./g, '').replace(',', '.');
            else if (str.includes(',')) str = str.replace(',', '.');
            monto = parseFloat(str);
        }

        if (isNaN(monto) || monto <= 0) {
            res.errors.push("Importe inválido.");
        }

        if (res.errors.length === 0) {
            const parts = fechaStr.split('/');
            const period = parts.length === 3 ? `${parts[2]}-${parts[1]}` : '';
            const razonSocial = mapping.razonSocial !== undefined ? String(row[mapping.razonSocial] || '').trim() : 'AGENTE RETENCION/PERCEPCION';
            const comprobante = mapping.certificado !== undefined && row[mapping.certificado] 
                ? String(row[mapping.certificado]).trim() 
                : (mapping.comprobante !== undefined ? String(row[mapping.comprobante] || '').trim() : '');

            res.normalizedData = {
                cuit: cleanCuit,
                razonSocial,
                fecha: fechaStr,
                period,
                comprobante,
                monto,
                amount: monto,
                importe: monto,
                jurisdiction: 'NACIONAL (IVA)',
                fuente: 'IVA',
                tipo: 'percepcion'
            };
        }

        results.push(res);
    }

    return results;
}
