/**
 * Función pura que parsea una matriz de filas de banco (BBVA u otros genéricos).
 * @param {Array<Array<any>>} rows - Filas extraídas de la planilla
 * @param {Object} context - Configuración u opciones (ej. batchId)
 */
export function parseBankRows(rows, context = {}) {
    const results = [];
    const batchId = context.batchId || null;

    if (!rows || rows.length === 0) return results;

    let headerRowIdx = -1;
    let headers = [];
    let mapping = {};
    
    // Buscar fila con al menos 'fecha' y 'concepto/descripcion' y (debito/credito o importe)
    for (let i = 0; i < Math.min(rows.length, 20); i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row)) continue;
        
        let hasDate = false;
        let hasDesc = false;
        let hasAmount = false;

        row.forEach(cell => {
            const str = String(cell || '').toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
            if (str.includes('fecha') || str.includes('fec.')) hasDate = true;
            if (str.includes('concepto') || str.includes('descripcion') || str.includes('detalle')) hasDesc = true;
            if (str.includes('importe') || str.includes('monto') || str.includes('debito') || str.includes('credito')) hasAmount = true;
        });

        if (hasDate && hasDesc && hasAmount) {
            headerRowIdx = i;
            headers = row.map(h => String(h || '').trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""));
            break;
        }
    }

    if (headerRowIdx === -1) {
        headerRowIdx = 0;
        headers = (rows[0] || []).map(h => String(h || '').trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""));
    }

    headers.forEach((clean, idx) => {
        if (clean === 'fec. valor' || clean === 'fecha valor') mapping.fechaValor = idx;
        else if (clean.includes('fec.')) mapping.fecha = idx;
        else if (clean === 'fecha') mapping.fecha = idx;
        else if (clean.includes('concepto') || clean.includes('descripcion')) {
            if (mapping.concepto === undefined) mapping.concepto = idx;
        }
        else if (clean.includes('detalle')) mapping.detalle = idx;
        else if (clean === 'referencia' || clean === 'ref.' || clean.includes('referencia')) mapping.referencia = idx;
        else if (clean.includes('importe') || clean.includes('monto')) mapping.importe = idx;
        else if (clean.includes('debito') || clean.includes('egreso') || clean.includes('salida')) mapping.debito = idx;
        else if (clean.includes('credito') || clean.includes('ingreso') || clean.includes('entrada')) mapping.credito = idx;
        else if (clean === 'saldo' || clean.includes('saldo')) mapping.saldo = idx;
    });

    const checkStrictNumber = (val) => {
        if (val === null || val === undefined || val === '') return null;
        if (typeof val === 'number') return val;
        let str = String(val).trim();
        if (str.includes('.') && str.includes(',')) str = str.replace(/\./g, '').replace(',', '.');
        else if (str.includes(',')) str = str.replace(',', '.');
        const num = parseFloat(str);
        return isNaN(num) ? null : num;
    };

    for (let i = headerRowIdx + 1; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row) || row.length === 0) continue;

        const dateVal = mapping.fecha !== undefined ? row[mapping.fecha] : null;
        const fechaValorVal = mapping.fechaValor !== undefined ? row[mapping.fechaValor] : null;
        const referenciaVal = mapping.referencia !== undefined ? String(row[mapping.referencia] || '').trim() : '';
        const saldoVal = mapping.saldo !== undefined ? checkStrictNumber(row[mapping.saldo]) : null;
        
        const conceptoVal = mapping.concepto !== undefined ? String(row[mapping.concepto] || '').trim() : '';
        const detalleVal = mapping.detalle !== undefined ? String(row[mapping.detalle] || '').trim() : '';
        const descVal = [conceptoVal, detalleVal].filter(Boolean).join(' - ');

        if (!dateVal && !descVal) continue;

        let amount = 0;
        let isDebit = false;
        let isCredit = false;
        let amountErrors = [];

        if (mapping.importe !== undefined) {
            let rawAmt = checkStrictNumber(row[mapping.importe]);
            if (rawAmt === null) {
                amountErrors.push("Importe vacío o no numérico.");
            } else {
                amount = Math.abs(rawAmt);
                if (rawAmt < 0) isDebit = true;
                else if (rawAmt > 0) isCredit = true;
            }
        } else {
            let debValRaw = mapping.debito !== undefined ? row[mapping.debito] : null;
            let credValRaw = mapping.credito !== undefined ? row[mapping.credito] : null;
            
            let debVal = checkStrictNumber(debValRaw);
            let credVal = checkStrictNumber(credValRaw);
            
            const hasDeb = debVal !== null && Math.abs(debVal) > 0;
            const hasCred = credVal !== null && Math.abs(credVal) > 0;

            if (hasDeb && hasCred) {
                amountErrors.push("Débito y Crédito informados simultáneamente.");
            } else if (!hasDeb && !hasCred) {
                amountErrors.push("Débito y Crédito vacíos o inválidos.");
            } else if (hasDeb) {
                amount = Math.abs(debVal);
                isDebit = true;
            } else if (hasCred) {
                amount = Math.abs(credVal);
                isCredit = true;
            }
        }

        const rowString = row.join(' ').toUpperCase();
        let signals = [];
        if (rowString.includes('SIRCREB')) signals.push('SIRCREB');
        if (rowString.includes('COMISION') || rowString.includes('MANTENIMIENTO')) signals.push('COMISION');
        if (rowString.includes('IVA')) signals.push('IVA');
        if (rowString.includes('IIBB') || rowString.includes('INGRESOS BRUTOS')) signals.push('IIBB');

        results.push({
            sourceRowNumber: i + 1,
            rawRow: row,
            errors: amountErrors,
            warnings: [],
            normalizedData: {
                fecha: dateVal,
                fechaValor: fechaValorVal,
                descripcion: descVal,
                referencia: referenciaVal,
                saldo: saldoVal,
                monto: amount,
                tipo: isDebit ? 'debit' : (isCredit ? 'credit' : 'unknown'),
                signals
            },
            batchId
        });
    }

    return results;
}
