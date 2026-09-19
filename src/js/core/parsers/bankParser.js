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
    let isHeaderless = false;
    
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

    if (headerRowIdx !== -1) {
        headers.forEach((clean, idx) => {
            if (clean === 'fec. valor' || clean === 'fecha valor') mapping.fechaValor = idx;
            else if (clean.includes('fec.') || clean === 'fecha') {
                if (mapping.fecha === undefined) mapping.fecha = idx;
            }
            else if (clean.includes('concepto') || clean.includes('descripcion')) {
                if (mapping.concepto === undefined) mapping.concepto = idx;
            }
            else if (clean.includes('detalle')) mapping.detalle = idx;
            else if (clean === 'referencia' || clean === 'ref.' || clean.includes('referencia')) mapping.referencia = idx;
            else if (clean === 'comprobante' || clean.includes('comprobante')) mapping.comprobante = idx;
            else if (clean === 'cod. mov.' || clean.includes('cod. mov') || clean.includes('cod mov') || clean.includes('codigo')) mapping.codMov = idx;
            else if (clean.includes('leyenda')) mapping.codLeyenda = idx;
            else if (clean.includes('suc. origen') || clean.includes('sucursal') || clean.includes('cuenta')) mapping.sucOrigen = idx;
            else if (clean.includes('observaciones') || clean.includes('obs')) mapping.observaciones = idx;
            else if (clean.includes('importe') || clean.includes('monto')) mapping.importe = idx;
            else if (clean.includes('debito') || clean.includes('egreso') || clean.includes('salida')) mapping.debito = idx;
            else if (clean.includes('credito') || clean.includes('ingreso') || clean.includes('entrada')) mapping.credito = idx;
            else if (clean === 'saldo' || clean.includes('saldo')) mapping.saldo = idx;
        });
    } else {
        isHeaderless = true;
        headerRowIdx = -1; // Comienza a procesar desde la primera fila (0)
        // Positional fallback for BBVA raw format: [date, date_val, concept, ref, col4, sucursal/account, col6 (credit), amount, col8, balance]
        mapping = {
            fecha: 0,
            fechaValor: 1,
            concepto: 2,
            referencia: 3,
            sucOrigen: 5,
            credito: 6,
            importe: 7,
            saldo: 9
        };
    }

    const checkStrictNumber = (val) => {
        if (val === null || val === undefined || val === '') return null;
        if (typeof val === 'number') return val;
        let str = String(val).trim();
        // Parse numbers embedded in strings like "Saldo Disponible: -10.860.159,05"
        const matchSaldo = str.match(/(?:[-+]?\d{1,3}(?:\.\d{3})+,\d{2})|(?:[-+]?\d+[\.,]\d+)|(?:[-+]?\d+)/);
        if (matchSaldo) {
            str = matchSaldo[0];
        }
        if (str.includes('.') && str.includes(',')) str = str.replace(/\./g, '').replace(',', '.');
        else if (str.includes(',')) str = str.replace(',', '.');
        const num = parseFloat(str);
        return isNaN(num) ? null : num;
    };

    const normalizeDate = (val) => {
        if (val === null || val === undefined || val === '') return null;
        if (val instanceof Date) {
            if (isNaN(val.getTime())) return null;
            const yyyy = val.getUTCFullYear();
            const mm = String(val.getUTCMonth() + 1).padStart(2, '0');
            const dd = String(val.getUTCDate()).padStart(2, '0');
            return `${yyyy}-${mm}-${dd}`;
        }
        if (typeof val === 'number') {
            if (val > 0 && val < 200000) {
                const utcDays = Math.floor(val - 25569);
                const utcMs = utcDays * 86400 * 1000;
                const dateObj = new Date(utcMs);
                if (!isNaN(dateObj.getTime())) {
                    const yyyy = dateObj.getUTCFullYear();
                    const mm = String(dateObj.getUTCMonth() + 1).padStart(2, '0');
                    const dd = String(dateObj.getUTCDate()).padStart(2, '0');
                    return `${yyyy}-${mm}-${dd}`;
                }
            }
            return String(val);
        }
        const str = String(val).trim();
        return str || null;
    };

    const startIdx = isHeaderless ? 0 : headerRowIdx + 1;

    for (let i = startIdx; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row) || row.length === 0) continue;

        const dateVal = mapping.fecha !== undefined ? normalizeDate(row[mapping.fecha]) : null;
        const fechaValorVal = mapping.fechaValor !== undefined ? normalizeDate(row[mapping.fechaValor]) : null;
        
        let referenciaVal = mapping.referencia !== undefined ? String(row[mapping.referencia] || '').trim() : '';
        if (!referenciaVal) {
            const compVal = mapping.comprobante !== undefined ? String(row[mapping.comprobante] || '').trim() : '';
            const codMovVal = mapping.codMov !== undefined ? String(row[mapping.codMov] || '').trim() : '';
            const codLeyendaVal = mapping.codLeyenda !== undefined ? String(row[mapping.codLeyenda] || '').trim() : '';
            const sucOrigenVal = mapping.sucOrigen !== undefined ? String(row[mapping.sucOrigen] || '').trim() : '';
            referenciaVal = [compVal, codMovVal, codLeyendaVal, sucOrigenVal].filter(Boolean).join(' ').trim();
        }

        let accountIdVal = mapping.sucOrigen !== undefined ? String(row[mapping.sucOrigen] || '').trim() : (context.banco || 'BBVA');
        if (!accountIdVal) accountIdVal = context.banco || 'BBVA';

        let saldoVal = mapping.saldo !== undefined ? checkStrictNumber(row[mapping.saldo]) : null;
        if (saldoVal === null && mapping.observaciones !== undefined) {
            const obsStr = String(row[mapping.observaciones] || '');
            const matchSaldo = obsStr.match(/Saldo\s*(?:Disponible)?:?\s*([-\d.,]+)/i);
            if (matchSaldo) {
                saldoVal = checkStrictNumber(matchSaldo[1]);
            }
        }
        
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
            if (rawAmt !== null) {
                amount = Math.abs(rawAmt);
                if (rawAmt < 0) isDebit = true;
                else if (rawAmt > 0) isCredit = true;
            } else {
                let credValRaw = mapping.credito !== undefined ? checkStrictNumber(row[mapping.credito]) : null;
                if (credValRaw === null && mapping.codMov !== undefined) {
                    let cand = checkStrictNumber(row[mapping.codMov]);
                    if (cand !== null && cand > 0) credValRaw = cand;
                }
                if (credValRaw !== null && credValRaw > 0) {
                    amount = Math.abs(credValRaw);
                    isCredit = true;
                } else {
                    amountErrors.push("Importe vacío o no numérico.");
                }
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
                accountIdentifier: accountIdVal,
                signals
            },
            batchId
        });
    }

    return results;
}
