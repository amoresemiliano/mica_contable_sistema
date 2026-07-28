import { appStore } from './store.js';

// 3. PARSER DE SUELDOS (ACOMPY) - EXTRACCIÓN DIRECTA DE FILA DE TOTALES (SOLID: Single Responsibility)
export class SalaryParser {
    static parseExcel(arrayBuffer, customMapping = null) {
        const data = new Uint8Array(arrayBuffer);
        const workbook = window.XLSX.read(data, { type: 'array' });
        const firstSheetName = workbook.SheetNames[0];
        const worksheet = workbook.Sheets[firstSheetName];
        
        const rawRows = window.XLSX.utils.sheet_to_json(worksheet, { header: 1 });
        if (rawRows.length === 0) return { error: "El archivo está vacío." };

        // 1. Identificar cabecera
        let headerRowIdx = -1;
        for (let i = 0; i < Math.min(rawRows.length, 15); i++) {
            const row = rawRows[i];
            if (row.some(cell => {
                const str = String(cell).toLowerCase();
                return str.includes('legajo') || str.includes('bruto') || str.includes('neto') || str.includes('empleado') || str.includes('básico');
            })) {
                headerRowIdx = i;
                break;
            }
        }
        if (headerRowIdx === -1) headerRowIdx = 0;
        const headers = rawRows[headerRowIdx].map(h => String(h || '').trim());

        // 2. Mapear columnas dinámicamente o aplicar el custom mapping
        const mapping = customMapping || this.loadSavedMapping() || this.detectColumns(headers);

        // Validar si tenemos las columnas obligatorias (Bruto y Neto)
        if (mapping.sueldoBruto === undefined || mapping.sueldoNeto === undefined) {
            return {
                headers,
                rawRows: rawRows.slice(headerRowIdx + 1),
                mappingRequired: true,
                detectedMapping: mapping
            };
        }

        // Guardamos mapeo exitoso
        this.saveMapping(mapping);

        // 3. Buscar Fila de Control ("TOTAL")
        let targetRow = null;
        for (let i = headerRowIdx + 1; i < rawRows.length; i++) {
            const row = rawRows[i];
            if (!row || row.length === 0) continue;

            const firstCell = String(row[0] || '').toUpperCase();
            if (firstCell.includes('TOTAL')) {
                targetRow = row;
                break;
            }
        }

        if (!targetRow) {
            return { error: "No se encontró la fila final de TOTALES en el archivo de sueldos." };
        }

        // 4. Extraer importes consolidados
        const sueldoBruto = this.cleanNumber(targetRow[mapping.sueldoBruto]);
        const sueldoNeto = this.cleanNumber(targetRow[mapping.sueldoNeto]);
        
        // Opcionales (pueden venir vacíos en monotributistas o pequeñas empresas)
        const anticipos = mapping.anticipos !== undefined ? this.cleanNumber(targetRow[mapping.anticipos]) : 0;
        const sindicatoAporte = mapping.sindicatoAporte !== undefined ? this.cleanNumber(targetRow[mapping.sindicatoAporte]) : 0;

        return {
            sueldoBruto,
            sueldoNeto,
            anticipos,
            sindicatoAporte,
            mappingRequired: false
        };
    }

    // Heurísticas de palabras clave para mapeo difuso
    static detectColumns(headers) {
        const mapping = {};
        headers.forEach((h, idx) => {
            const clean = h.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, ""); // Limpiar tildes
            
            if (clean.includes('bruto') || clean.includes('remunerativo') || clean.includes('rem.') || clean.includes('basico')) {
                mapping.sueldoBruto = idx;
            } else if (clean.includes('neto') || clean.includes('a pagar') || clean.includes('liquido') || clean.includes('neto perc') || clean.includes('cobrar')) {
                mapping.sueldoNeto = idx;
            } else if (clean.includes('anticipo') || clean.includes('adelanto') || clean.includes('devolucion') || clean.includes('vale')) {
                mapping.anticipos = idx;
            } else if (clean.includes('sindicato') || clean.includes('cuota sindical') || clean.includes('aporte sindicato') || clean.includes('rempl.') || clean.includes('union')) {
                mapping.sindicatoAporte = idx;
            }
        });
        return mapping;
    }

    static cleanNumber(val) {
        if (!val) return 0;
        let str = String(val).replace(/\./g, '').replace(',', '.');
        return parseFloat(str) || 0;
    }

    static loadSavedMapping() {
        return JSON.parse(localStorage.getItem('mica_salary_mapping'));
    }

    static saveMapping(mapping) {
        localStorage.setItem('mica_salary_mapping', JSON.stringify(mapping));
    }
}
