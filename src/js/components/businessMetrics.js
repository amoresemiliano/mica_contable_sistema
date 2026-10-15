import {reportingService} from '../core/services/reportingService.js';
import {escapeHtml as e} from '../core/reporting/exports.js';
import {metricDetail,metricValue,statusLabel,confidenceLabel,metricSources} from './metricDetail.js';
const mounted=new WeakMap();
const views=['Salud','Rentabilidad','Liquidez','Operación','Riesgos y prioridades'];
const iso=d=>d.toISOString().slice(0,10);
export function metricsPeriod(code,today=new Date()) {
 const y=today.getFullYear(),m=today.getMonth();
 const start=code==='ytd'?new Date(Date.UTC(y,0,1)):new Date(Date.UTC(y,m-(code==='previous'?1:code==='3months'?2:code==='6months'?5:0),1));
 const end=code==='ytd'?new Date(Date.UTC(y,m,today.getDate())):new Date(Date.UTC(y,m+(code==='previous'?0:1),0));
 return {from:iso(start),to:iso(end)};
}
const signalsHtml=signals=>signals.length?signals.map(s=>`<article class="metric-card ${s.status}"><strong>${e(s.explanation)}</strong><p>Confianza: ${e(confidenceLabel(s.confidence))}</p>${s.recommended_actions.map(a=>`<p>${e(a.text)}</p>`).join('')}<small>Regla: ${e(s.code)} · indicadores: ${e(s.metric_codes.join(', '))}</small></article>`).join(''):'<p>No hay señales con evidencia suficiente para este período.</p>';
export function createMetricsController({store,root,service=reportingService}) {
 const state={...metricsPeriod('month'),view:'Salud',compare:'previous',health:null,busy:false,error:'',org:null,generation:null,sequence:0};
 const can=()=>store.contextState==='TENANT_READY'&&store.hasCapability('REPORT_VIEW',{scope:'ORGANIZATION',orgId:store.activeOrganizationId});
 const context=()=>`${store.activeOrganizationId}:${store.contextGeneration}`;
 const render=()=>{
  if(!can()){root.innerHTML='<p>Seleccioná una empresa con acceso a reportes para ver Métricas.</p>';return;}
  const h=state.health;
  root.innerHTML=`<div class="business-metrics"><h1>Métricas</h1><p>Cómo está tu negocio, qué cambió y qué conviene revisar.</p><div class="metrics-controls"><label>Desde<input name="from" type="date" value="${e(state.from)}"></label><label>Hasta<input name="to" type="date" value="${e(state.to)}"></label><label>Período<select name="quick"><option value="">Personalizado</option><option value="month">Mes actual</option><option value="previous">Mes anterior</option><option value="3months">Últimos 3 meses</option><option value="6months">Últimos 6 meses</option><option value="ytd">Año hasta hoy</option></select></label><label>Comparación<select name="compare"><option value="previous" ${state.compare==='previous'?'selected':''}>Período anterior equivalente</option><option value="year" ${state.compare==='year'?'selected':''}>Año anterior</option></select></label><button data-load ${state.busy?'disabled':''}>Actualizar</button></div><nav aria-label="Vistas de Métricas">${views.map(v=>`<button data-view="${e(v)}" aria-pressed="${state.view===v}">${e(v)}</button>`).join('')}</nav><p role="status">${state.busy?'Evaluando fuentes documentales…':e(state.error)}</p>${h?content(h):''}</div>`;
  const controls=root.querySelector('.metrics-controls');
  if(controls){const disclosure=document.createElement('details'),summary=document.createElement('summary');summary.textContent=`Período: ${state.from} — ${state.to} · Cambiar`;controls.replaceWith(disclosure);disclosure.append(summary,controls);}
  if(h&&state.view==='Salud'){
   const trend=t=>t?.status==='AVAILABLE'?`${t.points>0?'+':''}${t.points} puntos frente al período anterior`:'Sin historia suficiente para comparar el puntaje';
   root.querySelector('.metric-hero')?.insertAdjacentHTML('beforeend',`<p>${e(trend(h.health.trend))}</p>`);
   root.querySelectorAll('.metrics-grid .metric-card').forEach((card,i)=>card.insertAdjacentHTML('beforeend',`<p>${e(trend(h.health.pillars[i]?.trend))}</p>`));
  }
 };
 function content(h) {
  const health=h.health;
  const cards=metrics=>`<div class="metrics-grid">${metrics.map(m=>`<article class="metric-card ${m.status}"><h3>${e(m.name)}</h3><strong class="metric-number">${e(metricValue(m))}</strong><p>${e(statusLabel(m.status))} · Confianza ${e(confidenceLabel(m.confidence))}</p>${metricDetail(m)}</article>`).join('')}</div>`;
  if(state.view==='Salud')return `<section class="metric-hero"><h2>Índice de salud empresarial</h2><strong>${health.score==null?'Sin índice global':`${health.score} / 100`}</strong><p>${e(statusLabel(health.status))} · Confianza: ${e(confidenceLabel(health.confidence))}</p><p>Evaluado: ${e(h.period.from)} — ${e(h.period.to)}</p><p>${e(health.explanation)}</p><details><summary>¿Por qué este puntaje?</summary><p>No se redistribuyen pesos. Los pilares ausentes no valen cero.</p>${health.pillars.map(p=>`<p>${e(p.code)}: ${p.score??'No determinable'} · peso ${p.weight}% · contribución ${p.contribution==null?'No disponible':Math.round(p.contribution*10)/10} · indicadores ${e(p.metric_codes.join(', '))}</p>`).join('')}</details></section><h2>Pilares</h2><div class="metrics-grid">${health.pillars.map(p=>`<article class="metric-card"><h3>${e(p.code)}</h3><strong>${p.score??'No determinable'}</strong><p>${e(statusLabel(p.status))} · Confianza ${e(confidenceLabel(p.confidence))}</p><button data-pillar="${e(p.code)}">Ver indicadores</button></article>`).join('')}</div><h2>Hoy deberías mirar</h2>${signalsHtml(h.priorities.slice(0,3))}<h2>Prioridades de acción</h2>${signalsHtml(h.priorities)}<h2>Señales positivas</h2>${signalsHtml(h.positive_signals)}<h2>Evolución mensual</h2><div class="metrics-timeline">${h.timeline.map(t=>`<article><strong>${e(t.period)}</strong><p>${t.score??'Sin índice'} · ${e(statusLabel(t.status))}</p><p>Confianza ${e(confidenceLabel(t.confidence))}</p><small>${e(t.major_signal||'Sin señal concluyente')}</small></article>`).join('')}</div><h2>Calidad del diagnóstico</h2><p>${e(h.quality.coverage_explanation)}</p><p>Indicadores disponibles: ${h.quality.available.length}. Confianza: ${e(confidenceLabel(h.quality.confidence))}.</p>${h.quality.missing.map(x=>`<p class="metric-warning">${e(x)}</p>`).join('')}`;
  if(state.view==='Riesgos y prioridades')return `<h2>Prioridades de acción</h2>${signalsHtml(h.priorities)}<h2>Señales</h2>${signalsHtml(h.signals)}${cards(h.metrics.filter(m=>m.missing.length))}`;
  const pillars=state.view==='Rentabilidad'?['RENTABILIDAD','COSTOS']:state.view==='Liquidez'?['LIQUIDEZ']:['VENTAS','COSTOS','FISCAL','PERSONAL'];
  return cards(h.metrics.filter(m=>pillars.includes(m.pillar)));
 }
 async function load() {
  const sequence=++state.sequence;state.health=null;state.org=store.activeOrganizationId;state.generation=store.contextGeneration;
  if(!can()){render();return;}const key=context();state.busy=true;state.error='';render();
  try{const result=await service.request({action:'health',organization_id:state.org,from:state.from,to:state.to,compare:state.compare});
   if(sequence!==state.sequence||key!==context()||!can())return;
   if(result.health?.organization_id!==state.org)throw new Error('La empresa cambió. Actualizá el diagnóstico.');state.health=result.health;
  }catch{if(sequence===state.sequence&&key===context())state.error='No se pudo evaluar el diagnóstico. Revisá el período y volvé a intentar.';}
  finally{if(sequence===state.sequence){state.busy=false;render();}}
 }
 root.onchange=event=>{const {name,value}=event.target;if(name==='quick'){if(value)Object.assign(state,metricsPeriod(value));}else if(['from','to','compare'].includes(name))state[name]=value;else return;void load();};
 root.onclick=async event=>{
  const button=event.target.closest('button');if(!button)return;
  if(button.hasAttribute('data-load'))return void load();
  if(button.dataset.view){state.view=button.dataset.view;render();return;}
  if(button.dataset.pillar){state.view=button.dataset.pillar==='RENTABILIDAD'?'Rentabilidad':button.dataset.pillar==='LIQUIDEZ'?'Liquidez':'Operación';render();return;}
  if(button.dataset.source!=null&&state.health&&can()){
   const key=context(),seq=state.sequence,m=state.health.metrics.find(m=>m.code===button.dataset.metric),s=m?metricSources(m)[Number(button.dataset.source)]:null;if(!s?.filter)return;
   const target=root.querySelector(`[data-transactions="${m.code}"]`);button.disabled=true;
   const offset=Number(button.dataset.offset)||0;
   try{const detail=await service.detail(state.org,s.date_from||m.period.from,s.date_to||m.period.to,s.filter,offset);
    if(key!==context()||seq!==state.sequence||!can())return;
    const pageButton=(label,next)=>`<button type="button" data-metric="${e(m.code)}" data-source="${e(button.dataset.source)}" data-offset="${next}">${label}</button>`;
    target.innerHTML=`<p>Registros ${detail.rows.length?offset+1:0}–${offset+detail.rows.length} de ${detail.total??detail.rows.length}</p>`+detail.rows.map(r=>`<article><strong>${e(r.supplier||'Registro de origen')}</strong><p>${e(r.day||'Fecha no disponible')} · ${e(r.kind||'')}</p><p>Importe de origen: ${e(r.amount??'No disponible')} ${e(r.currency||'')}</p><small>Referencia: ${e(r.id)}</small></article>`).join('')+(offset>0?pageButton('Anteriores',Math.max(0,offset-100)):'')+(offset+detail.rows.length<detail.total?pageButton('Siguientes',offset+100):'');
   }catch{if(key===context()&&seq===state.sequence)target.textContent='No se pudo abrir el detalle.';}finally{button.disabled=false;}
  }
 };
 const unsubscribe=store.subscribe?.(()=>{if(state.org!==store.activeOrganizationId||state.generation!==store.contextGeneration||!can()){++state.sequence;state.health=null;state.org=null;state.busy=false;render();}});
 return {state,load,ensure(){if(state.org!==store.activeOrganizationId||state.generation!==store.contextGeneration)void load();else render();},destroy(){++state.sequence;unsubscribe?.();root.onclick=null;root.onchange=null;root.innerHTML='';}};
}
export function mountBusinessMetrics(store,{refresh=false}={}) {
 const root=document.getElementById('business-metrics-root');if(!root)return;
 let controller=mounted.get(root);if(!controller){controller=createMetricsController({store,root});mounted.set(root,controller);}
 if(refresh)void controller.load();else controller.ensure();
}
