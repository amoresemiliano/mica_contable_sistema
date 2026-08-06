/**
 * Configuración estricta del cliente (Tenant)
 */

export const TIPO_IVA = {
    RESPONSABLE_INSCRIPTO: 'RESPONSABLE_INSCRIPTO',
    MONOTRIBUTO: 'MONOTRIBUTO',
    EXENTO: 'EXENTO'
};

export const PERIODO_CONTABLE = {
    FECHA_MOVIMIENTO: 'FECHA_MOVIMIENTO',
    MANUAL: 'MANUAL'
};

/**
 * Valida y crea una configuración de tenant en tiempo de ejecución.
 * @param {Object} data 
 */
export function createTenantConfig(data) {
    if (!data) throw new Error("Configuración requerida");
    
    const allowedKeys = ['condicionIva', 'tratamientoIvaComisiones', 'toleranciaTributos', 'reglasJurisdiccion', 'periodoContableDefault'];
    for (const key of Object.keys(data)) {
        if (!allowedKeys.includes(key)) {
            throw new Error(`Propiedad desconocida o no autorizada: ${key}`);
        }
    }

    if (!Object.values(TIPO_IVA).includes(data.condicionIva)) {
        throw new Error(`Condición IVA inválida: ${data.condicionIva}`);
    }

    if (!Object.values(PERIODO_CONTABLE).includes(data.periodoContableDefault)) {
        throw new Error(`Período contable inválido: ${data.periodoContableDefault}`);
    }

    let tolerancia = 5.0;
    if (data.toleranciaTributos !== undefined) {
        if (typeof data.toleranciaTributos !== 'number' || !Number.isFinite(data.toleranciaTributos) || data.toleranciaTributos < 0) {
            throw new Error("toleranciaTributos debe ser un número finito mayor o igual a 0");
        }
        tolerancia = data.toleranciaTributos;
    }

    return {
        version: "1.0.0",
        condicionIva: data.condicionIva,
        tratamientoIvaComisiones: Boolean(data.tratamientoIvaComisiones),
        toleranciaTributos: tolerancia,
        reglasJurisdiccion: data.reglasJurisdiccion || {},
        periodoContableDefault: data.periodoContableDefault
    };
}
