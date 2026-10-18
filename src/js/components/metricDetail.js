import {escapeHtml as e,formatMoney} from '../core/reporting/exports.js';
export const metricValue=m=>m.value==null?'No determinable':m.unit==='ARS_CENTS'?formatMoney(m.value):`${Math.round(m.value*10)/10}${m.unit==='PERCENT'?'%':m.unit==='POINTS'?' puntos':''}`;
export const statusLabel=s=>({HEALTHY:'Estable',WATCH:'Atención',CRITICAL:'Crítico',POSITIVE_SIGNAL:'Señal positiva',NO_ACTIVITY:'Sin actividad documentada',INSUFFICIENT_DATA:'Datos insuficientes',INCOMPLETE:'Información incompleta',GREEN:'Verde',YELLOW:'Amarillo',RED:'Rojo'})[s]||s;
export const confidenceLabel=s=>({HIGH:'Alta',MEDIUM:'Media',LOW:'Baja',UNAVAILABLE:'No disponible'})[s];
export const metricSources=m=>[...m.drilldown.sources,...m.drilldown.previous_sources,...m.drilldown.historical_sources.map(s=>({...s,date_from:m.drilldown.trace_from,date_to:m.drilldown.trace_to}))];
export function metricDetail(m) {
 return `<details class="metric-detail"><summary>Ver detalle: ${e(m.name)}</summary><p>${e(m.explanation)}</p><p><strong>Por qué importa:</strong> ${e(m.why_it_matters)}</p><dl><dt>Fórmula</dt><dd>${e(m.formula)}</dd><dt>Período</dt><dd>${e(m.period.from)} — ${e(m.period.to)}</dd><dt>Actual</dt><dd>${e(metricValue(m))}</dd><dt>Anterior</dt><dd>${e(metricValue({...m,value:m.comparison.value}))}</dd><dt>Referencia histórica</dt><dd>${e(metricValue({...m,value:m.comparison.baseline}))}</dd><dt>Registros de origen (referencias, pueden repetirse)</dt><dd>${m.source_count}</dd><dt>Estado y confianza</dt><dd>${e(statusLabel(m.status))} · ${e(confidenceLabel(m.confidence))}</dd><dt>Puntaje</dt><dd>${m.score??'No participa'} · regla business-health-v1</dd></dl>
 ${m.missing.map(x=>`<p class="metric-warning">${e(x)}</p>`).join('')}${m.exclusions.map(x=>`<p>Exclusión: ${e(JSON.stringify(x))}</p>`).join('')}
 ${m.recommended_actions.map(a=>`<p>${e(a.text)} <small>Regla: ${e(a.rule)}</small></p>`).join('')}
 ${m.drilldown.rows.map(r=>`<p>${e(r.name||r.month)}: ${e(metricValue({...m,value:r.value,unit:'ARS_CENTS'}))}</p>`).join('')}
 ${m.drilldown.manual.map(r=>`<p>Ajuste ${e(r.kind)} · ${e(r.period)} · ${e(r.note||'')} · revisión ${e(r.revision)}</p>`).join('')}
 ${metricSources(m).map((s,i)=>`<button type="button" data-source="${i}" data-metric="${e(m.code)}">Ver registros ${e(s.filter?.month||'')} · ${e(s.source_type)} (${s.count})</button>`).join('')}
 <div data-transactions="${e(m.code)}" aria-live="polite"></div></details>`;
}
