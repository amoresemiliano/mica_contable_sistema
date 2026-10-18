// Alias normalization only. This module never applies an exchange rate.
export const ARS_ALIASES = Object.freeze(['ARS', 'PES', '$']);
export function normalizeReportingCurrency(value) {
    const code = typeof value === 'string' ? value.trim().toUpperCase() : null;
    return ARS_ALIASES.includes(code) ? 'ARS' : code || null;
}
export const isArsCurrency = row => normalizeReportingCurrency(row.currency) === 'ARS';

export function currencyExclusions(rows, field = 'amount') {
    const currencies = new Map();
    for (const row of rows.filter(row => !isArsCurrency(row))) {
        const currency = normalizeReportingCurrency(row.currency) || 'SIN MONEDA';
        const group = currencies.get(currency) || { currency, record_count: 0, group_count: 0, source_value: 0, field };
        group.record_count += Number(row.count);
        group.group_count++;
        // Source cents stay in their original currency, never in an ARS sum.
        group.source_value = group.source_value == null || row[field] == null ? null : group.source_value + Number(row[field]);
        if (group.source_value != null && !Number.isSafeInteger(group.source_value)) throw new Error('Importe de origen fuera de rango.');
        currencies.set(currency, group);
    }
    return [...currencies.values()];
}

export function currencyWarnings(rows) {
    const descriptions = { SALES: 'comprobantes de venta', PURCHASES: 'comprobantes de compra', MANUAL_PURCHASE: 'comprobantes de compra manual', BANK: 'movimientos bancarios', PAYROLL: 'registros de sueldos', TAX: 'registros fiscales', OTHER_INCOME: 'otros ingresos', OTHER_EXPENSE: 'otros egresos' };
    const kinds = new Set(rows.filter(row => !isArsCurrency(row)).map(row => row.kind));
    return [...kinds].flatMap(kind => currencyExclusions(rows.filter(row => row.kind === kind)).map(group =>
        `${group.record_count} ${descriptions[kind] || 'registros'} en ${group.currency} pendientes de conversión; excluidos del cálculo en ARS.`));
}
