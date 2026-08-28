/**
 * Adaptador de SheetJS. Envuelve la librería XLSX proporcionada por inyección.
 * Aisla la dependencia de window.XLSX y maneja errores estructurales de hojas de cálculo.
 */

export function createSheetJsAdapter(xlsxLibrary) {
    if (!xlsxLibrary) {
        throw new Error("La librería SheetJS (XLSX) es obligatoria.");
    }

    return {
        /**
         * Lee un ArrayBuffer y retorna una matriz bidimensional (Array<Array<unknown>>)
         * @param {ArrayBuffer} arrayBuffer El buffer del archivo
         * @param {Object} options Opciones (sheetName, etc)
         * @returns {Array<Array<unknown>>} Matriz de filas
         */
        workbookToRows(arrayBuffer, options = {}) {
            if (!arrayBuffer) throw new Error("ArrayBuffer obligatorio");

            let workbook;
            try {
                // SheetJS read options
                workbook = xlsxLibrary.read(arrayBuffer, { type: 'array', cellFormula: false, cellHTML: false });

                // Verificar si SheetJS parseó silenciosamente texto no-Excel como CSV 1x1
                if (workbook && workbook.SheetNames && workbook.SheetNames.length === 1) {
                    const firstSheet = workbook.Sheets[workbook.SheetNames[0]];
                    if (firstSheet && firstSheet['!ref'] === 'A1' && typeof firstSheet['A1']?.v === 'string') {
                        const val = firstSheet['A1'].v.trim();
                        if (val.length > 0 && !val.includes(',') && !val.includes(';') && !val.includes('\t') && !val.includes('\n')) {
                            throw new Error("No se encontraron tablas estructuradas válidas");
                        }
                    }
                }
            } catch (error) {
                throw new Error("El archivo está corrupto o no es un formato de hoja de cálculo válido: " + error.message);
            }

            if (!workbook || !workbook.SheetNames || workbook.SheetNames.length === 0) {
                throw new Error("El archivo no contiene hojas.");
            }

            let sheetName = options.sheetName;

            // Si no se especifica hoja, pero hay más de una, es ambiguo.
            if (!sheetName) {
                if (workbook.SheetNames.length > 1) {
                    throw new Error("El archivo contiene múltiples hojas y no se especificó cuál leer. Hojas disponibles: " + workbook.SheetNames.join(', '));
                }
                sheetName = workbook.SheetNames[0];
            } else if (!workbook.SheetNames.includes(sheetName)) {
                throw new Error(`La hoja "${sheetName}" no existe en el archivo.`);
            }

            const sheet = workbook.Sheets[sheetName];
            if (!sheet || Object.keys(sheet).length === 0) {
                throw new Error(`La hoja "${sheetName}" está vacía.`);
            }

            // Convertir a Array de Arrays
            const rows = xlsxLibrary.utils.sheet_to_json(sheet, {
                header: 1, // Retorna array de arrays, no asume fila de encabezado
                defval: null,
                blankrows: false
            });

            if (rows.length === 0) {
                throw new Error(`La hoja "${sheetName}" no contiene datos.`);
            }

            return rows;
        }
    };
}
