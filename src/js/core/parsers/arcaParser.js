/**
 * Función pura que parsea una matriz de filas de ARCA (Compras o Ventas)
 * @param {Array<Array<any>>} rows - Filas extraídas de la planilla
 * @param {Object} context - Configuración u opciones (ej. batchId, tipo: 'COMPRAS'|'VENTAS')
 */
export function parseArcaRows(rows, context = {}) {
    const results = [];
    const batchId = context.batchId || null;

    if (!rows || rows.length === 0) return results;

    let headerRowIdx = -1;
    let headers = [];
    let mapping = {};
    let alicuotasMapping = []; // [{ tasa: 21, baseIdx: 15, ivaIdx: 16 }, ...]
    
    // Buscar fila de encabezado
    for (let i = 0; i < Math.min(rows.length, 10); i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row)) continue;
        
        let hasFecha = false;
        let hasPdv = false;
        let hasMonto = false;

        row.forEach(cell => {
            const str = String(cell || '').toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
            if (str === 'fecha') hasFecha = true;
            if (str.includes('punto de venta')) hasPdv = true;
            if (str.includes('imp. total') || str.includes('neto gravado')) hasMonto = true;
        });

        if (hasFecha && hasPdv && hasMonto) {
            headerRowIdx = i;
            headers = row.map(h => String(h || '').trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""));
            break;
        }
    }

    if (headerRowIdx === -1) {
        return [{
            sourceRowNumber: -1,
            rawRow: null,
            errors: ["No se encontró el encabezado estructural de ARCA (Fecha, Punto de Venta, Imp. Total)"],
            warnings: [],
            normalizedData: null,
            batchId
        }];
    }

    // Mapeo dinámico
    headers.forEach((clean, idx) => {
        if (clean === 'fecha') mapping.fecha = idx;
        else if (clean === 'tipo') mapping.tipo = idx;
        else if (clean === 'punto de venta') mapping.pdv = idx;
        else if (clean === 'numero desde') mapping.nroDesde = idx;
        else if (clean === 'numero hasta') mapping.nroHasta = idx;
        else if (clean.includes('emisor') || clean.includes('receptor')) {
            if (clean.includes('tipo')) mapping.tipoDoc = idx;
            const isEmisor = clean.includes('emisor');
            const isReceptor = clean.includes('receptor');
            const target = (context.tipo === 'VENTAS' || context.tipoOperacion === 'VENTA') ? isReceptor : isEmisor;
            if (target || (!context.tipo && !context.tipoOperacion)) {
                if (clean.includes('nro') || clean.includes('cuit')) mapping.cuit = idx;
                if (clean.includes('denominacion') || clean.includes('nombre') || clean.includes('razon social')) mapping.razonSocial = idx;
            }
        }
        else if (clean === 'tipo cambio') mapping.tipoCambio = idx;
        else if (clean === 'moneda') mapping.moneda = idx;
        else if (clean === 'neto no gravado') mapping.noGravado = idx;
        else if (clean === 'op. exentas') mapping.exento = idx;
        else if (clean === 'otros tributos') mapping.otrosTributos = idx;
        else if (clean === 'total iva') mapping.totalIva = idx;
        else if (clean === 'imp. total') mapping.total = idx;
        
        // Detección de alícuotas: "iva 21%" o "neto grav. iva 21%"
        const isIva = clean.match(/^iva\s*(\d+(?:,\d+)?)\s*%/);
        const isBase = clean.match(/^neto grav\.?\s*iva\s*(\d+(?:,\d+)?)\s*%/);
        
        if (isIva || isBase) {
            const matchStr = (isIva || isBase)[1];
            const tasa = parseFloat(matchStr.replace(',', '.'));
            let al = alicuotasMapping.find(a => a.tasa === tasa);
            if (!al) {
                al = { tasa };
                alicuotasMapping.push(al);
            }
            if (isIva) al.ivaIdx = idx;
            if (isBase) al.baseIdx = idx;
        }
    });

    const parseNumberStrict = (val, fieldName, errors) => {
        if (val === null || val === undefined || val === '') {
            errors.push(`El campo obligatorio ${fieldName} está vacío o es nulo.`);
            return null;
        }
        if (typeof val === 'number') return val;
        let str = String(val).replace(/\./g, '').replace(',', '.');
        const num = parseFloat(str);
        if (isNaN(num)) {
            errors.push(`El campo ${fieldName} contiene un valor no numérico inválido: ${val}`);
            return null;
        }
        return num;
    };

    const parseNumberLenient = (val) => {
        if (val === null || val === undefined || val === '') return 0; // Opcional -> 0
        if (typeof val === 'number') return val;
        let str = String(val).replace(/\./g, '').replace(',', '.');
        const num = parseFloat(str);
        return isNaN(num) ? 0 : num;
    };

    for (let i = headerRowIdx + 1; i < rows.length; i++) {
        const row = rows[i];
        if (!row || !Array.isArray(row) || row.length === 0) continue;

        const dateVal = mapping.fecha !== undefined ? row[mapping.fecha] : null;
        if (!dateVal) continue;

        let errors = [];
        let warnings = [];

        const cuitVal = mapping.cuit !== undefined ? String(row[mapping.cuit] || '').replace(/\D/g, '') : '';
        const pdvVal = mapping.pdv !== undefined ? parseInt(row[mapping.pdv], 10) : 0;
        const nroDesdeVal = mapping.nroDesde !== undefined ? parseInt(row[mapping.nroDesde], 10) : 0;
        const nroHastaVal = mapping.nroHasta !== undefined ? parseInt(row[mapping.nroHasta], 10) : 0;
        
        if (!cuitVal) errors.push("CUIT faltante o inválido");
        if (!pdvVal) errors.push("Punto de Venta inválido");
        if (!nroDesdeVal) errors.push("Número Comprobante inválido");

        let total = 0;
        if (mapping.total !== undefined) {
            total = parseNumberStrict(row[mapping.total], "Imp. Total", errors);
        } else {
            errors.push("Columna Imp. Total ausente.");
        }

        let moneda = mapping.moneda !== undefined ? String(row[mapping.moneda] || '').trim() : '';
        let tipoCambio = mapping.tipoCambio !== undefined ? row[mapping.tipoCambio] : null;

        if (!moneda) {
            warnings.push("Moneda vacía. Se asume PES.");
            moneda = 'PES';
        }
        if (moneda === 'PES' && (tipoCambio === null || tipoCambio === undefined || tipoCambio === '')) {
            warnings.push("Tipo de cambio vacío para PES. Se asume 1.");
            tipoCambio = 1;
        } else if (moneda !== 'PES' && (tipoCambio === null || tipoCambio === undefined || tipoCambio === '')) {
            errors.push("Tipo de cambio es obligatorio para moneda extranjera.");
            tipoCambio = 1;
        } else {
            tipoCambio = parseNumberLenient(tipoCambio);
            if (tipoCambio === 0) tipoCambio = 1; 
        }

        // Extracción de alícuotas
        const alicuotas = [];
        alicuotasMapping.forEach(alMap => {
            const baseImp = alMap.baseIdx !== undefined ? parseNumberLenient(row[alMap.baseIdx]) : 0;
            const impIva = alMap.ivaIdx !== undefined ? parseNumberLenient(row[alMap.ivaIdx]) : 0;
            if (baseImp !== 0 || impIva !== 0) {
                alicuotas.push({
                    tasa: alMap.tasa,
                    baseImponible: baseImp,
                    importeIva: impIva
                });
            }
        });

        results.push({
            sourceRowNumber: i + 1,
            rawRow: row,
            errors,
            warnings,
            normalizedData: {
                fecha: dateVal,
                tipo_cbte: mapping.tipo !== undefined ? parseInt(row[mapping.tipo], 10) || 0 : 0,
                pdv: pdvVal,
                nroDesde: nroDesdeVal,
                nroHasta: nroHastaVal,
                cuit: cuitVal,
                razonSocial: mapping.razonSocial !== undefined ? String(row[mapping.razonSocial] || '').trim() : '',
                moneda: moneda,
                tipoCambio: tipoCambio,
                netoNoGravado: mapping.noGravado !== undefined ? parseNumberLenient(row[mapping.noGravado]) : 0,
                exento: mapping.exento !== undefined ? parseNumberLenient(row[mapping.exento]) : 0,
                otrosTributos: mapping.otrosTributos !== undefined ? parseNumberLenient(row[mapping.otrosTributos]) : 0,
                totalIva: mapping.totalIva !== undefined ? parseNumberLenient(row[mapping.totalIva]) : 0,
                total: total || 0,
                alicuotas
            },
            batchId
        });
    }

    return results;
}
