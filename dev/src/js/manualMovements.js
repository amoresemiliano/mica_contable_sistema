import { appStore } from './store.js';

// 5. REGISTRO Y VALIDACIÓN DE MOVIMIENTOS MANUALES (SOLID: Single Responsibility)
export class ManualMovements {
    // Registra una compra manual con el formato estricto de REGINFO/LID AFIP
    static saveReginfoPurchase(fields) {
        // Validaciones críticas
        if (!fields.fecha || fields.fecha.length !== 8) {
            return { success: false, error: "La fecha debe tener 8 caracteres (AAAAMMDD)." };
        }
        if (!fields.tipoComprobante || fields.tipoComprobante.length !== 3) {
            return { success: false, error: "El tipo de comprobante debe ser de 3 caracteres (ej: 001)." };
        }
        if (!fields.puntoVenta || fields.puntoVenta.length !== 5 || isNaN(fields.puntoVenta)) {
            return { success: false, error: "Punto de Venta debe ser numérico de 5 dígitos." };
        }
        if (!fields.numeroComprobante || fields.numeroComprobante.length !== 8 || isNaN(fields.numeroComprobante)) {
            return { success: false, error: "El número de comprobante debe ser numérico de 8 dígitos." };
        }

        const total = parseFloat(fields.importeTotal) || 0;
        const noGravado = parseFloat(fields.importeNoGravado) || 0;
        const exento = parseFloat(fields.importeExento) || 0;
        const percIva = parseFloat(fields.importePercepIva) || 0;
        const percIibb = parseFloat(fields.importePercepIibb) || 0;
        const percMun = parseFloat(fields.importePercepMun) || 0;
        const impInternos = parseFloat(fields.importeInternos) || 0;
        
        // Tipo de cambio (por defecto 1.000000)
        let tipoCambio = parseFloat(fields.tipoCambio) || 1;
        
        const movement = {
            id: `reginfo-${Date.now()}`,
            origen: 'manual-reginfo',
            fecha: `${fields.fecha.substring(0,4)}-${fields.fecha.substring(4,6)}-${fields.fecha.substring(6,8)}`, // YYYY-MM-DD
            fechaRaw: fields.fecha,
            tipoComprobante: fields.tipoComprobante,
            puntoVenta: fields.puntoVenta,
            numeroComprobante: fields.numeroComprobante,
            cuit: fields.cuit.replace(/\D/g, ''),
            razonSocial: fields.razonSocial || 'Proveedor Manual',
            total,
            noGravado,
            exento,
            percIva,
            percIibb,
            percMun,
            impInternos,
            moneda: fields.moneda || 'PES',
            tipoCambio,
            cantidadAlicuotas: parseInt(fields.cantidadAlicuotas) || 1,
            confirmada: true
        };

        // Guardamos en el store unificado
        appStore.addManualMovement(movement);

        // Agregamos también como renglón a la grilla general para que se compute en las liquidaciones
        // Para simular la compra de ARCA, normalizamos para el store de compras
        appStore.addItems([{
            id: movement.id,
            tipo: 'recibido',
            fecha: `${fields.fecha.substring(6,8)}/${fields.fecha.substring(4,6)}/${fields.fecha.substring(0,4)}`, // DD/MM/YYYY
            comprobante: `${fields.tipoComprobante} - Factura Manual`,
            cuit: movement.cuit,
            razonSocial: movement.razonSocial,
            total,
            otrosTributos: percIva + percIibb + percMun + impInternos,
            saldoAExplicar: 0, // Las manuales se asumen ya explicadas por desglose
            percepcionesMapeadas: [
                { jurisdiction: 'IVA', amount: percIva },
                { jurisdiction: 'IIBB', amount: percIibb },
                { jurisdiction: 'MUNICIPAL', amount: percMun },
                { jurisdiction: 'INTERNOS', amount: impInternos }
            ],
            categoria: fields.categoria || 'Mercaderías / Insumos',
            sugerida: false,
            confirmada: true
        }]);

        return { success: true, movement };
    }

    // Registra movimientos internos de caja chica
    static saveInternalMovement(fields) {
        if (!fields.tipo || !fields.fecha || !fields.imputacion || !fields.importe) {
            return { success: false, error: "Los campos Tipo, Fecha, Imputación e Importe son obligatorios." };
        }

        const movement = {
            origen: 'manual-interno',
            tipo: fields.tipo, // 'Ingreso' o 'Gasto'
            fecha: fields.fecha, // YYYY-MM-DD
            imputacion: fields.imputacion, // YYYY-MM (impacto contable)
            importe: parseFloat(fields.importe) || 0,
            descripcion: fields.descripcion || '',
            confirmada: true
        };

        appStore.addManualMovement(movement);
        return { success: true, movement };
    }
}
