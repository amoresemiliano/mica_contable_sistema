import { appStore } from './store.js';

// 4. PARSER Y MOTOR DE CLASIFICACIÓN DE EXTRACTOS BANCARIOS (SOLID: Single Responsibility / Open-Closed)
export class BankParser {
    // Convierte el archivo leído a formato JSON plano
    static parseExcel(arrayBuffer, bankName) {
        // Leemos con XLSX (SheetJS cargado vía CDN)
        const data = new Uint8Array(arrayBuffer);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const firstSheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[firstSheetName];
        
        // Convertimos a matriz de filas (filas[fila][columna])
        const rawRows = window.XLSX.utils.sheet_to_json(worksheet, { header: 1 });
        if (rawRows.length === 0) return { headers: [], transactions: [] };

        // 1. Identificar fila de cabeceras y mapear columnas
        let headerRowIdx = -1;
        for (let i = 0; i < Math.min(rawRows.length, 10); i++) {
            const row = rawRows[i];
            if (row.some(cell => {
                const str = String(cell).toLowerCase();
                return str.includes('fecha') || str.includes('concepto') || str.includes('descripcion') || str.includes('descripción') || str.includes('importe') || str.includes('monto');
            })) {
                headerRowIdx = i;
                break;
            }
        }

        // Si no encontramos cabecera, asumimos la primera fila con datos
        if (headerRowIdx === -1) headerRowIdx = 0;
        const rawHeaders = rawRows[headerRowIdx].map(h => String(h || '').trim());

        // Intentamos obtener mapeo guardado o creamos uno heurístico
        const mapping = appStore.bankTemplates[bankName] || this.detectColumns(rawHeaders);

        // Si falta mapeo de columnas críticas, devolvemos las cabeceras para que la UI le permita mapear
        if (!mapping.fecha || !mapping.descripcion || (!mapping.importe && (!mapping.debito || !mapping.credito))) {
            return { headers: rawHeaders, mappingRequired: true, rawRows: rawRows.slice(headerRowIdx + 1) };
        }

        // Guardamos la plantilla aprobada en el store
        appStore.saveBankTemplate(bankName, mapping);

        const transactions = [];
        // Recorrer filas de transacciones
        for (let i = headerRowIdx + 1; i < rawRows.length; i++) {
            const row = rawRows[i];
            if (!row || row.length === 0) continue;

            const dateVal = row[mapping.fecha];
            const descVal = row[mapping.descripcion];
            
            if (!dateVal || !descVal) continue;

            // Formatear Fecha
            let fechaStr = String(dateVal);
            if (typeof dateVal === 'number') {
                // Formato numérico de Excel
                const dateObj = window.XLSX.utils.sheet_to_date(worksheet);
                const jsDate = new Date((dateVal - 25569) * 86400 * 1000);
                fechaStr = jsDate.toLocaleDateString('es-AR');
            }

            // Calcular importe
            let amount = 0;
            let type = 'debit'; // 'debit' (egreso) o 'credit' (ingreso)

            if (mapping.importe !== undefined) {
                let rawAmt = String(row[mapping.importe] || '0').replace(/\./g, '').replace(',', '.');
                amount = parseFloat(rawAmt) || 0;
                type = amount < 0 ? 'debit' : 'credit';
                amount = Math.abs(amount);
            } else {
                let debVal = parseFloat(String(row[mapping.debito] || '0').replace(/\./g, '').replace(',', '.')) || 0;
                let credVal = parseFloat(String(row[mapping.credito] || '0').replace(/\./g, '').replace(',', '.')) || 0;

                if (debVal > 0) {
                    amount = debVal;
                    type = 'debit';
                } else if (credVal > 0) {
                    amount = credVal;
                    type = 'credit';
                } else {
                    continue; // Renglón vacío
                }
            }

            let referenciaStr = mapping.referencia !== undefined ? String(row[mapping.referencia] || '').trim() : '';
            let saldoVal = null;
            if (mapping.saldo !== undefined && row[mapping.saldo] !== undefined) {
                const str = String(row[mapping.saldo] || '').trim();
                const matchSaldo = str.match(/(?:[-+]?\d{1,3}(?:\.\d{3})+,\d{2})|(?:[-+]?\d+[\.,]\d+)|(?:[-+]?\d+)/);
                if (matchSaldo) {
                    const cleanStr = matchSaldo[0].replace(/\./g, '').replace(',', '.');
                    const num = parseFloat(cleanStr);
                    if (!isNaN(num)) saldoVal = num;
                }
            }

            let accountIdStr = mapping.cuenta !== undefined ? String(row[mapping.cuenta] || '').trim() : (bankName || 'BBVA');
            if (!accountIdStr) accountIdStr = bankName || 'BBVA';

            // Clasificación automática basada en reglas de texto
            const cleanDesc = String(descVal).toUpperCase();
            const rules = appStore.bankRules[type] || [];
            let matchedRule = rules.find(rule => cleanDesc.includes(rule.pattern));

            const suggestion = matchedRule ? matchedRule.category : (type === 'debit' ? 'Pago Proveedor' : 'Ingreso por Ventas');

            transactions.push({
                id: `bank-${Date.now()}-${i}-${amount}`,
                fecha: fechaStr,
                fechaValor: mapping.fechaValor !== undefined ? String(row[mapping.fechaValor] || '').trim() : fechaStr,
                descripcion: String(descVal).trim(),
                referencia: referenciaStr,
                saldo: saldoVal,
                accountIdentifier: accountIdStr,
                monto: amount,
                tipo: type,
                cuentaSugerida: suggestion,
                confirmada: false
            });
        }

        return { headers: rawHeaders, transactions, mappingRequired: false };
    }

    // Heurística de detección automática de columnas
    static detectColumns(headers) {
        const mapping = {};
        headers.forEach((h, idx) => {
            const clean = h.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
            if (clean === 'fec. valor' || clean === 'fecha valor' || clean === 'f.valor') mapping.fechaValor = idx;
            else if (clean.includes('fecha') || clean.includes('fec.')) {
                if (mapping.fecha === undefined) mapping.fecha = idx;
            }
            else if (clean.includes('concepto') || clean.includes('descripcion') || clean.includes('detalle')) {
                if (mapping.descripcion === undefined) mapping.descripcion = idx;
            }
            else if (clean.includes('referencia') || clean.includes('ref.') || clean.includes('comprobante') || clean.includes('cod')) mapping.referencia = idx;
            else if (clean.includes('sucursal') || clean.includes('cuenta') || clean.includes('suc.')) mapping.cuenta = idx;
            else if (clean.includes('importe') || clean.includes('monto') || clean.includes('saldo_movimiento') || (clean.includes('total') && !clean.includes('sub'))) mapping.importe = idx;
            else if (clean.includes('debito') || clean.includes('egreso') || clean.includes('salida')) mapping.debito = idx;
            else if (clean.includes('credito') || clean.includes('ingreso') || clean.includes('entrada')) mapping.credito = idx;
            else if (clean === 'saldo' || clean.includes('saldo')) mapping.saldo = idx;
        });
        return mapping;
    }

    // Aplica las reglas del motor a una descripción manual
    static classifyTransaction(type, description) {
        const cleanDesc = description.toUpperCase();
        const rules = appStore.bankRules[type] || [];
        const matchedRule = rules.find(rule => cleanDesc.includes(rule.pattern));
        return matchedRule ? matchedRule.category : (type === 'debit' ? 'Pago Proveedor' : 'Ingreso por Ventas');
    }
}
