/**
 * Parsea el texto del archivo ARBA (ancho fijo).
 *
 * @param {string} text - Contenido del archivo de texto.
 * @param {Object} context - Contexto con configuraciones o lote.
 * @returns {Array} Array de filas parseadas.
 */
export function parseArbaText(text, context = {}) {
    const lines = text.split(/\r?\n/);
    const results = [];
    
    lines.forEach((line, index) => {
        if (!line || line.trim() === '') return;
        
        const sourceRowNumber = index + 1;
        const result = {
            sourceRowNumber,
            rawRow: line,
            errors: [],
            warnings: [],
            normalizedData: null,
            batchId: context.batchId || null
        };
        
        if (line.length !== 70) {
            result.errors.push(`Longitud de línea inválida: esperada 70, encontrada ${line.length}`);
            results.push(result);
            return;
        }

        try {
            let cleanCuit = '';
            let fechaStr = '';
            let sucursal = '';
            let comprobante = '';
            let montoStr = '';
            let codigoInicial = '';

            const isRealArbaFormat = line.substring(4, 18).includes('-');

            if (isRealArbaFormat) {
                codigoInicial = line.substring(0, 4);
                const cuitRaw = line.substring(4, 18);
                cleanCuit = cuitRaw.replace(/\D/g, '').replace(/^2(?=30|33|34|20|27)/, '');
                fechaStr = line.substring(18, 28);
                sucursal = line.substring(28, 32);
                comprobante = line.substring(32, 56);
                montoStr = line.substring(56, 70);
            } else {
                codigoInicial = line.substring(0, 8);
                cleanCuit = line.substring(8, 19);
                fechaStr = line.substring(19, 29);
                sucursal = line.substring(29, 41);
                comprobante = line.substring(42, 56);
                montoStr = line.substring(56, 70);
            }

            // Validación de CUIT (11 dígitos)
            if (!/^\d{11}$/.test(cleanCuit)) {
                result.errors.push("Formato de CUIT inválido");
            }
            
            // Validación de fecha (DD/MM/YYYY)
            if (!/^\d{2}\/\d{2}\/\d{4}$/.test(fechaStr)) {
                result.errors.push("Formato de Fecha inválido");
            }

            const parsedAmount = parseArbaAmount(montoStr);
            if (parsedAmount === null) {
                result.errors.push("Monto inválido");
            }

            if (result.errors.length === 0) {
                const parts = fechaStr.split('/');
                const period = parts.length === 3 ? `${parts[2]}-${parts[1]}` : '';

                result.normalizedData = {
                    cuit: cleanCuit,
                    fecha: fechaStr,
                    period: period,
                    regimen: codigoInicial.trim(),
                    sucursal: sucursal.trim(),
                    comprobante: comprobante.trim(),
                    monto: parsedAmount,
                    amount: parsedAmount,
                    importe: parsedAmount,
                    jurisdiction: (context.jurisdiccion || 'ARBA').toUpperCase(),
                    fuente: 'ARBA',
                    tipo: 'percepcion',
                    audit: {
                        codigoInicial
                    }
                };
            }
        } catch (e) {
            result.errors.push("Error inesperado al parsear línea: " + e.message);
        }
        
        results.push(result);
    });

    return results;
}

/**
 * Valida y parsea el importe del archivo ARBA.
 * @param {string} rawAmount - String original (e.g. "000000028382,92")
 * @returns {number|null} El número flotante o null si es inválido.
 */
export function parseArbaAmount(rawAmount) {
    if (typeof rawAmount !== 'string') {
        return null;
    }
    const trimmed = rawAmount.trim();
    if (trimmed.length !== 14) {
        return null;
    }
    
    if (!/^[0-9]+\,?[0-9]*$/.test(trimmed)) {
        return null;
    }
    
    const normalized = trimmed.replace(',', '.');
    const floatVal = parseFloat(normalized);
    
    if (isNaN(floatVal)) return null;
    return floatVal;
}
