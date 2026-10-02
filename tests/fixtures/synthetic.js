export const ARBA_FIXTURES = {
    valid: "000000003071111111201/05/2026000000000001 0000000000123400000001000,50",
    short: "000000003071111111201/05/2026",
    long: "000000003071111111201/05/2026000000000001 0000000000123400000001000,50XXXXX",
    invalidCuit: "00000000307111A111201/05/2026000000000001 0000000000123400000001000,50",
    invalidDate: "0000000030711111112XX/XX/XXXX000000000001 0000000000123400000001000,50",
    invalidMonto: "000000003071111111201/05/2026000000000001 00000000001234XXXXX001000,50"
};

export const ARCA_COMPRAS_30 = [
    ["Fecha", "Tipo", "Punto de Venta", "Numero Desde", "Numero Hasta", "Cód. Autorización", "Tipo Doc. Emisor", "Nro. Doc. Emisor", "Denominación Emisor", "Tipo Cambio", "Moneda", "Imp. Neto Gravado", "Neto No Gravado", "Op. Exentas", "Otros Tributos", "IVA 21%", "Imp. Total"],
    ["01/05/2026", "1", "15", "100", "100", "123", "80", "30711111112", "EMPRESA A", "1", "PES", "100", "0", "0", "0", "21", "121"]
];

export const ARCA_VENTAS_19 = [
    ["Fecha", "Tipo", "Punto de Venta", "Numero Desde", "Numero Hasta", "Cód. Autorización", "Tipo Doc. Receptor", "Nro. Doc. Receptor", "Denominación Receptor", "Tipo Cambio", "Moneda", "Imp. Neto Gravado", "Neto No Gravado", "Op. Exentas", "Otros Tributos", "IVA 21%", "Imp. Total"],
    ["01/05/2026", "1", "15", "100", "100", "123", "80", "30722222223", "CLIENTE B", "1", "PES", "100", "0", "0", "0", "21", "121"]
];

export const ARCA_SIN_HEADER = [
    ["01/05/2026", "1", "15", "100", "100", "123", "80", "30722222223", "CLIENTE B", "1", "PES", "100", "0", "0", "0", "21", "121"]
];

export const ARCA_COL_AUSENTE = [
    ["Fecha", "Tipo", "Punto de Venta"], // Falta Imp. Total
    ["01/05/2026", "1", "15"]
];

export const ARCA_IMPORTE_INVALIDO = [
    ["Fecha", "Punto de Venta", "Imp. Total", "Nro. Doc. Emisor", "Numero Desde"],
    ["01/05/2026", "15", "INVALIDO", "30711111112", "100"]
];

export const ARCA_CAMPO_OBLIGATORIO_VACIO = [
    ["Fecha", "Punto de Venta", "Imp. Total", "Nro. Doc. Emisor", "Numero Desde"],
    ["01/05/2026", "15", "", "30711111112", "100"]
];

export const ARCA_VARIAS_ALICUOTAS = [
    ["Fecha", "Punto de Venta", "Imp. Total", "Nro. Doc. Emisor", "Numero Desde", "Neto Grav. IVA 21%", "IVA 21%", "Neto Grav. IVA 10,5%", "IVA 10,5%"],
    ["01/05/2026", "15", "200", "30711111112", "100", "100", "21", "100", "10,5"]
];

export const ARCA_MONEDA_EXTRANJERA_SIN_TC = [
    ["Fecha", "Punto de Venta", "Imp. Total", "Nro. Doc. Emisor", "Numero Desde", "Moneda", "Tipo Cambio"],
    ["01/05/2026", "15", "100", "30711111112", "100", "DOL", ""]
];


export const BBVA_DESPLAZADO = [
    ["Extracto de cuenta"],
    ["Periodo: Mayo 2026"],
    [""],
    [""],
    [""],
    [""],
    ["Fec. Valor", "Fec. Operación", "Concepto", "Referencia", "Importe", "Saldo"],
    ["01/05/2026", "01/05/2026", "TRANSFERENCIA", "123", "1000,50", "1000,50"],
    ["02/05/2026", "02/05/2026", "PAGO", "124", "-500,00", "500,50"]
];

export const BBVA_SIMULTANEO = [
    ["Fecha", "Concepto", "Debito", "Credito"],
    ["01/05/2026", "DOBLE", "100", "100"]
];

export const BBVA_VACIOS = [
    ["Fecha", "Concepto", "Debito", "Credito"],
    ["01/05/2026", "VACIO", "", ""]
];

export const BBVA_SOLO_CREDITO = [
    ["Fecha", "Concepto", "Debito", "Credito"],
    ["01/05/2026", "INGRESO", "", "1000"]
];

export const BBVA_SIN_ENCABEZADO = [
    ["01/05/2026", "01/05/2026", "PAGO", "123", "444", "001", "", "100", ""]
];

export const BBVA_DOS_CANDIDATOS = [
    ["Fecha", "Otra Cosa", "Valor"],
    ["01/05/2026", "Basura", "0"],
    ["Fecha", "Concepto", "Debito", "Credito"],
    ["01/05/2026", "PAGO", "100", ""]
];

export const BBVA_SIRCREB = [
    ["Fecha", "Concepto", "Importe"],
    ["01/05/2026", "RETENCION SIRCREB BA", "-100"]
];

export const BBVA_COMISION = [
    ["Fecha", "Concepto", "Importe"],
    ["01/05/2026", "COMISION MANTENIMIENTO", "-50"]
];


export const ACOMPY_JUNIO_SAC = [
    ["Legajo", "CUIL", "Nombre", "Sueldo Neto", "SAC Proporcional", "Remunerativo", "No Remunerativo", "Total"],
    ["1", "20111111112", "JUAN", "1000", "500", "1500", "200", "1700"],
    ["", "", "TOTALES", "1000", "500", "1500", "200", "1700"]
];

export const ACOMPY_SUBTOTAL = [
    ["Legajo", "Sueldo", "Remunerativo", "No Remunerativo", "Total"],
    ["SUBTOTAL", "", 500, 100, 600],
    ["TOTALES:", "", 1000, 200, 1200]
];

export const ACOMPY_MAYO_SIN_SAC = [
    ["Legajo", "CUIL", "Nombre", "Sueldo Neto", "Remunerativo", "No Remunerativo", "Total"],
    ["1", "20111111112", "JUAN", "1000", "1500", "200", "1700"],
    ["", "", "TOTALES:", "1000", "1500", "200", "1700"]
];

export const ACOMPY_SIN_TOTALES = [
    ["Legajo", "CUIL", "Nombre", "Sueldo Neto", "Remunerativo", "No Remunerativo", "Total"],
    ["1", "20111111112", "JUAN", "1000", "1500", "200", "1700"]
];

export const ACOMPY_MULTIPLES_TOTALES = [
    ["Legajo", "CUIL", "Nombre", "Sueldo Neto", "Remunerativo", "No Remunerativo", "Total"],
    ["", "", "TOTALES DE SECCION", "500", "500", "0", "500"],
    ["", "", "TOTALES DEL MES", "1000", "1500", "200", "1700"]
];

export const ACOMPY_TOTALES_FUERA_DE_COLUMNA_1 = [
    ["Legajo", "Nombre", "Remunerativo", "Total"],
    ["1", "TOTALES:", "1000", "1000"]
];

export const ACOMPY_COLUMNA_OPCIONAL_AUSENTE = [
    ["Legajo", "Nombre", "Remunerativo", "Total"], // No hay "No Remunerativo"
    ["", "TOTALES:", "1500", "1500"]
];
