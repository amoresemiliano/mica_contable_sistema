/**
 * Adaptador de Texto
 * Procesa archivos de texto plano o CSV en matrices de filas (Array<Array<unknown>>)
 */

export function parseDelimitedText(text, options = {}) {
    if (typeof text !== 'string') {
        throw new Error("El contenido proporcionado no es un texto válido.");
    }
    
    if (text.trim().length === 0) {
        throw new Error("El archivo de texto está vacío.");
    }
    
    let delimiter = options.delimiter;

    // Si no se especifica delimitador o es 'AUTO', autodetectar por primera línea útil
    if (!delimiter || delimiter === 'AUTO') {
        const rawLines = text.split(/\r?\n/);
        const firstLine = rawLines.find(l => l.trim().length > 0) || '';
        
        const countSemicolons = (firstLine.match(/;/g) || []).length;
        const countCommas = (firstLine.match(/,/g) || []).length;
        const countTabs = (firstLine.match(/\t/g) || []).length;

        if (countSemicolons >= countCommas && countSemicolons >= countTabs && countSemicolons > 0) {
            delimiter = ';';
        } else if (countTabs > countCommas && countTabs > 0) {
            delimiter = '\t';
        } else {
            delimiter = ',';
        }
    }
    
    // Separar por saltos de línea manejando CRLF y LF
    const rawLines = text.split(/\r?\n/);
    
    const rows = [];
    for (let line of rawLines) {
        // Ignorar líneas vacías si está configurado
        if (options.ignoreEmptyLines && line.trim() === '') {
            continue;
        }
        
        if (delimiter === 'NONE') {
            rows.push([line]); // Fixed width
        } else {
            rows.push(line.split(delimiter));
        }
    }
    
    return rows;
}
