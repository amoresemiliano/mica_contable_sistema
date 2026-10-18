import { tenantCan } from './moduleAccess.js';
import { semanticExtractors } from './operationalSemantics.js';

// These extractors are shared with the rendered grids, before pagination.
export const exportExtractors = {
    comprobantes: { razonSocial: i => i.razonSocial || i.agente || '', cuit: i => i.cuit || '',
        comprobante: i => i.comprobante || '', total: i => i.total || 0,
        iva: i => i.iva || i.importeIva || 0, fecha: i => i.fecha || '' },
    percepciones: { fuente: p => p.fuente || p.jurisdiction || p.jurisdiccion || '',
        agente: p => p.agente || p.razonSocial || '',
        monto: p => typeof p.amount === 'number' ? p.amount : (typeof p.monto === 'number' ? p.monto : parseFloat(p.importe) || 0) },
    bancos: {fecha:t=>t.fecha || t.fechaValor || '',descripcion:t=>t.descripcion || t.concepto || '',monto:t=>t.monto || t.amount || 0}
};

export const columns = {
    bancos: [['Fecha','fecha'],['Descripción','descripcion'],['Importe','monto'],['Tipo','tipo'],['Cuenta','cuenta'],['Categoría','categoria'],['Actividad','actividad']],
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
    const status = store.operationalDataStatus?.({comprobantes:'tab-conciliador',percepciones:'tab-percepciones',sueldos:'tab-sueldos',bancos:'tab-bancos'}[module]);
    if (status?.loading || status?.error) return [];
    const source = module === 'comprobantes' ? store.items : module === 'percepciones' ? store.perceptions : module === 'bancos' ? store.bankTransactions : [store.salaries].filter(Boolean);
    const scoped = (source || []).filter(r => r.organization_id === store.activeOrganizationId);
    return grid ? grid.filterAndSort(scoped, semanticExtractors(store, exportExtractors[module])) : scoped;
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
        if (module === 'bancos') Object.assign(row, Object.fromEntries(Object.entries(exportExtractors.bancos).map(([key,get])=>[key,get(r)])));
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
    XLSX.utils.book_append_sheet(book, sheet, {comprobantes:'Comprobantes',percepciones:'Percepciones',sueldos:'Sueldos',bancos:'Extractos'}[module]);
    return book;
}

const safeName = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9_-]+/g,'_').replace(/^_+|_+$/g,'').slice(0,64);
export function moduleFilename(store, module, grid, records, format) {
    const period = module === 'sueldos' ? records[0]?.periodo : grid?.dateMode === 'custom'
        ? `${grid.startDate || 'inicio'}_${grid.endDate || 'fin'}` : grid?.periodFilter;
    return `mica_${module}_${safeName(store.confirmedOrganizationName) || 'empresa'}_${safeName(period) || 'todos'}.${format}`;
}

export function downloadModule(store, module, grid, format, {XLSX=globalThis.XLSX, document=globalThis.document}={}) {
    if (!['csv','xlsx','pdf'].includes(format)) throw new Error('Formato desconocido.');
    const records = moduleExportRecords(store, module, grid);
    if (!records.length) throw new Error('No hay registros disponibles para exportar con estos filtros y empresa.');
    const rows = moduleExportRows(store, module, records);
    const filename = moduleFilename(store, module, grid, records, format);
    if (format === 'pdf') {
        const frame=document.createElement('iframe');frame.title='Vista de impresión';
        frame.style.cssText='position:fixed;width:1px;height:1px;left:-9999px';
        frame.onload=()=>{frame.contentWindow.focus();frame.contentWindow.print();};
        frame.srcdoc=modulePrintHtml(store,module,grid,records);document.body.append(frame);
        setTimeout(()=>frame.remove(),60000);
    } else if (format === 'xlsx') {
        if (!XLSX) throw new Error('La biblioteca XLSX no está disponible.');
        XLSX.writeFile(moduleWorkbook(rows,module,XLSX),filename);
    } else {
        const url = URL.createObjectURL(new Blob([moduleCsv(rows)],{type:'text/csv;charset=utf-8'}));
        const link = document.createElement('a');
        link.href=url; link.download=filename; link.click();
        setTimeout(() => URL.revokeObjectURL(url),1000);
    }
}

const html = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function modulePrintHtml(store,module,grid,records,generated=new Date()) {
    const rows=moduleExportRows(store,module,records);
    const aliases={tipoOperacion:'origen',netoGravado:'neto',exento:'exentas',activity_id:'actividad',period:'periodo',amount:'monto',razonSocial:module==='percepciones'?'agente':'razonSocial',...(module==='bancos'?{categoria:'cuenta',actividad:'cuenta'}:{})};
    // Currency and exchange rate are mandatory context even when the grid hides them.
    const indices=columns[module].flatMap(([,key],index)=>!grid || ['moneda','tipoCambio'].includes(key) || grid.isColumnVisible(aliases[key] || key) ? [index] : []);
    const reportRows=rows.map(row=>indices.map(index=>row[index]));
    const filter=[grid?.primaryFilter,grid?.dateMode==='custom'?`${grid.startDate || 'inicio'} — ${grid.endDate || 'fin'}`:grid?.periodFilter,grid?.searchQuery].filter(Boolean).join(' · ') || records[0]?.periodo || 'Todos';
    const title={comprobantes:'Comprobantes',percepciones:'Percepciones',bancos:'Bancos / Extractos',sueldos:'Sueldos'}[module];
    return `<!doctype html><html lang="es"><meta charset="utf-8"><title>${html(moduleFilename(store,module,grid,records,'pdf'))}</title><style>@page{size:A3 landscape;margin:12mm}body{font:10pt system-ui;color:#172638}h1{font-size:18pt}table{border-collapse:collapse;width:100%;font-size:8pt;table-layout:fixed}th,td{border:1px solid #ccd5df;padding:5px;text-align:left;overflow-wrap:anywhere}thead{display:table-header-group}tr{break-inside:avoid}footer{margin-top:12px}</style><h1>MICA · ${html(title)}</h1><h2>${html(store.confirmedOrganizationName)}</h2><p>Período / filtros: ${html(filter)}<br>Generado: ${html(generated.toISOString())}</p><table><thead><tr>${reportRows[0].map(v=>`<th>${html(v)}</th>`).join('')}</tr></thead><tbody>${reportRows.slice(1).map(row=>`<tr>${row.map(v=>`<td>${html(v)}</td>`).join('')}</tr>`).join('')}</tbody></table><footer>${records.length} registros</footer></html>`;
}
