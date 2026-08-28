/**
 * Adaptador de lectura de archivos. Aisla el API de FileReader del resto del sistema.
 */

export async function readFileAsArrayBuffer(file, options = {}) {
    return new Promise((resolve, reject) => {
        if (!file) return reject(new Error("Archivo no proporcionado"));
        if (options.maxSize && file.size > options.maxSize) {
            return reject(new Error(`El archivo excede el tamaño máximo permitido de ${options.maxSize} bytes`));
        }

        const reader = new FileReader();

        if (options.signal) {
            options.signal.addEventListener('abort', () => {
                reader.abort();
                reject(new Error("Lectura cancelada"));
            });
        }

        reader.onload = (e) => resolve(e.target.result);
        reader.onerror = () => reject(new Error("Error al leer el archivo (ArrayBuffer)"));
        reader.readAsArrayBuffer(file);
    });
}

export async function readFileAsText(file, options = {}) {
    return new Promise((resolve, reject) => {
        if (!file) return reject(new Error("Archivo no proporcionado"));
        if (options.maxSize && file.size > options.maxSize) {
            return reject(new Error(`El archivo excede el tamaño máximo permitido de ${options.maxSize} bytes`));
        }

        const reader = new FileReader();

        if (options.signal) {
            options.signal.addEventListener('abort', () => {
                reader.abort();
                reject(new Error("Lectura cancelada"));
            });
        }

        reader.onload = (e) => resolve(e.target.result);
        reader.onerror = () => reject(new Error("Error al leer el archivo (Text)"));
        reader.readAsText(file, options.encoding || 'UTF-8');
    });
}

/**
 * Detecta el formato del archivo utilizando la extensión, mimeType y la firma binaria (magic bytes).
 */
export function detectFileFormat({ arrayBuffer, text, fileName, mimeType }) {
    if (!fileName) throw new Error("fileName es obligatorio para detectar formato");

    const ext = fileName.split('.').pop().toLowerCase();

    // Check Magic Bytes si se proporcionó un arrayBuffer
    let signatureFormat = null;
    if (arrayBuffer && arrayBuffer.byteLength >= 8) {
        const view = new Uint8Array(arrayBuffer);
        const hexSignature = Array.from(view.slice(0, 8)).map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();

        if (hexSignature.startsWith('D0CF11E0A1B11AE1')) {
            signatureFormat = 'OLE2_BIFF'; // XLS (Excel 97-2003)
        } else if (hexSignature.startsWith('504B0304')) {
            signatureFormat = 'OOXML_XLSX'; // ZIP / XLSX
        }
    }

    // Inferencia por extensión si no hay firma o no se proveyó buffer
    let extensionFormat = 'UNKNOWN';
    if (ext === 'xlsx') extensionFormat = 'OOXML_XLSX';
    else if (ext === 'xls') extensionFormat = 'OLE2_BIFF';
    else if (ext === 'csv') extensionFormat = 'TEXT_DELIMITED';
    else if (ext === 'txt') extensionFormat = 'TEXT_FIXED_WIDTH';

    // Consistencia
    if (arrayBuffer && arrayBuffer.byteLength >= 8) {
        if (signatureFormat && signatureFormat !== extensionFormat) {
            throw new Error(`Inconsistencia de formato: la extensión es .${ext} pero la firma binaria indica ${signatureFormat}`);
        }
        if (!signatureFormat && (extensionFormat === 'OOXML_XLSX' || extensionFormat === 'OLE2_BIFF')) {
            throw new Error(`Inconsistencia de formato: la extensión es .${ext} pero el contenido no posee firma binaria de Excel válida`);
        }
    }

    return signatureFormat || extensionFormat;
}
