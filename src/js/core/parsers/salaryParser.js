/**
 * Función pura que parsea una matriz de filas (proveniente del Excel de sueldos Acompy)
 * @param {Array<Array<any>>} rows - Filas extraídas de la planilla (Array of Arrays)
 * @param {Object} context - Configuración u opciones adicionales
 */
export function parseSalaryRows(rows, context = {}) {
    const results = [];
    
    // Primero, identificar cabeceras. Asumiremos la primera fila con algo válido o donde estén "TOTALES" referenciados.
    // Como Acompy tiene cabeceras como "Legajo", "Remunerativo", buscamos su posición relativas.
    let headerRowIdx = -1;
    let headers = [];
    let mapping = {};
    
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
        
        // Buscar texto "TOTALES" o "TOTALES:" en cualquier columna excluyendo "SUBTOTAL"
        const hasTotals = row.some(cell => {
            if (typeof cell !== 'string') return false;
            const up = cell.toUpperCase();
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
    
    const cleanNumber = (val) => {
        if (!val) return 0;
        let str = String(val).replace(/\./g, '').replace(',', '.');
        return parseFloat(str) || 0;
    };
    
    // Extracción
    const remunerativo = mapping.remunerativo !== undefined ? cleanNumber(row[mapping.remunerativo]) : 0;
    const noRemunerativo = mapping.noRemunerativo !== undefined ? cleanNumber(row[mapping.noRemunerativo]) : 0;
    const anticipoSueldo = mapping.anticipoSueldo !== undefined ? cleanNumber(row[mapping.anticipoSueldo]) : 0;
    const sacProporcional = mapping.sacProporcional !== undefined ? cleanNumber(row[mapping.sacProporcional]) : 0;
    const aporteSindicalObligatorio = mapping.aporteSindicalObligatorio !== undefined ? cleanNumber(row[mapping.aporteSindicalObligatorio]) : 0;
    const faecys = mapping.faecys !== undefined ? cleanNumber(row[mapping.faecys]) : 0;
    const sueldoNeto = mapping.sueldoNeto !== undefined ? cleanNumber(row[mapping.sueldoNeto]) : 0;

    // Cálculo Bruto = Remunerativo + No Remunerativo + Anticipo
    // (SAC ya está en Remunerativo según el contador)
    const sueldoBrutoCalculado = remunerativo + noRemunerativo + anticipoSueldo;
    const aporteSindicalCalculado = aporteSindicalObligatorio + faecys;

    results.push({
        sourceRowNumber: target.rowIndex + 1,
        rawRow: row, // o JSON.stringify(row) si se prefiere seguro
        errors: [],
        warnings: (mapping.sueldoNeto === undefined) ? ["Columna 'Total' (neto) no detectada claramente."] : [],
        normalizedData: {
            remunerativo,
            noRemunerativo,
            anticipoSueldo,
            sacProporcional,
            aporteSindicalObligatorio,
            faecys,
            sueldoNeto,
            sueldoBrutoCalculado,
            aporteSindicalCalculado
        },
        batchId
    });

    return results;
}
