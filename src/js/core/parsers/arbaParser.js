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
            const codigoInicial = line.substring(0, 8); // 0-8
            const cuitStr = line.substring(8, 19);      // 8-19
            const fechaStr = line.substring(19, 29);    // 19-29
            const sucursal = line.substring(29, 41);    // 29-41
            const padding = line.substring(41, 42);     // 41-42
            const comprobante = line.substring(42, 56); // 42-56
            const montoStr = line.substring(56, 70);    // 56-70

            // Validación de CUIT (11 dígitos)
            if (!/^\d{11}$/.test(cuitStr)) {
                result.errors.push("Formato de CUIT inválido");
            }
            
            // Validación de fecha (básica)
            if (!/^\d{2}\/\d{2}\/\d{4}$/.test(fechaStr)) {
                result.errors.push("Formato de Fecha inválido");
            }

            const parsedAmount = parseArbaAmount(montoStr);
            if (parsedAmount === null) {
                result.errors.push("Monto inválido");
            }

            if (result.errors.length === 0) {
                result.normalizedData = {
                    cuit: cuitStr,
                    fecha: fechaStr,
                    sucursal: sucursal.trim(),
                    comprobante: comprobante.trim(),
                    monto: parsedAmount,
                    // Campos de auditoría conservados
                    audit: {
                        codigoInicial,
                        padding
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
 * @param {string} rawAmount - String original (e.g. "0000000000150,")
 * @returns {number|null} El número flotante o null si es inválido.
 */
export function parseArbaAmount(rawAmount) {
    if (typeof rawAmount !== 'string' || rawAmount.length !== 14) {
        return null;
    }
    
    // ARBA montos suelen ser paddeados con 0 a la izquierda y usar coma decimal.
    // Ejemplo: 0000000000150, => 150.00
    // Opcional: Puede venir con decimales: "0000000000150,5"
    if (!/^[0-9]+\,?[0-9]*$/.test(rawAmount)) {
        return null; // Caracteres inválidos
    }
    
    // Normalizar a formato numérico (punto)
    const normalized = rawAmount.replace(',', '.');
    const floatVal = parseFloat(normalized);
    
    if (isNaN(floatVal)) return null;
    return floatVal;
}
