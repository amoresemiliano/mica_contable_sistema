import { categorizer } from './categorizer.js';

// 2. PARSER Y NORMALIZADOR DE CSV (SOLID: Single Responsibility)
export class CSVParser {
    static parse(content, type) {
        const lines = content.split(/\r?\n/);
        if (lines.length < 2) return [];

        // Detectamos los encabezados de la primera línea limpiando comillas
        const headers = lines[0].split(';').map(h => h.replace(/"/g, '').trim());
        const list = [];

        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            // Parseo básico compatible con separadores punto y coma
            const values = line.split(';').map(v => v.replace(/"/g, '').trim());
            if (values.length < headers.length) continue;

            const rawData = {};
            headers.forEach((header, idx) => {
                rawData[header] = values[idx];
            });

            list.push(this.normalize(rawData, type));
        }
        return list;
    }

    // Convierte las diferencias entre Emitidos y Recibidos en un único objeto homogéneo
    static normalize(raw, type) {
        let name = "S/D";
        let cuit = "S/D";
        let date = raw['Fecha de Emisión'] || 'S/D';
        let docType = raw['Tipo de Comprobante'] || 'S/D';

        if (type === 'recibido') {
            name = raw['Denominación Emisor'] || 'Consumidor Final';
            cuit = raw['Nro. Doc. Emisor'] || 'S/D';
        } else {
            name = raw['Denominación Receptor'] || 'Consumidor Final';
            cuit = raw['Nro. Doc. Receptor'] || 'S/D';
        }

        // Limpiar y parsear el Importe Total
        let rawTotal = raw['Imp. Total'] || '0';
        rawTotal = rawTotal.replace(/\./g, '').replace(',', '.');
        const parsedTotal = parseFloat(rawTotal) || 0;

        // Limpiar y parsear Otros Tributos para compras (Recibidos)
        let parsedOtros = 0;
        if (type === 'recibido') {
            let rawOtros = raw['Imp. de Otros Tributos'] || '0';
            rawOtros = rawOtros.replace(/\./g, '').replace(',', '.');
            parsedOtros = parseFloat(rawOtros) || 0;
        }

        // Buscamos si el sistema ya "aprendió" la categoría para este CUIT
        const suggestion = categorizer.getSuggestion(cuit);

        return {
            id: `${type}-${cuit}-${date}-${parsedTotal}`,
            tipo: type, // 'recibido' o 'emitido'
            fecha: date,
            comprobante: docType,
            cuit: cuit.replace(/\D/g, ''), // CUIT limpio sin guiones
            razonSocial: name,
            total: parsedTotal,
            otrosTributos: parsedOtros,
            saldoAExplicar: parsedOtros, // Saldo inicial a explicar
            percepcionesMapeadas: [], // Detalle de percepciones { jurisdiccion, monto }
            categoria: suggestion.category,
            sugerida: suggestion.exists,
            confirmada: false,
            // Campos de ventas
            netoGravado: parseFloat((raw['Imp. Neto Gravado'] || '0').replace(/\./g, '').replace(',', '.')) || 0,
            noGravado: parseFloat((raw['Imp. Neto No Gravado'] || '0').replace(/\./g, '').replace(',', '.')) || 0,
            exento: parseFloat((raw['Imp. Op. Exentas'] || '0').replace(/\./g, '').replace(',', '.')) || 0,
            iva: parseFloat((raw['Imp. Liquidado'] || '0').replace(/\./g, '').replace(',', '.')) || 0,
            actividad: "" // Asignación de actividad posterior
        };
    }
}
