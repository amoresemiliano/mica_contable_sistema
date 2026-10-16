import {escapeHtml as e} from '../core/reporting/exports.js';

export function financeHeader(title,subtitle,eyebrow='MICA · Visión del negocio') {
 return `<header class="finance-header"><div><span class="finance-eyebrow">${e(eyebrow)}</span><h1>${e(title)}</h1><p>${e(subtitle)}</p></div><span class="finance-context">Empresa activa · datos documentados</span></header>`;
}
export function statusChip(label,tone='neutral') {
 return `<span class="finance-chip finance-chip--${e(tone)}">${e(label)}</span>`;
}
export const statusTone=status=>({GREEN:'positive',HEALTHY:'positive',POSITIVE_SIGNAL:'positive',YELLOW:'warning',WATCH:'warning',INCOMPLETE:'warning',RED:'critical',CRITICAL:'critical',INSUFFICIENT_DATA:'neutral',NO_ACTIVITY:'neutral'})[status]||'neutral';
export function sectionHeading(title,note='') {
 return `<div class="finance-section-heading"><h2>${e(title)}</h2>${note?`<p>${e(note)}</p>`:''}</div>`;
}
export function emptyState(title,note) {
 return `<div class="finance-empty"><span class="finance-eyebrow">Sin conclusión disponible</span><strong>${e(title)}</strong><p>${e(note)}</p></div>`;
}

// Presentation annotations only. Existing event selectors, source values and
// permission-gated controls remain owned by the reporting controller.
export function refineReportingPresentation(root,mode) {
 const shell=root.querySelector('.mr-shell');if(!shell)return;
 shell.classList.add('finance-surface',`finance-${mode}`);
 const heading=shell.querySelector('.mr-heading h2');
 if(heading){const note=document.createElement('p');note.className='finance-subtitle';note.textContent=mode==='management'?'Una lectura clara de ventas, resultados y movimientos del negocio.':'Prepará, revisá y conservá reportes con respaldo en cada cálculo.';heading.after(note);}
 for(const button of shell.querySelectorAll('[data-refresh], [data-preview]'))button.classList.add('finance-primary');
 for(const button of shell.querySelectorAll('[data-export]'))button.classList.add('finance-export');
 for(const button of shell.querySelectorAll('[data-status]'))button.classList.add('finance-workflow');
 const toolbar=shell.querySelector('.mr-report-toolbar');
 if(toolbar){for(const [label,selector] of [['Preparar','label, [data-preview]'],['Exportar','[data-export]'],['Versiones','[data-status], [data-history]']]){
  const nodes=[...toolbar.querySelectorAll(selector)];if(!nodes.length)continue;
  const group=document.createElement('div');group.className='finance-action-group';group.setAttribute('role','group');group.setAttribute('aria-label',label);
  const caption=document.createElement('span');caption.className='finance-action-label';caption.textContent=label;group.append(caption,...nodes);toolbar.append(group);
 }}
 const kpis=shell.querySelector('.mr-kpis');
 if(kpis){kpis.insertAdjacentHTML('beforebegin',sectionHeading('Resumen ejecutivo','Indicadores documentales del período · abrí una tarjeta para ver su cálculo.'));
  for(const card of kpis.children){const incomplete=card.querySelector('.mr-metric-warning'),value=card.querySelector('strong')?.textContent||'';
   const unavailable=/No disponible|No determinable|Sin datos|Sin comparación/.test(value),tone=incomplete?'warning':unavailable?'neutral':card.classList.contains('mr-negative')?'critical':'info';
   card.dataset.presentationTone=tone;
   card.insertAdjacentHTML('afterbegin',statusChip(incomplete?'Parcial':unavailable?'No disponible':'Documentado',tone));
   card.insertAdjacentHTML('beforeend','<span class="finance-card-link">Ver cálculo <span aria-hidden="true">↗</span></span>');
  }
 }
 for(const panel of shell.querySelectorAll('.mr-panel')){
  if(panel.querySelector('.mr-chart'))panel.classList.add('finance-chart-panel');
  const alerts=[...panel.querySelectorAll('.mr-alert')];
  if(alerts.length){panel.classList.add('finance-alert-panel');
   for(const [title,selector] of [['Requiere atención',a=>a.classList.contains('mr-critical')],['Para revisar',a=>!a.classList.contains('mr-critical')&&!a.classList.contains('mr-positive')],['Señales positivas',a=>a.classList.contains('mr-positive')]]){
    const matching=alerts.filter(selector);if(!matching.length)continue;const group=document.createElement('div');group.className='finance-alert-group';
    const label=document.createElement('h4');label.textContent=title;group.append(label,...matching);panel.append(group);
   }
  }
 }
 for(const notice of shell.querySelectorAll('.mr-notice')){
  notice.classList.add('finance-banner');
  if(notice.getAttribute('role')==='alert')notice.classList.add('finance-banner--error');
  else if(mode==='management'&&!notice.closest('.mr-dialog'))notice.insertAdjacentHTML('beforeend','<p><button data-go-reports>Revisar configuración y datos pendientes ↗</button></p>');
 }
 const reportStatus=shell.querySelector('.mr-report-meta p strong');
 if(reportStatus)reportStatus.outerHTML=statusChip(reportStatus.textContent,reportStatus.textContent==='CERRADO'?'positive':'info');
 for(const empty of shell.querySelectorAll('.mr-empty'))empty.classList.add('finance-empty');
 for(const row of shell.querySelectorAll('.mr-table-wrap tbody tr')){
  if(row.querySelector('[data-report-line]'))row.classList.add('finance-report-row');
 }
}
