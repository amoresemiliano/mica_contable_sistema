/**
 * Parser para archivos de Catálogo de Actividades Económicas ARCA (F883)
 * Estructura: COD_ACTIVIDAD_F883;DESC_ACTIVIDAD_F883;DESCL_ACTIVIDA_F883;
 */
export function parseF883ActivitiesTxt(rawText) {
    if (typeof rawText !== 'string') {
        throw new Error('El contenido a parsear debe ser un string.');
    }

    const lines = rawText.split(/\r?\n/);
    const validActivities = [];
    const malformedLines = [];
    const seenCodes = new Set();
    let duplicateCount = 0;

    let isHeaderSkipped = false;

    lines.forEach((line, index) => {
        const trimmedLine = line.trim();
        if (!trimmedLine) return; // Ignorar líneas vacías

        // Separar por punto y coma (;)
        const parts = trimmedLine.split(';').map(p => p.trim());

        // Si la última parte está vacía (por el ; final de cada fila en F883), eliminarla
        if (parts.length > 0 && parts[parts.length - 1] === '') {
            parts.pop();
        }

        // Ignorar encabezado si existe
        if (!isHeaderSkipped && parts.length >= 2 && parts[0].toUpperCase().startsWith('COD_ACTIVIDAD')) {
            isHeaderSkipped = true;
            return;
        }

        if (parts.length < 2) {
            malformedLines.push({ lineNumber: index + 1, content: line, reason: 'Campos insuficientes (se requiere código y nombre)' });
            return;
        }

        // Preservar exacto el código como texto (con ceros a la izquierda, ej: "011111", "000007")
        const arcaCode = parts[0];
        const name = parts[1];
        const description = parts[2] || parts[1]; // Si no hay DESCL, usar DESC

        if (!arcaCode || !name) {
            malformedLines.push({ lineNumber: index + 1, content: line, reason: 'Código ARCA o Nombre vacío' });
            return;
        }

        if (seenCodes.has(arcaCode)) {
            duplicateCount++;
            // En caso de duplicado en el mismo archivo, actualizamos o conservamos la versión más reciente
            const existingIdx = validActivities.findIndex(a => a.arca_code === arcaCode);
            if (existingIdx !== -1) {
                validActivities[existingIdx] = {
                    arca_code: arcaCode,
                    name: name,
                    description: description,
                    is_active: true
                };
            }
        } else {
            seenCodes.add(arcaCode);
            validActivities.push({
                arca_code: arcaCode,
                name: name,
                description: description,
                is_active: true
            });
        }
    });

    return {
        totalRows: lines.filter(l => l.trim().length > 0).length - (isHeaderSkipped ? 1 : 0),
        validRows: validActivities.length,
        invalidRows: malformedLines.length,
        duplicateCodes: duplicateCount,
        validActivities,
        malformedLines,
        previewRows: validActivities.slice(0, 10)
    };
}
