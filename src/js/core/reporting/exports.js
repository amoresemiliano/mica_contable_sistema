export const escapeHtml = value => String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const formatMoney = value => value==null?'No disponible':new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(value/100);
export const formatPercent = value => value==null?'Sin comparación':`${new Intl.NumberFormat('es-AR',{maximumFractionDigits:1}).format(value)} %`;
export const formatDate = value => /^\d{4}-\d{2}-\d{2}/.test(value||'')?value.slice(0,10).split('-').reverse().join('/'):'—';
export function reportFilename(report,extension) {
 const company=report.company_name.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-zA-Z0-9]+/g,'_').replace(/^_|_$/g,'').slice(0,64)||'EMPRESA';
 const period=report.type==='GANANCIAS'?report.from.slice(0,4):report.from.slice(0,7)===report.to.slice(0,7)?report.from.slice(0,7):`${report.from.slice(0,7)}_${report.to.slice(0,7)}`;
 return `MICA_${company}_${report.type}_${period}.${extension}`;
}
export function reportSheets(report) {
 const calculations=[['Período','Jurisdicción','Concepto','Importe ARS','Actividad','Base jurisdiccional ARS','Coeficiente','Alícuota %','Referencia tasa','Fórmula','Registros','Origen manual','Faltantes'],...report.rows.map(r=>[r.month,r.jurisdiction||'',r.label,r.value==null?'No disponible':r.value/100,r.activity_name||r.activity_id||'',r.base==null?'':r.base/100,r.coefficient??'',r.rate??'',r.rate_id||'',r.formula,r.source_count,r.manual.map(m=>`${m.kind} ${m.period} rev ${m.revision}`).join('; '),r.missing.join('; ')])];
 const codes=[...new Set(report.rows.map(r=>r.code))],months=[...new Set(report.rows.map(r=>r.month))];
 const comparative=[['Concepto',...months,'Acumulado (solo flujos)'],...codes.map(code=>{const label=report.rows.find(r=>r.code===code).label;const values=months.map(m=>{const rows=report.rows.filter(r=>r.code===code&&r.month===m);return !rows.length||rows.some(r=>r.value==null)?null:rows.reduce((n,r)=>n+r.value,0)/100;});const stock=/prior|next|technical_period|annual_|credit|free_/.test(code);return [label,...values.map(v=>v??'No disponible'),stock?'No acumulable':values.some(v=>v==null)?'No disponible':values.reduce((a,b)=>a+b,0)];})];
 return {
  Resumen:comparative,
  Calculos:calculations,
  Fuentes:[['Línea','Período','Fuente','Cantidad','Campo','Filtro de detalle','IDs (snapshot)'],...report.rows.flatMap(r=>r.sources.map(s=>[r.label,r.month,s.source_type,s.count,s.field,JSON.stringify(s.filter),(s.ids||[]).join(',')]))],
  Manuales:[['ID','Tipo','Período','Revisión','Usuario','Fecha','Nota','Valores (centavos)'],...report.manual_inputs.map(i=>[i.id,i.kind,i.period,i.revision,i.created_by,i.created_at,i.note,JSON.stringify(i.payload)])],
  Metadatos:[['Campo','Valor'],...Object.entries({organization_id:report.organization_id,empresa:report.company_name,cuit:report.cuit||'No disponible',reporte:report.type,desde:report.from,hasta:report.to,generado:report.generated_at,usuario:report.generated_by,estado:report.status,version_motor:report.engine_version,hash_entradas:report.input_hash,version_cierre:report.version||'',snapshot:report.snapshot_id||'',aviso:report.disclaimer})]
 };
}
const csvCell = value => {const text=String(value??'');const safe=typeof value==='string'&&/^[\s\u0000-\u001f]*[=+\-@]/.test(text)?`'${text}`:text;return `"${safe.replaceAll('"','""')}"`;};
export function reportCsv(report) {
 return '\uFEFF'+Object.entries(reportSheets(report)).map(([name,rows])=>[[name],...rows].map(r=>r.map(csvCell).join(';')).join('\r\n')).join('\r\n\r\n');
}
export function reportWorkbook(report,XLSX) {
 const book=XLSX.utils.book_new();
 for(const [name,rows] of Object.entries(reportSheets(report))){const sheet=XLSX.utils.aoa_to_sheet(rows);sheet['!cols']=rows[0].map((_,i)=>({wch:i===2?44:24}));XLSX.utils.book_append_sheet(book,sheet,name);}
 return book;
}
export function printReportHtml(report) {
 return `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${escapeHtml(reportFilename(report,'pdf'))}</title><style>body{font:12px system-ui;color:#172638}h1{font-size:22px}table{border-collapse:collapse;width:100%;margin:16px 0}td,th{padding:6px;border:1px solid #cbd5e1;text-align:left}thead{display:table-header-group}tr{break-inside:avoid}@page{size:A4 landscape;margin:12mm}</style></head><body><h1>MICA · ${escapeHtml(report.type)} · ${escapeHtml(report.company_name)}</h1><p>CUIT: ${escapeHtml(report.cuit||'No disponible')} · ${formatDate(report.from)} — ${formatDate(report.to)} · ${escapeHtml(report.status)}</p><p>${escapeHtml(report.disclaimer)}</p>${Object.entries(reportSheets(report)).map(([name,rows])=>`<h2>${escapeHtml(name)}</h2><table><thead><tr>${rows[0].map(c=>`<th>${escapeHtml(c)}</th>`).join('')}</tr></thead><tbody>${rows.slice(1).map(r=>`<tr>${r.map(c=>`<td>${escapeHtml(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`).join('')}</body></html>`;
}
export function downloadReport(report,format,{document=globalThis.document,XLSX=globalThis.XLSX}={}) {
 if(format==='xlsx'){if(!XLSX)throw new Error('La biblioteca XLSX no está disponible.');XLSX.writeFile(reportWorkbook(report,XLSX),reportFilename(report,'xlsx'));return;}
 if(format==='pdf'){
  const frame=document.createElement('iframe');frame.title='Vista de impresión del reporte';frame.style.cssText='position:fixed;width:1px;height:1px;left:-9999px';
  frame.onload=()=>{frame.contentWindow.focus();frame.contentWindow.print();};frame.srcdoc=printReportHtml(report);document.body.append(frame);
  setTimeout(()=>frame.remove(),60000);return;
 }
 const url=URL.createObjectURL(new Blob([reportCsv(report)],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download=reportFilename(report,'csv');a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
