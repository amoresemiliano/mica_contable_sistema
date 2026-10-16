import { tenantCan } from './moduleAccess.js';

// These extractors are shared with the rendered grids, before pagination.
export const exportExtractors = {
    comprobantes: { razonSocial: i => i.razonSocial || i.agente || '', cuit: i => i.cuit || '',
        comprobante: i => i.comprobante || '', total: i => i.total || 0,
        iva: i => i.iva || i.importeIva || 0, fecha: i => i.fecha || '' },
    percepciones: { fuente: p => p.fuente || p.jurisdiction || p.jurisdiccion || '',
        agente: p => p.agente || p.razonSocial || '',
        monto: p => typeof p.amount === 'number' ? p.amount : (typeof p.monto === 'number' ? p.monto : parseFloat(p.importe) || 0) }
};

const columns = {
    comprobantes: [['Fecha','fecha'],['Operación','tipoOperacion'],['Tipo de comprobante','tipo_cbte'],
        ['Comprobante','comprobante'],['CUIT','cuit'],['Razón social','razonSocial'],['Moneda','moneda'],
        ['Tipo de cambio','tipoCambio'],['Neto gravado','netoGravado'],['Neto no gravado','netoNoGravado'],
        ['Exento','exento'],['IVA','iva'],['Otros tributos','otrosTributos'],['Total','total'],
        ['Categoría','categoria'],['Actividad','actividad'],['Estado','estado']],
    percepciones: [['Fecha','fecha'],['Período','period'],['Tipo','tipo'],['Fuente / impuesto','fuente'],
        ['Régimen','regimen'],['Jurisdicción','jurisdiction'],['CUIT','cuit'],['Agente / razón social','razonSocial'],
        ['Comprobante','comprobante'],['Importe','amount'],['Categoría','categoria'],['Actividad','actividad']],
    sueldos: [['Período','periodo'],['Fuente','fuente'],['Remunerativo','remunerativo'],
        ['No remunerativo','noRemunerativo'],['Anticipos','anticipos'],['SAC proporcional','sacProporcional'],
        ['Aporte sindical obligatorio','aporteSindicalObligatorio'],['FAECYS','faecys'],
        ['Sueldo neto total','sueldoNeto'],['Sueldo bruto calculado','sueldoBrutoCalculado'],
        ['Aporte sindical calculado','aporteSindicalCalculado']]
};

export function moduleExportRecords(store, module, grid) {
    if (!columns[module]) throw new Error('Módulo de exportación desconocido.');
    if (!store.canOperationalAction('export') || !tenantCan(store, 'RECORD_VIEW')) return [];
    const status = store.operationalDataStatus?.({comprobantes:'tab-conciliador',percepciones:'tab-percepciones',sueldos:'tab-sueldos'}[module]);
    if (status?.loading || status?.error) return [];
    const source = module === 'comprobantes' ? store.items : module === 'percepciones' ? store.perceptions : [store.salaries].filter(Boolean);
    const scoped = (source || []).filter(r => r.organization_id === store.activeOrganizationId);
    return grid ? grid.filterAndSort(scoped, exportExtractors[module]) : scoped;
}

const scalar = value => typeof value === 'number' ? (Number.isFinite(value) ? value : '')
    : typeof value === 'string' || typeof value === 'boolean' ? value : '';
export function moduleExportRows(store, module, records) {
    const name = (catalog, id) => catalog?.find(r => r.id === id)?.name || '';
    return [columns[module].map(([label]) => label), ...records.map(r => {
        const row = {...r,
            categoria: name(store.taxCategories, r.category_id) || r.categoria,
            actividad: name(store.economicActivities, r.activity_id),
            estado: r.confirmada ? 'Categorizado' : 'Pendiente'};
        if (module === 'comprobantes') row.tipoOperacion = r.tipoOperacion || (r.tipo === 'recibido' ? 'COMPRA' : 'VENTA');
        if (module === 'percepciones') Object.assign(row, {
            period: r.period || r.periodo, fuente: r.fuente || r.jurisdiction || r.jurisdiccion,
            jurisdiction: r.jurisdiction || r.jurisdiccion, razonSocial: r.razonSocial || r.agente,
            amount: exportExtractors.percepciones.monto(r)});
        return columns[module].map(([,key]) => scalar(row[key]));
    })];
}

export function moduleCsv(rows) {
    return '\uFEFF' + rows.map(row => row.map(value => {
        const text = String(scalar(value));
        const safe = typeof value === 'string' && /^[\s\u0000-\u001f]*[=+\-@]/.test(text) ? "'" + text : text;
        return '"' + safe.replaceAll('"','""') + '"';
    }).join(';')).join('\r\n');
}

export function moduleWorkbook(rows, module, XLSX) {
    const book = XLSX.utils.book_new();
    const sheet = XLSX.utils.aoa_to_sheet(rows);
    sheet['!cols'] = rows[0].map(() => ({wch:24}));
    XLSX.utils.book_append_sheet(book, sheet, {comprobantes:'Comprobantes',percepciones:'Percepciones',sueldos:'Sueldos'}[module]);
    return book;
}

const safeName = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9_-]+/g,'_').replace(/^_+|_+$/g,'').slice(0,64);
export function moduleFilename(store, module, grid, records, format) {
    const period = module === 'sueldos' ? records[0]?.periodo : grid?.dateMode === 'custom'
        ? `${grid.startDate || 'inicio'}_${grid.endDate || 'fin'}` : grid?.periodFilter;
    return `mica_${module}_${safeName(store.confirmedOrganizationName) || 'empresa'}_${safeName(period) || 'todos'}.${format}`;
}

export function downloadModule(store, module, grid, format, {XLSX=globalThis.XLSX, document=globalThis.document}={}) {
    if (!['csv','xlsx'].includes(format)) throw new Error('Formato desconocido.');
    const records = moduleExportRecords(store, module, grid);
    if (!records.length) throw new Error('No hay registros disponibles para exportar con estos filtros y empresa.');
    const rows = moduleExportRows(store, module, records);
    const filename = moduleFilename(store, module, grid, records, format);
    if (format === 'xlsx') {
        if (!XLSX) throw new Error('La biblioteca XLSX no está disponible.');
        XLSX.writeFile(moduleWorkbook(rows,module,XLSX),filename);
    } else {
        const url = URL.createObjectURL(new Blob([moduleCsv(rows)],{type:'text/csv;charset=utf-8'}));
        const link = document.createElement('a');
        link.href=url; link.download=filename; link.click();
        setTimeout(() => URL.revokeObjectURL(url),1000);
    }
}
