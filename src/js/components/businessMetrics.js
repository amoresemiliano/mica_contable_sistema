import {reportingService} from '../core/services/reportingService.js';
import {escapeHtml as e} from '../core/reporting/exports.js';
import {financeHeader} from './financeUi.js';
import {renderMetricsView} from './metricOverview.js';
import {metricSources} from './metricDetail.js';
const mounted=new WeakMap();
const views=['Salud','Rentabilidad','Liquidez','Operación','Riesgos y prioridades'];
const iso=d=>d.toISOString().slice(0,10);
export function metricsPeriod(code,today=new Date()) {
 const y=today.getFullYear(),m=today.getMonth();
 const start=code==='ytd'?new Date(Date.UTC(y,0,1)):new Date(Date.UTC(y,m-(code==='previous'?1:code==='3months'?2:code==='6months'?5:0),1));
 const end=code==='ytd'?new Date(Date.UTC(y,m,today.getDate())):new Date(Date.UTC(y,m+(code==='previous'?0:1),0));
 return {from:iso(start),to:iso(end)};
}
export function createMetricsController({store,root,service=reportingService}) {
 const state={...metricsPeriod('month'),view:'Salud',compare:'previous',health:null,busy:false,error:'',org:null,generation:null,sequence:0};
 const can=()=>store.contextState==='TENANT_READY'&&store.hasCapability('REPORT_VIEW',{scope:'ORGANIZATION',orgId:store.activeOrganizationId});
 const context=()=>`${store.activeOrganizationId}:${store.contextGeneration}`;
 const render=()=>{
  if(!can()){root.innerHTML='<p>Seleccioná una empresa con acceso a reportes para ver Métricas.</p>';return;}
  const h=state.health;
  root.innerHTML=`<div class="business-metrics">${financeHeader('Métricas','Entendé la salud de tu negocio y enfocá tu próxima decisión.','MICA · Inteligencia del negocio')}<div class="metrics-controls"><label>Desde<input name="from" type="date" value="${e(state.from)}"></label><label>Hasta<input name="to" type="date" value="${e(state.to)}"></label><label>Período<select name="quick"><option value="">Personalizado</option><option value="month">Mes actual</option><option value="previous">Mes anterior</option><option value="3months">Últimos 3 meses</option><option value="6months">Últimos 6 meses</option><option value="ytd">Año hasta hoy</option></select></label><label>Comparación<select name="compare"><option value="previous" ${state.compare==='previous'?'selected':''}>Período anterior equivalente</option><option value="year" ${state.compare==='year'?'selected':''}>Año anterior</option></select></label><button data-load ${state.busy?'disabled':''}>Actualizar</button></div><nav aria-label="Vistas de Métricas">${views.map(v=>`<button data-view="${e(v)}" aria-pressed="${state.view===v}">${e(v)}</button>`).join('')}</nav><p role="status">${state.busy?'Evaluando fuentes documentales…':e(state.error)}</p>${h?renderMetricsView(h,state.view):''}</div>`;
  const controls=root.querySelector('.metrics-controls');
  if(controls){const disclosure=document.createElement('details'),summary=document.createElement('summary');summary.textContent=`Período: ${state.from} — ${state.to} · Cambiar`;controls.replaceWith(disclosure);disclosure.append(summary,controls);}
 };
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
