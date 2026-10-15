import {buildModel,aggregateMetric,change,monthsBetween} from '../reporting/engine.js';
import {isArsCurrency} from '../reporting/currency.js';
import {scoreHealth,statusScore} from './scoring.js';
import {confidenceFor} from './confidence.js';
import {buildSignals,rankPriorities} from './signals.js';
const sum=xs=>xs.reduce((n,v)=>n+v,0);
const ratio=(n,d)=>n==null||d==null||d<=0?null:n/d*100;
const median=xs=>{const a=[...xs].sort((a,b)=>a-b);return a.length?a[Math.floor(a.length/2)]:null;};
const iso=d=>d.toISOString().slice(0,10);
export function previousPeriod(from,to,mode='previous') {
 if(mode==='year') {const shift=s=>{const [y,m,d]=s.split('-').map(Number);return iso(new Date(Date.UTC(y-1,m-1,Math.min(d,new Date(Date.UTC(y-1,m,0)).getUTCDate()))));};return {from:shift(from),to:shift(to)};}
 const start=new Date(`${from}T00:00:00Z`),end=new Date(`${to}T00:00:00Z`),next=new Date(+end+86400000);
 if(from.endsWith('-01')&&next.getUTCDate()===1){const n=monthsBetween(from,to).length;return {from:iso(new Date(Date.UTC(start.getUTCFullYear(),start.getUTCMonth()-n,1))),to:iso(new Date(Date.UTC(start.getUTCFullYear(),start.getUTCMonth(),0)))};}
 return {from:iso(new Date(+start-(+end-+start+86400000))),to:iso(new Date(+start-86400000))};
}
export function healthSourceRange(from,to,compare='previous') {
 monthsBetween(from,to);const previous=previousPeriod(from,to,compare),d=new Date(`${from}T00:00:00Z`);
 const history=iso(new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()-6,1)));
 const start=previous.from<history?previous.from:history;monthsBetween(start,to);
 return {from:start,to,previous};
}
function slice(model,from,to) {
 const within=m=>m.month>=from.slice(0,7)&&m.month<=to.slice(0,7);
 return {...model,date_from:from,date_to:to,monthly:model.monthly.filter(within),groups:model.groups.filter(within),iva:model.iva.filter(within),iibb:model.iibb.filter(within)};
}
export function buildBusinessHealth(data,{from,to,compare='previous',timeline=true,compareScore=true}={}) {
 monthsBetween(from,to);
 if(data.groups.some(g=>g.organization_id&&g.organization_id!==data.organization_id))throw new Error('Fuente de otra organización.');
 const full=buildModel(data),range=previousPeriod(from,to,compare),current=slice(full,from,to),previous=slice(full,range.from,range.to);
 const next=new Date(`${to}T00:00:00Z`);next.setUTCDate(next.getUTCDate()+1);
 const partial=!from.endsWith('-01')||next.getUTCDate()!==1,fullMonth=!partial&&monthsBetween(from,to).length===1;
 // For partial ranges use server-filtered selected facts, supplied separately by the handler.
 if(data.selected){const selected=buildModel(data.selected);Object.assign(current,selected);}
 if(data.compared){Object.assign(previous,buildModel(data.compared));}
 current.iva=slice(full,from,to).iva;current.iibb=slice(full,from,to).iibb;
 previous.iva=slice(full,range.from,range.to).iva;previous.iibb=slice(full,range.from,range.to).iibb;
 const metrics=[];
 const lines=(model,code)=>model.monthly.flatMap(m=>m.lines.filter(l=>l.code===code));
 const total=(model,code)=>aggregateMetric(model,code);
 const add=(code,name,pillar,value,unit,deps,options={})=>{
  const ls=deps.flatMap(d=>lines(current,d)),prior=deps.flatMap(d=>lines(previous,d));
  const missing=[...new Set([...ls.flatMap(l=>l.missing||[]),...(options.missing||[])])];
  const exclusions=ls.flatMap(l=>l.excluded_currencies||[]),sources=ls.flatMap(l=>l.sources||[]);
  const source_count=sources.reduce((n,s)=>n+Number(s.count||0),0);
  const confidence=confidenceFor({value,missing,exclusions,source_count});
  let status=value==null?(missing.length?'INCOMPLETE':'INSUFFICIENT_DATA'):missing.length?'INCOMPLETE':options.status||'HEALTHY';
  if(value===0&&!missing.length&&ls.length&&ls.every(l=>l.status==='NO_ACTIVITY'))status='NO_ACTIVITY';
  const baseline=options.baseline??null,comparison=options.previous??null;
  const metric={code,name,pillar,value,unit,status,score:options.scorable===false||confidence==='LOW'?null:statusScore(status),
   trend:{status:comparison==null?'INSUFFICIENT_HISTORY':'AVAILABLE',change:change(value,comparison)},comparison:{value:comparison,period:range,baseline},confidence,
   explanation:missing.length?'Información incompleta; no permite una conclusión firme.':options.explanation||`Estado ${status}: evaluación determinista de ${name.toLowerCase()}. ${options.baseline!=null?`Referencia histórica: ${Math.round(options.baseline*10)/10}. `:''}Fuentes importadas; la cobertura total no está certificada.`,
   why_it_matters:options.why||'Ayuda a revisar la evolución del negocio con datos documentados.',
   recommended_actions:[{rule:`REVIEW_${code.toUpperCase()}`,text:options.action||'Revisá los registros y validá la cobertura de las importaciones.'}],
   formula:options.formula||`SUM(${deps.join(' + ')}) en ARS`,period:{from,to},source_count,exclusions,missing,
   drilldown:{sources,manual:ls.flatMap(l=>l.manual||[]),previous_sources:prior.flatMap(l=>l.sources||[]).map(s=>({...s,date_from:range.from,date_to:range.to})),historical_sources:full.monthly.filter(m=>m.month<from.slice(0,7)).slice(-6).flatMap(m=>m.lines.filter(l=>deps.includes(l.code)).flatMap(l=>l.sources||[])),rows:options.rows||[],trace_from:data.date_from,trace_to:data.date_to}};
  metrics.push(metric);return metric;
 };
 const v=code=>total(current,code).value,p=code=>total(previous,code).value;
 const history=full.monthly.filter(m=>m.month<from.slice(0,7));
 const historical=(code,n=6)=>{const rows=history.slice(-n);return rows.length===n&&rows.every(m=>m.lines.find(l=>l.code===code)?.value!=null)?rows.map(m=>m.lines.find(l=>l.code===code).value):[];};
 const sales=v('sales'),purchases=v('purchases'),result=v('result'),payroll=v('payroll');
 const salesDelta=change(sales,p('sales')),purchaseDelta=change(purchases,p('purchases'));
 const movement=(delta,upGood=true)=>delta==null?'INSUFFICIENT_DATA':(upGood?delta:-delta)<-15?'WATCH':(upGood?delta:-delta)>15?'POSITIVE_SIGNAL':'HEALTHY';
 const salesHist=historical('sales');
 const salesMetric=add('sales','Ventas netas','VENTAS',sales,'ARS_CENTS',['sales'],{previous:p('sales'),status:salesHist.length&&sales>Math.max(...salesHist)&&fullMonth?'POSITIVE_SIGNAL':movement(salesDelta),scorable:salesDelta!=null});
 salesMetric.record=Boolean(salesHist.length&&sales>Math.max(...salesHist)&&fullMonth);
 add('sales_change','Variación de ventas','VENTAS',salesDelta,'PERCENT',['sales'],{status:movement(salesDelta),formula:'(Ventas actuales − anteriores) / ABS(anteriores) × 100'});
 for(const n of [3,6]){const h=historical('sales',n);add(`sales_trend_${n}`,`Ventas frente a promedio de ${n} meses`,'VENTAS',fullMonth&&h.length?change(sales,sum(h)/n):null,'PERCENT',['sales'],{scorable:false,baseline:h.length?sum(h)/n:null,formula:`(Ventas del mes / promedio de ${n} meses anteriores − 1) × 100`});}
 const observed=current.monthly.filter(m=>m.sales!=null);
 for(const [code,name,fn] of [['best_sales','Mejor mes observado',Math.max],['worst_sales','Peor mes observado',Math.min]])add(code,name,'VENTAS',observed.length?fn(...observed.map(m=>m.sales)):null,'ARS_CENTS',['sales'],{scorable:false,rows:observed.map(m=>({month:m.month,value:m.sales}))});
 add('purchases','Compras netas','COSTOS',purchases,'ARS_CENTS',['purchases'],{previous:p('purchases'),scorable:false});
 add('purchase_change','Variación de compras','COSTOS',purchaseDelta,'PERCENT',['purchases'],{status:salesDelta!=null&&purchaseDelta>salesDelta+10?'WATCH':'HEALTHY',scorable:salesDelta!=null,formula:'(Compras actuales − anteriores) / ABS(anteriores) × 100'});
 const purchaseShare=ratio(purchases,sales),oldPurchaseShare=ratio(p('purchases'),p('sales'));
 const shareHistory=history.slice(-6).map(m=>ratio(m.purchases,m.sales));
 const shareBaseline=shareHistory.length===6&&shareHistory.every(x=>x!=null)?median(shareHistory):oldPurchaseShare;
 add('purchase_share','Compras / ventas','COSTOS',purchaseShare,'PERCENT',['purchases','sales'],{previous:oldPurchaseShare,baseline:shareBaseline,status:shareBaseline!=null&&purchaseShare>shareBaseline+10?'WATCH':'HEALTHY',scorable:shareBaseline!=null,formula:'Compras netas / ventas netas × 100'});
 add('purchase_share_change','Cambio del peso de compras','COSTOS',purchaseShare!=null&&oldPurchaseShare!=null?purchaseShare-oldPurchaseShare:null,'POINTS',['purchases','sales'],{scorable:false,formula:'Compras/ventas actual − anterior'});
 add('result','Resultado documental','RENTABILIDAD',result,'ARS_CENTS',['result'],{previous:p('result'),status:result<0?'CRITICAL':'HEALTHY',formula:'Ventas − compras − personal − cargas + otros ingresos − otros egresos',why:'Es un resultado documental antes de impuestos; no equivale al beneficio contable completo.'});
 const margin=ratio(result,sales),oldMargin=ratio(p('result'),p('sales'));
 add('margin','Margen documental','RENTABILIDAD',margin,'PERCENT',['result','sales'],{previous:oldMargin,status:margin<0?'CRITICAL':'HEALTHY',scorable:false,formula:'Resultado documental / ventas × 100'});
 add('result_change','Tendencia del resultado','RENTABILIDAD',change(result,p('result')),'PERCENT',['result'],{scorable:false,formula:'(Resultado actual − anterior) / ABS(anterior) × 100'});
 add('margin_change','Evolución del margen','RENTABILIDAD',margin!=null&&oldMargin!=null?margin-oldMargin:null,'POINTS',['result','sales'],{scorable:false,formula:'Margen actual − anterior'});
 for(const positive of [true,false])add(positive?'positive_months':'negative_months',positive?'Meses positivos':'Meses negativos','RENTABILIDAD',current.monthly.every(m=>m.result!=null)?current.monthly.filter(m=>positive?m.result>0:m.result<0).length:null,'COUNT',['result'],{scorable:false,formula:'COUNT(meses con resultado completo de signo indicado)'});
 for(const code of ['bank_flow','bank_income','bank_outflow']){const baseline=historical(code);const cv=v(code);add(code,{bank_flow:'Flujo bancario neto',bank_income:'Ingresos bancarios',bank_outflow:'Egresos bancarios'}[code],'LIQUIDEZ',cv,'ARS_CENTS',[code],{previous:p(code),baseline:baseline.length?median(baseline):null,status:code==='bank_flow'?cv<0?'WATCH':'HEALTHY':code==='bank_outflow'&&baseline.length&&cv>median(baseline)*1.3&&monthsBetween(from,to).length===1?'WATCH':'HEALTHY',scorable:code==='bank_flow'});}
 add('flow_change','Tendencia del flujo','LIQUIDEZ',change(v('bank_flow'),p('bank_flow')),'PERCENT',['bank_flow'],{scorable:false,formula:'(Flujo actual − anterior) / ABS(anterior) × 100'});
 // RPC accounts lack observation dates/tie semantics; never derive a range balance change.
 add('balance_change','Variación del saldo observado','LIQUIDEZ',null,'ARS_CENTS',[],{scorable:false,missing:['Las observaciones bancarias no permiten validar fechas y orden de los saldos.']});
 for(const code of ['payroll','employer_contributions','sac'])add(code,{payroll:'Personal bruto',employer_contributions:'Cargas patronales',sac:'SAC documentado'}[code],'PERSONAL',v(code),'ARS_CENTS',[code],{previous:p(code),scorable:false});
 add('payroll_change','Variación de personal','PERSONAL',change(payroll,p('payroll')),'PERCENT',['payroll'],{scorable:false,formula:'(Personal actual − anterior) / ABS(anterior) × 100'});
 const payrollShare=ratio(payroll,sales),oldPayrollShare=ratio(p('payroll'),p('sales'));
 const ph=history.slice(-6).map(m=>ratio(m.payroll,m.sales)),pb=ph.length===6&&ph.every(x=>x!=null)?median(ph):oldPayrollShare;
 add('payroll_share','Personal / ventas','PERSONAL',payrollShare,'PERCENT',['payroll','sales'],{previous:oldPayrollShare,baseline:pb,status:pb!=null&&payrollShare>pb+8?'WATCH':'HEALTHY',scorable:pb!=null,formula:'Personal bruto / ventas × 100',action:'Revisá la evolución de personal y ventas; este indicador no mide eficiencia de la dotación.'});
 add('employer_share','Cargas patronales / ventas','PERSONAL',ratio(v('employer_contributions'),sales),'PERCENT',['employer_contributions','sales'],{scorable:false,formula:'Cargas patronales / ventas × 100'});
 const payrollDelta=change(payroll,p('payroll'));
 add('payroll_vs_sales','Crecimiento de personal frente a ventas','PERSONAL',payrollDelta!=null&&salesDelta!=null?payrollDelta-salesDelta:null,'POINTS',['payroll','sales'],{scorable:false,formula:'Variación porcentual de personal − variación porcentual de ventas'});
 add('expense_vs_sales','Crecimiento de compras frente a ventas','COSTOS',purchaseDelta!=null&&salesDelta!=null?purchaseDelta-salesDelta:null,'POINTS',['purchases','sales'],{scorable:false,formula:'Variación porcentual de compras − variación porcentual de ventas'});
 let declining=0,negativeFlow=0;
 const completeMonths=full.monthly.filter(m=>m.month<to.slice(0,7)||m.month===to.slice(0,7)&&next.getUTCDate()===1);
 for(let i=completeMonths.length-1;i>0;i--){if(completeMonths[i].sales!=null&&completeMonths[i-1].sales!=null&&completeMonths[i].sales<completeMonths[i-1].sales)declining++;else break;}
 for(let i=completeMonths.length-1;i>=0;i--){if(completeMonths[i].bank_flow!=null&&completeMonths[i].bank_flow<0)negativeFlow++;else break;}
 add('declining_months','Meses consecutivos de caída de ventas','VENTAS',completeMonths.length>=2&&completeMonths.slice(-2).every(m=>m.sales!=null)?declining:null,'COUNT',['sales'],{scorable:false,formula:'COUNT(meses consecutivos con ventas inferiores al anterior)'});
 add('negative_flow_months','Meses consecutivos con flujo negativo','LIQUIDEZ',completeMonths.length&&completeMonths.at(-1).bank_flow!=null?negativeFlow:null,'COUNT',['bank_flow'],{scorable:false,formula:'COUNT(meses consecutivos con flujo bancario neto negativo)'});
 const purchasesRows=current.groups.filter(r=>['PURCHASES','MANUAL_PURCHASE'].includes(r.kind)&&isArsCurrency(r));
 const grouped=key=>{const map=new Map();for(const r of purchasesRows){const k=r[key]||'Sin identificar';map.set(k,(map.get(k)||0)+(r.net||0));}return [...map].map(([name,value])=>({name,value})).sort((a,b)=>b.value-a.value);};
 const suppliers=grouped('supplier'),categories=grouped('category_id');
 const trustworthy=purchasesRows.length&&purchasesRows.every(r=>r.supplier&&r.net!=null&&r.net>=0)&&purchases>0;
 for(const n of [1,3,5])add(`supplier_top${n}`,`Compras en principales ${n} proveedores`,'COSTOS',trustworthy?ratio(sum(suppliers.slice(0,n).map(r=>r.value)),purchases):null,'PERCENT',['purchases'],{scorable:false,rows:suppliers.slice(0,5),formula:`SUM(compras de top ${n}) / compras × 100`,explanation:'Concentración documental: indica dependencia potencial, no ineficiencia.'});
 add('purchase_categories','Compras por categoría','COSTOS',purchases,'ARS_CENTS',['purchases'],{scorable:false,rows:categories,formula:'SUM(compras netas ARS) GROUP BY categoría'});
 add('category_concentration','Compras en la principal categoría','COSTOS',purchasesRows.every(r=>r.category_id&&r.net!=null&&r.net>=0)&&purchases>0?ratio(categories[0]?.value,purchases):null,'PERCENT',['purchases'],{scorable:false,rows:categories.slice(0,5),formula:'Compras de principal categoría / compras × 100'});
 const salesGroups=current.groups.filter(r=>r.kind==='SALES'&&isArsCurrency(r)),activities=new Map();
 for(const r of salesGroups)activities.set(r.activity_id,(activities.get(r.activity_id)||0)+(r.net||0));
 add('sales_activities','Ventas por actividad','VENTAS',sales,'ARS_CENTS',['sales'],{scorable:false,rows:[...activities].map(([id,value])=>({name:current.activities.find(a=>a.id===id)?.name||'Sin actividad identificada',value})),formula:'SUM(ventas netas ARS) GROUP BY actividad'});
 const count=sum(purchasesRows.map(r=>r.count));
 add('unclassified_share','Compras sin clasificar','COSTOS',count?sum(purchasesRows.filter(r=>!r.category_id).map(r=>r.count))/count*100:null,'PERCENT',['purchases'],{scorable:false,formula:'Cantidad de compras sin categoría / cantidad de compras ARS × 100'});
 add('customer_concentration','Concentración de clientes','VENTAS',null,'PERCENT',[],{scorable:false,missing:['La fuente canónica no garantiza identidad de cliente.']});
 for(const [code,name,family,lineCode] of [['iva_share','IVA estimado / ventas','iva','iva_payable'],['iibb_share','IIBB estimado / ventas','iibb','iibb_payable']]){
  const months=current[family],ls=months.flatMap(m=>m.lines.filter(l=>l.code===lineCode)),missing=[...new Set(months.flatMap(m=>m.missing||[]).concat(ls.flatMap(l=>l.missing||[])))];
  if(partial)missing.push('La estimación fiscal requiere meses completos.');
  const value=!missing.length&&ls.length&&ls.every(l=>l.value!=null)?ratio(sum(ls.map(l=>l.value)),sales):null;
  const past=history.slice(-6).map(m=>{
   const tax=full[family].find(t=>t.month===m.month),taxLines=tax?.lines.filter(l=>l.code===lineCode)||[];
   return tax?.missing.length||!taxLines.length||taxLines.some(l=>l.value==null)?null:ratio(sum(taxLines.map(l=>l.value)),m.sales);
  });
  const baseline=past.length===6&&past.every(v=>v!=null)?median(past):null;
  const spike=value!=null&&baseline!=null&&value>baseline*1.3&&value>baseline+3;
  const metric=add(code,name,'FISCAL',value,'PERCENT',['sales'],{scorable:baseline!=null&&!partial,baseline,status:spike?'WATCH':'HEALTHY',missing,formula:`SUM(${lineCode}) / ventas × 100`,explanation:'La obligación fiscal no se considera mala por sí misma; se compara su proporción con seis meses completos.'});
  metric.drilldown.sources.push(...ls.flatMap(l=>l.sources||[]));metric.drilldown.manual.push(...ls.flatMap(l=>l.manual||[]));metric.source_count=metric.drilldown.sources.reduce((n,s)=>n+Number(s.count||0),0);
  metric.drilldown.historical_sources.push(...full[family].filter(t=>t.month<from.slice(0,7)).slice(-6).flatMap(t=>t.lines.filter(l=>l.code===lineCode).flatMap(l=>l.sources||[])));
 }
 const creditLines=current.iva.flatMap(m=>m.lines.filter(l=>l.code==='iva_cf'));
 const creditMissing=creditLines.flatMap(l=>l.missing||[]);
 const credit=add('iva_credits','Crédito fiscal documentado','FISCAL',!partial&&creditLines.length&&creditLines.every(l=>l.value!=null)?sum(creditLines.map(l=>l.value)):null,'ARS_CENTS',[],{scorable:false,missing:creditMissing,formula:'SUM(IVA crédito fiscal ARS de compras)'});
 credit.drilldown.sources=creditLines.flatMap(l=>l.sources||[]);credit.source_count=sum(credit.drilldown.sources.map(s=>s.count||0));credit.confidence=confidenceFor(credit);
 add('tax_configuration','Configuración fiscal pendiente','FISCAL',null,'COUNT',[],{scorable:false,missing:[...new Set([...current.iva,...current.iibb].flatMap(m=>m.missing||[]))],formula:'Limitaciones informadas por motores IVA e IIBB',explanation:'Los detalles fiscales indican configuración o información pendiente; no mide salud empresarial.'});
 add('tax_anomalies','Anomalías fiscales','FISCAL',null,'COUNT',[],{scorable:false,missing:['No hay un catálogo canónico de anomalías exclusivamente fiscales.'],formula:'No disponible; no se infieren anomalías fiscales de incidencias generales'});
 const comparableMonths=full.monthly.filter(m=>m.month<=to.slice(0,7)&&(m.month!==to.slice(0,7)||next.getUTCDate()===1));
 const health=scoreHealth(metrics),signals=buildSignals(metrics,comparableMonths),priorities=rankPriorities(signals);
 const priorHealth=compareScore?buildBusinessHealth({...data,selected:data.compared,compared:undefined},{...range,timeline:false,compareScore:false}).health:null;
 health.trend={status:health.score!=null&&priorHealth?.score!=null?'AVAILABLE':'INSUFFICIENT_HISTORY',points:health.score!=null&&priorHealth?.score!=null?health.score-priorHealth.score:null};
 for(const pillar of health.pillars){const old=priorHealth?.pillars.find(p=>p.code===pillar.code);pillar.trend={status:pillar.score!=null&&old?.score!=null?'AVAILABLE':'INSUFFICIENT_HISTORY',points:pillar.score!=null&&old?.score!=null?pillar.score-old.score:null};}
 const timelineRows=timeline?full.monthly.filter(m=>m.month<to.slice(0,7)||m.month===to.slice(0,7)&&!partial).slice(-6).map(m=>{
  const [y,mo]=m.month.split('-').map(Number),end=iso(new Date(Date.UTC(y,mo,0)));
  const h=buildBusinessHealth({...data,selected:undefined,compared:undefined},{from:`${m.month}-01`,to:end,timeline:false});
  return {period:m.month,score:h.health.score,status:h.health.status,confidence:h.health.confidence,major_signal:h.signals[0]?.code||null};
 }):[];
 return {version:'business-health-v1',organization_id:data.organization_id,input_hash:data.input_hash,period:{from,to},comparison:range,metrics,health,signals,priorities,
  positive_signals:signals.filter(s=>s.status==='POSITIVE_SIGNAL'),timeline:timelineRows,quality:{coverage:null,coverage_explanation:'La cobertura de importación total no está certificada.',confidence:health.confidence,available:metrics.filter(m=>m.value!=null&&!m.missing.length).map(m=>m.code),missing:[...new Set(metrics.flatMap(m=>m.missing))],exclusions:metrics.flatMap(m=>m.exclusions)}};
}
