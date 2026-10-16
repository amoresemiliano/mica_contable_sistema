import {escapeHtml as e,formatMoney} from '../core/reporting/exports.js';
export function lineChart(series,label,{compact=false}={}) {
 const valid=series.filter(r=>r.value!=null);if(!valid.length)return '<p class="mr-empty">No hay datos suficientes para calcular este indicador.</p>';
 const width=600,height=compact?56:220,pad=compact?4:46,values=valid.map(r=>r.value),min=Math.min(0,...values),max=Math.max(0,...values),span=max-min||1;
 const x=i=>pad+i*(width-2*pad)/Math.max(1,series.length-1),y=v=>height-pad-(v-min)/span*(height-2*pad);
 let path='',started=false;series.forEach((r,i)=>{if(r.value==null){started=false;return;}path+=`${started?'L':'M'}${x(i).toFixed(2)},${y(r.value).toFixed(2)} `;started=true;});
 const axisValue=v=>new Intl.NumberFormat('es-AR',{notation:'compact',maximumFractionDigits:1}).format(v/100);
 const axes=compact?'':`<g fill="#596d7d" font-size="10"><text x="${pad}" y="14">ARS</text><text x="${pad-8}" y="${y(max)+4}" text-anchor="end">${e(axisValue(max))}</text>${min!==max?`<text x="${pad-8}" y="${y(min)+4}" text-anchor="end">${e(axisValue(min))}</text>`:''}<text x="${pad}" y="${height-10}">${e(series[0]?.label||'')}</text>${series.length>1?`<text x="${width-pad}" y="${height-10}" text-anchor="end">${e(series.at(-1)?.label||'')}</text>`:''}</g>`;
 return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${e(label)}" class="${compact?'mr-spark':'mr-chart'}"><title>${e(label)}</title>${axes}<line x1="${pad}" y1="${y(0)}" x2="${width-pad}" y2="${y(0)}" stroke="#cbd5e1"/><path d="${path}" fill="none" stroke="#237c91" stroke-width="${compact?3:2.5}"/>${series.map((r,i)=>r.value==null?'':`<circle cx="${x(i)}" cy="${y(r.value)}" r="${compact?2:4}" fill="#237c91"><title>${e(r.label)}: ${e(formatMoney(r.value))}</title></circle>`).join('')}</svg>${compact?'':`<details><summary>Ver datos del gráfico</summary><table><tbody>${series.map(r=>`<tr><th>${e(r.label)}</th><td>${formatMoney(r.value)}</td></tr>`).join('')}</tbody></table></details>`}`;
}
export function bars(rows,label) {
 const max=Math.max(1,...rows.map(r=>Math.abs(r.value??0)));
 return `<div role="group" aria-label="${e(label)}" class="mr-bars">${rows.map(r=>`<button type="button" data-trace="${e(r.trace||r.code||'')}" class="mr-bar-row"><span>${e(r.label)}</span><span class="mr-bar-track"><i style="width:${Math.min(100,Math.abs(r.value??0)/max*100)}%;background:${r.value<0?'#b85b55':'#237c91'}"></i></span><strong>${formatMoney(r.value)}</strong></button>`).join('')||'<p class="mr-empty">No hay datos disponibles.</p>'}</div>`;
}
export function waterfall(rows) {
 let running=0;const steps=rows.map(r=>{const start=running;running+=r.value??0;return {...r,start,end:running};});
 const low=Math.min(0,...steps.flatMap(s=>[s.start,s.end])),high=Math.max(1,...steps.flatMap(s=>[s.start,s.end])),scale=v=>180-(v-low)/(high-low)*145;
 return `<svg viewBox="0 0 700 230" class="mr-chart" role="img" aria-label="Puente del resultado documental"><title>Ventas menos compras, personal, cargas y otros egresos; más otros ingresos</title>${steps.map((s,i)=>`<g><rect x="${20+i*96}" y="${Math.min(scale(s.start),scale(s.end))}" width="65" height="${Math.max(2,Math.abs(scale(s.start)-scale(s.end)))}" fill="${s.value<0?'#b85b55':'#237c91'}"><title>${e(s.label)}: ${e(formatMoney(s.value))}; acumulado ${e(formatMoney(s.end))}</title></rect><text x="${20+i*96}" y="205" font-size="11">${e(s.label)}</text></g>`).join('')}</svg><p class="mr-caption">Resultado: ${formatMoney(running)} · importes documentales antes de impuesto.</p>`;
}
