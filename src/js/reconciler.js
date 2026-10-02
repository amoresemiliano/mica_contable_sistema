import { appStore } from './store.js';

// 6. MOTOR DE CONCILIACIÓN DE "OTROS TRIBUTOS" Y PERCEPCIONES PROVINCIALES (SOLID: Single Responsibility)
export class Reconciler {
    // Parsea percepciones provinciales desde CSV/TXT/Excel
    static parsePerceptions(content, jurisdiction) {
        const lines = content.split(/\r?\n/);
        if (lines.length < 2) return [];

        // Detecta delimitadores comunes
        const firstLine = lines[0];
        let delimiter = ';';
        if (firstLine.includes(',')) delimiter = ',';
        else if (firstLine.includes('\t')) delimiter = '\t';

        const headers = firstLine.split(delimiter).map(h => h.replace(/"/g, '').trim().toLowerCase());
        const list = [];

        // Busca índices de columnas por aproximación de nombres
        const cuitIdx = headers.findIndex(h => h.includes('cuit') || h.includes('código') || h.includes('cód.') || h.includes('cuit_agente') || h.includes('cuit agente') || h.includes('doc'));
        const amountIdx = headers.findIndex(h => h.includes('monto') || h.includes('importe') || h.includes('percepción') || h.includes('percepcion') || h.includes('alicuota') || h.includes('perc.'));
        const dateIdx = headers.findIndex(h => h.includes('fecha') || h.includes('periodo') || h.includes('período') || h.includes('emisión') || h.includes('fec.'));

        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            const values = line.split(delimiter).map(v => v.replace(/"/g, '').trim());
            if (values.length < 2) continue;

            let cuit = cuitIdx !== -1 ? values[cuitIdx] : values[0];
            let rawAmount = amountIdx !== -1 ? values[amountIdx] : values[1];
            let rawDate = dateIdx !== -1 ? values[dateIdx] : (values[2] || '');

            if (!cuit || !rawAmount) continue;

            cuit = cuit.replace(/\D/g, ''); // CUIT limpio sin guiones
            rawAmount = rawAmount.replace(/\./g, '').replace(',', '.');
            const amount = parseFloat(rawAmount) || 0;

            // Extraer período en formato YYYY-MM
            let period = "";
            if (rawDate) {
                // Formato DD/MM/YYYY o YYYY-MM-DD
                const match = rawDate.match(/(\d{4})[-/](\d{2})/); // YYYY-MM
                const matchRev = rawDate.match(/(\d{2})[-/](\d{4})/); // MM-YYYY or DD/MM/YYYY
                const matchShort = rawDate.match(/^(\d{6})$/); // YYYYMM

                if (match) {
                    period = `${match[1]}-${match[2]}`;
                } else if (matchRev) {
                    period = `${matchRev[2]}-${matchRev[1]}`;
                } else if (matchShort) {
                    period = `${matchShort[1].substring(0, 4)}-${matchShort[1].substring(4, 6)}`;
                } else {
                    period = rawDate.substring(0, 7); // Fallback
                }
            }

            list.push({
                cuit,
                period,
                amount,
                jurisdiction: jurisdiction.toUpperCase()
            });
        }
        return list;
    }

    // Ejecuta el cruce automático (Matching) entre ARCA Compras y Tabla_Percepciones_Provinciales
    static runCrossMatching() {
        const items = appStore.items.filter(i => i.tipo === 'recibido' && i.otrosTributos > 0);
        const perceptions = appStore.perceptions;

        if (items.length === 0 || perceptions.length === 0) return;

        items.forEach(item => {
            // Extraer mes/año del comprobante (Fecha de Emisión es DD/MM/YYYY o YYYY-MM-DD)
            const dateParts = item.fecha.split('/');
            let itemPeriod = "";
            if (dateParts.length === 3) {
                itemPeriod = `${dateParts[2]}-${dateParts[1]}`; // YYYY-MM
            } else {
                const datePartsDash = item.fecha.split('-');
                if (datePartsDash.length === 3) {
                    itemPeriod = `${datePartsDash[0]}-${datePartsDash[1]}`; // YYYY-MM
                }
            }

            // Filtrar percepciones del mismo proveedor en el mismo período
            const matches = perceptions.filter(p => p.cuit === item.cuit && p.period === itemPeriod);

            let saldoAExplicar = item.otrosTributos;
            const mapped = [];

            matches.forEach(percep => {
                if (saldoAExplicar > 0) {
                    const matchedAmount = Math.min(saldoAExplicar, percep.amount);
                    saldoAExplicar -= matchedAmount;
                    mapped.push({
                        jurisdiction: percep.jurisdiction,
                        amount: matchedAmount
                    });
                }
            });

            // Margen de tolerancia: +- $5 se asigna automáticamente a EXENTO
            if (saldoAExplicar > 0 && saldoAExplicar <= 5) {
                mapped.push({
                    jurisdiction: 'EXENTO',
                    amount: saldoAExplicar
                });
                saldoAExplicar = 0;
            } else if (saldoAExplicar < 0 && saldoAExplicar >= -5) {
                // Si la percepción es un poco mayor, toleramos y ajustamos el saldo a cero
                saldoAExplicar = 0;
            }

            item.percepcionesMapeadas = mapped;
            item.saldoAExplicar = saldoAExplicar;
        });

        appStore.notify();
    }

    // Resolución manual de diferencias por el contador
    static manualResolve(itemId, allocationType, customAccount) {
        const item = appStore.items.find(i => i.id === itemId);
        if (item && item.saldoAExplicar > 0) {
            if (allocationType === 'exento') {
                item.percepcionesMapeadas.push({
                    jurisdiction: 'EXENTO',
                    amount: item.saldoAExplicar
                });
            } else {
                item.percepcionesMapeadas.push({
                    jurisdiction: customAccount || 'OTRO TRIBUTO MANUAL',
                    amount: item.saldoAExplicar
                });
            }
            item.saldoAExplicar = 0;
            appStore.notify();
        }
    }
}
