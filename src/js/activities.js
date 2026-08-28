import { appStore } from './store.js';

// 6. MOTOR DE IMPUTACIÓN Y MULTI-ACTIVIDAD (SOLID: Single Responsibility)
export class Activities {
    // Retorna las actividades económicas registradas para el CUIT de la empresa activa
    static getClientActivities(cuit) {
        // Mock de base de datos de actividades por empresa (código fiscal NAES)
        const database = {
            '20263235550': [
                { id: 'act1', nombre: 'Servicios de Asesoramiento', codigo: '702091' }
            ],
            '30710536461': [
                { id: 'act1', nombre: 'Servicios Informáticos / Consultoría', codigo: '620900' },
                { id: 'act2', nombre: 'Exportación de Software', codigo: '620100' }
            ]
        };

        return database[cuit] || [{ id: 'act-unica', nombre: 'Actividad General', codigo: '999999' }];
    }

    // Procesa el comprobante de venta e imputa su actividad
    static processVentaComprobante(item, cuitEmpresaActiva) {
        const activities = this.getClientActivities(cuitEmpresaActiva);

        if (activities.length === 1) {
            // Regla de Actividad Única: Asignación automática del 100% de las variables
            item.actividad = activities[0].id;
            item.imputacionDetalle = [{
                actividadId: activities[0].id,
                actividadNombre: activities[0].nombre,
                codigoNaes: activities[0].codigo,
                netoGravado: item.netoGravado,
                noGravado: item.noGravado,
                exento: item.exento,
                iva: item.iva
            }];
            item.confirmada = true;
            return { requiredAction: 'auto_assigned', item };
        } else {
            // Regla Multi-Actividad: Requiere desplegar pop-up visual de selección obligatoria
            return { requiredAction: 'modal_required', item, activities };
        }
    }

    // Opción 1: Asignar TODO el comprobante a una sola actividad
    static assignAllToActivity(itemId, activityId, cuitEmpresaActiva) {
        const item = appStore.items.find(i => i.id === itemId);
        const activities = this.getClientActivities(cuitEmpresaActiva);
        const selected = activities.find(a => a.id === activityId);

        if (item && selected) {
            item.actividad = selected.id;
            item.imputacionDetalle = [{
                actividadId: selected.id,
                actividadNombre: selected.nombre,
                codigoNaes: selected.codigo,
                netoGravado: item.netoGravado,
                noGravado: item.noGravado,
                exento: item.exento,
                iva: item.iva
            }];
            item.confirmada = true;
            appStore.notify();
        }
    }

    // Opción 2: Dividir (Itemizar) montos entre actividades
    static assignSplitToActivities(itemId, splits) {
        // splits = [{ actividadId, netoGravado, noGravado, exento, iva }]
        const item = appStore.items.find(i => i.id === itemId);
        if (!item) return;

        // Validar que la suma coincida con los totales del comprobante
        let sumNeto = 0;
        let sumNoGravado = 0;
        let sumExento = 0;
        let sumIva = 0;

        splits.forEach(s => {
            sumNeto += parseFloat(s.netoGravado) || 0;
            sumNoGravado += parseFloat(s.noGravado) || 0;
            sumExento += parseFloat(s.exento) || 0;
            sumIva += parseFloat(s.iva) || 0;
        });

        // Toleramos diferencias mínimas de centavos debido al redondeo
        const tolerance = 0.5;
        if (Math.abs(sumNeto - item.netoGravado) > tolerance ||
            Math.abs(sumExento - item.exento) > tolerance) {
            return { success: false, error: "La suma de los montos divididos no coincide con los totales del comprobante." };
        }

        item.actividad = 'ITEMIZADO';
        item.imputacionDetalle = splits.map(s => ({
            actividadId: s.actividadId,
            actividadNombre: s.actividadNombre,
            codigoNaes: s.codigoNaes,
            netoGravado: s.netoGravado,
            noGravado: s.noGravado,
            exento: s.exento,
            iva: s.iva
        }));
        item.confirmada = true;
        appStore.notify();

        return { success: true };
    }
}
