/**
 * Función pura que parsea una matriz de filas (proveniente del Excel de sueldos Acompy)
 * @param {Array<Array<any>>} rows - Filas extraídas de la planilla (Array of Arrays)
 * @param {Object} context - Configuración u opciones adicionales
 */
export function parseSalaryRows(rows, context = {}) {
    const results = [];

    let headerRowIdx = -1;
    let headers = [];
    let mapping = {};
    let periodo = context.periodo || null;

    // Buscar período en las primeras filas
    for (let i = 0; i < Math.min(rows.length, 10); i++) {
        const row = rows[i];
        if (Array.isArray(row)) {
            const rowStr = row.map(c => String(c || '')).join(' ');
            const match = rowStr.match(/(\d{2}\/\d{4})/);
            if (match) {
                periodo = match[1];
                break;
            }
        }
    }

    // Buscar cabecera
    for (let i = 0; i < Math.min(rows.length, 15); i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row)) continue;

        if (row.some(cell => {
            const str = String(cell || '').toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
            return str.includes('legajo') || str.includes('bruto') || str.includes('neto') || str.includes('remunerativo');
        })) {
            headerRowIdx = i;
            headers = row.map(h => String(h || '').trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""));
            break;
        }
    }

    if (headerRowIdx !== -1) {
        headers.forEach((clean, idx) => {
            if (clean === 'remunerativo') mapping.remunerativo = idx;
            else if (clean === 'no remunerativo') mapping.noRemunerativo = idx;
            else if (clean.includes('anticipo') || clean.includes('adelanto')) mapping.anticipoSueldo = idx;
            else if (clean === 'sac proporcional') mapping.sacProporcional = idx;
            else if (clean.includes('sindical') && !clean.includes('faecys')) mapping.aporteSindicalObligatorio = idx;
            else if (clean.includes('faecys')) mapping.faecys = idx;
            else if (clean === 'total' || clean.includes('neto')) mapping.sueldoNeto = idx;
        });
    }

    // Buscar fila de Totales
    let totalRowsMatched = [];
    for (let i = headerRowIdx + 1; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row)) continue;

        const hasTotals = row.some(cell => {
            if (!cell) return false;
            const up = String(cell).toUpperCase().trim();
            return (up === 'TOTALES' || up === 'TOTALES:') && !up.includes('SUBTOTAL');
        });

        if (hasTotals) {
            totalRowsMatched.push({ rowIndex: i, row });
        }
    }

    const batchId = context.batchId || null;

    if (totalRowsMatched.length === 0) {
        return [{
            sourceRowNumber: -1,
            rawRow: null,
            errors: ["No se encontró ninguna fila con 'TOTALES' o 'TOTALES:'"],
            warnings: [],
            normalizedData: null,
            batchId
        }];
    }

    if (totalRowsMatched.length > 1) {
         return [{
            sourceRowNumber: -1,
            rawRow: null,
            errors: [`Se encontraron ${totalRowsMatched.length} filas de totales. Se esperaba exactamente 1.`],
            warnings: [],
            normalizedData: null,
            batchId
        }];
    }

    const target = totalRowsMatched[0];
    const row = target.row;

    const parseNumberSafe = (val) => {
        if (val === null || val === undefined || val === '') return 0;
        if (typeof val === 'number') return val;
        let str = String(val).trim();
        if (str.includes('.') && str.includes(',')) {
            str = str.replace(/\./g, '').replace(',', '.');
        } else if (str.includes(',')) {
            str = str.replace(',', '.');
        }
        const num = parseFloat(str);
        return isNaN(num) ? 0 : num;
    };

    // Extracción
    const remunerativo = mapping.remunerativo !== undefined ? parseNumberSafe(row[mapping.remunerativo]) : 0;
    const noRemunerativo = mapping.noRemunerativo !== undefined ? parseNumberSafe(row[mapping.noRemunerativo]) : 0;
    const anticipoSueldo = mapping.anticipoSueldo !== undefined ? parseNumberSafe(row[mapping.anticipoSueldo]) : 0;
    const sacProporcional = mapping.sacProporcional !== undefined ? parseNumberSafe(row[mapping.sacProporcional]) : 0;
    const aporteSindicalObligatorio = mapping.aporteSindicalObligatorio !== undefined ? parseNumberSafe(row[mapping.aporteSindicalObligatorio]) : 0;
    const faecys = mapping.faecys !== undefined ? parseNumberSafe(row[mapping.faecys]) : 0;
    const sueldoNeto = mapping.sueldoNeto !== undefined ? parseNumberSafe(row[mapping.sueldoNeto]) : 0;

    const sueldoBrutoCalculado = remunerativo + noRemunerativo;
    const aporteSindicalCalculado = aporteSindicalObligatorio + faecys;

    results.push({
        sourceRowNumber: target.rowIndex + 1,
        rawRow: row,
        errors: [],
        warnings: (mapping.sueldoNeto === undefined) ? ["Columna 'Total' (neto) no detectada claramente."] : [],
        normalizedData: {
            periodo,
            remunerativo,
            noRemunerativo,
            anticipoSueldo,
            sacProporcional,
            aporteSindicalObligatorio,
            faecys,
            sueldoNeto,
            sueldoBrutoCalculado,
            aporteSindicalCalculado,
            sueldoBruto: sueldoBrutoCalculado,
            anticipos: anticipoSueldo,
            sindicatoAporte: aporteSindicalCalculado,
            fuente: 'PAYROLL',
            tipo: 'sueldo'
        },
        batchId
    });

    return results;
}
