import {reportingData} from './fixtures/reporting.js';
import {buildBusinessHealth,healthSourceRange,previousPeriod} from '../src/js/core/metrics/engine.js';
import {scoreHealth} from '../src/js/core/metrics/scoring.js';
import {createReportingHandler} from '../src/js/core/reporting/server.js';
import {SIGNAL_CATALOG,rankPriorities} from '../src/js/core/metrics/signals.js';
const options={from:'2026-09-01',to:'2026-09-30'};
function fixture(){
 const base=reportingData(),groups=[],inputs=[];
 for(let i=2;i<=9;i++){const month=`2026-${String(i).padStart(2,'0')}`;
  groups.push(...base.groups.map(g=>({...g,month})));
  inputs.push(...base.inputs.filter(i=>i.kind==='PERIOD_ADJUSTMENT').map(i=>({...i,period:month,id:`adjust-${month}`,payload:{...i.payload,iva_compensation:0}})));
 }
 inputs.push(...base.inputs.filter(i=>i.kind==='IIBB_CONFIG'),{...base.inputs.find(i=>i.kind==='IVA_OPENING'),period:'2026-02'});
 return {...base,groups,inputs,date_from:'2026-02-01'};
}
const evaluate=(data=fixture(),opts=options)=>buildBusinessHealth(data,opts);
const metric=(h,c)=>h.metrics.find(m=>m.code===c);
const modify=(d,month,kind,values)=>Object.assign(d.groups.find(g=>g.month===month&&g.kind===kind),values);
test('complete organization has deterministic score and explicit weighted contributions',()=>{
 const h=evaluate();expect(h.health.score).toBe(85);expect(h.health.pillars.map(p=>p.weight)).toEqual([25,20,15,15,15,10]);expect(evaluate()).toEqual(h);
 expect(h.metrics.length).toBeGreaterThan(30);expect(h.health.pillars.every(p=>p.score!=null)).toBe(true);
});
test('declining sales and rising purchases deduplicate related signals',()=>{
 const d=fixture();modify(d,'2026-09','SALES',{net:600000});modify(d,'2026-09','PURCHASES',{net:400000});const h=evaluate(d);
 expect(metric(h,'sales_change').status).toBe('WATCH');expect(h.signals.some(s=>s.code==='SALES_DOWN_COSTS_UP')).toBe(true);expect(h.signals.some(s=>s.code==='EXPENSES_GROW_FASTER_THAN_SALES')).toBe(false);
});
test('complete negative result is critical; recovery produces positives',()=>{
 const d=fixture();modify(d,'2026-08','PURCHASES',{net:1000000});modify(d,'2026-09','PURCHASES',{net:1100000});const h=evaluate(d);
 expect(metric(h,'result').status).toBe('CRITICAL');expect(h.signals.some(s=>s.code==='TWO_NEGATIVE_RESULT_MONTHS')).toBe(true);
 modify(d,'2026-09','PURCHASES',{net:100000});expect(evaluate(d).positive_signals.some(s=>s.code==='IMPROVING_MARGIN')).toBe(true);
});
test('payroll grows faster than flat sales',()=>{const d=fixture();modify(d,'2026-09','PAYROLL',{net:300000});const h=evaluate(d);expect(h.signals.some(s=>s.code==='SALES_FLAT_PAYROLL_UP')).toBe(true);expect(metric(h,'payroll_share').status).toBe('WATCH');});
test('recurring bank outflow and result divergence are traceable',()=>{const d=fixture();for(const m of ['2026-08','2026-09'])modify(d,m,'BANK',{amount:-200000});const h=evaluate(d);expect(h.signals.map(s=>s.code)).toEqual(expect.arrayContaining(['RECURRING_NEGATIVE_FLOW','NEGATIVE_FLOW_WITH_PROFIT']));});
test('four USD purchases exclude profitability without poisoning unrelated bank and sales',()=>{
 const d=fixture();d.groups.push({...d.groups.find(g=>g.kind==='PURCHASES'),month:'2026-09',currency:'USD',count:4});const h=evaluate(d);
 expect(metric(h,'result').value).toBeNull();expect(metric(h,'purchases').exclusions[0].record_count).toBe(4);expect(metric(h,'bank_flow').value).toBe(300000);expect(metric(h,'sales').value).toBe(900000);expect(h.health.score).toBeNull();
});
test.each(['employer','iibb','iva','bank','payroll'])('missing %s does not invent zero or suppress unrelated sales',kind=>{
 const d=fixture();let code;
 if(kind==='employer'){d.inputs.filter(i=>i.kind==='PERIOD_ADJUSTMENT').forEach(i=>delete i.payload.employer_contributions);code='result';}
 if(kind==='iibb'){d.inputs=d.inputs.filter(i=>i.kind!=='IIBB_CONFIG');code='iibb_share';}
 if(kind==='iva'){d.inputs=d.inputs.filter(i=>i.kind!=='IVA_OPENING');code='iva_share';}
 if(kind==='bank'){d.groups=d.groups.filter(g=>g.kind!=='BANK');code='bank_flow';}
 if(kind==='payroll'){d.groups=d.groups.filter(g=>g.kind!=='PAYROLL');code='payroll';}
 const h=evaluate(d);expect(metric(h,code).value).toBeNull();expect(metric(h,code).confidence).toBe('UNAVAILABLE');expect(metric(h,'sales').value).toBe(900000);
});
test('low classification and supplier dependency are separate from health penalties',()=>{const d=fixture();d.groups.filter(g=>g.kind==='PURCHASES').forEach(g=>g.category_id=null);const h=evaluate(d);expect(h.signals.map(s=>s.code)).toEqual(expect.arrayContaining(['LOW_CLASSIFICATION_COVERAGE','HIGH_SUPPLIER_CONCENTRATION']));expect(metric(h,'unclassified_share').score).toBeNull();});
test('unknown clients are unavailable; no false concentration',()=>{const h=evaluate();expect(metric(h,'customer_concentration').value).toBeNull();expect(h.signals.some(s=>s.code==='HIGH_CUSTOMER_CONCENTRATION')).toBe(false);});
test('insufficient history produces no percentage or record claim',()=>{const h=evaluate(reportingData());expect(metric(h,'sales_change').value).toBeNull();expect(metric(h,'sales_trend_6').trend.status).toBe('INSUFFICIENT_HISTORY');expect(h.positive_signals.some(s=>s.code==='RECORD_SALES')).toBe(false);});
test('zero differs from missing and zero denominator produces null',()=>{const d=fixture();modify(d,'2026-09','BANK',{amount:0});modify(d,'2026-09','SALES',{net:0});const h=evaluate(d);expect(metric(h,'bank_flow').value).toBe(0);expect(metric(h,'bank_flow').confidence).toBe('MEDIUM');expect(metric(h,'purchase_share').value).toBeNull();});
test('no activity month preserves documentary scope',()=>{const d=fixture();d.groups=d.groups.filter(g=>g.month!=='2026-09');d.inputs=d.inputs.filter(i=>i.period!=='2026-09');const h=evaluate(d);expect(metric(h,'sales').value).toBe(0);expect(metric(h,'sales').status).toBe('NO_ACTIVITY');expect(h.health.score).toBeNull();});
test('positive record and cost control require comparable history',()=>{const d=fixture();modify(d,'2026-09','SALES',{net:1300000});modify(d,'2026-09','PURCHASES',{net:100000});const h=evaluate(d);expect(h.positive_signals.map(s=>s.code)).toEqual(expect.arrayContaining(['RECORD_SALES','COST_CONTROL_IMPROVING']));});
test('missing pillar is never zero or redistributed',()=>{const h=scoreHealth([{pillar:'VENTAS',code:'sales',score:85,confidence:'MEDIUM',missing:[]}]);expect(h.score).toBeNull();expect(h.pillars.find(p=>p.code==='LIQUIDEZ').score).toBeNull();expect(h.pillars.find(p=>p.code==='VENTAS').weight).toBe(15);});
test('priorities max five and all recommendations reference deterministic rules',()=>{const h=evaluate();expect(rankPriorities(Object.keys(SIGNAL_CATALOG).map(code=>({code,status:'WATCH',severity:2,persistence:1,actionability:1,confidence:'MEDIUM',financial_relevance:1})))).toHaveLength(5);for(const s of h.signals)expect(s.recommended_actions[0].rule).toBe(s.code);});
test('drilldown agrees with canonical amount, source count and filters',()=>{const m=metric(evaluate(),'sales');expect(m.value).toBe(900000);expect(m.source_count).toBe(2);expect(m.drilldown.sources[0].filter).toMatchObject({month:'2026-09',kind:'SALES'});});
test('timeline never calculates from future months',()=>{const d=fixture();const before=evaluate(d).timeline;modify(d,'2026-09','SALES',{net:9999999});const after=evaluate(d).timeline;expect(before.slice(0,-1)).toEqual(after.slice(0,-1));});
test('foreign tenant source and manual inputs are rejected',()=>{const d=fixture();d.groups[0].organization_id='other';expect(()=>evaluate(d)).toThrow('otra organización');delete d.groups[0].organization_id;d.inputs[0].organization_id='other';expect(()=>evaluate(d)).toThrow('otra organización');});
test('partial periods withhold fiscal estimates',()=>{const h=evaluate(fixture(),{from:'2026-09-05',to:'2026-09-20'});expect(metric(h,'iva_share').value).toBeNull();});
test('outflow spike uses six-month company history',()=>{const d=fixture();modify(d,'2026-09','BANK',{outflow:600000});expect(evaluate(d).signals.some(s=>s.code==='BANK_OUTFLOW_SPIKE')).toBe(true);});
test('three consecutive declines require four valid months',()=>{const d=fixture();for(const [month,net] of [['2026-06',900000],['2026-07',800000],['2026-08',700000],['2026-09',600000]])modify(d,month,'SALES',{net});const h=evaluate(d);expect(metric(h,'declining_months').value).toBe(3);expect(h.signals.some(s=>s.code==='THREE_MONTH_SALES_DECLINE')).toBe(true);});
test('unsupported optional metrics do not create a critical-data priority',()=>{expect(evaluate().signals.some(s=>s.code==='MISSING_CRITICAL_DATA')).toBe(false);});
test('fiscal obligations are not scored bad just for being positive',()=>{const h=evaluate();expect(metric(h,'iva_share').value).toBeGreaterThan(0);expect(metric(h,'iva_share').status).toBe('HEALTHY');});
test('isolated negative result and sales decline have actionable rules',()=>{const d=fixture();modify(d,'2026-09','SALES',{net:600000});modify(d,'2026-09','PURCHASES',{net:700000});const h=evaluate(d);expect(h.signals.some(s=>s.code==='NEGATIVE_RESULT')).toBe(true);modify(d,'2026-09','PURCHASES',{net:200000});expect(evaluate(d).signals.some(s=>s.code==='SALES_DECLINE')).toBe(true);});
test('payroll pressure with growing sales is not overlooked',()=>{const d=fixture();modify(d,'2026-09','SALES',{net:1000000});modify(d,'2026-09','PAYROLL',{net:300000});expect(evaluate(d).signals.some(s=>s.code==='PAYROLL_PRESSURE')).toBe(true);});
test('bank recovery is a positive signal',()=>{const d=fixture();modify(d,'2026-08','BANK',{amount:-10000});expect(evaluate(d).positive_signals.some(s=>s.code==='BANK_FLOW_RECOVERY')).toBe(true);});
test('partial current month cannot produce a monthly record or monthly average trend',()=>{const d=fixture();modify(d,'2026-09','SALES',{net:9999999});const h=evaluate(d,{from:'2026-09-05',to:'2026-09-20'});expect(h.positive_signals.some(s=>s.code==='RECORD_SALES')).toBe(false);expect(metric(h,'sales_trend_6').value).toBeNull();expect(h.timeline.at(-1).period).toBe('2026-08');});
test('growth above fifteen percent alone is not a record',()=>{const d=fixture();modify(d,'2026-03','SALES',{net:2000000});modify(d,'2026-09','SALES',{net:1200000});expect(evaluate(d).positive_signals.some(s=>s.code==='RECORD_SALES')).toBe(false);});
test('equivalent periods and history bounds are deterministic',()=>{expect(previousPeriod('2026-09-01','2026-09-30')).toEqual({from:'2026-08-01',to:'2026-08-31'});expect(previousPeriod('2024-02-29','2024-02-29','year').from).toBe('2023-02-28');expect(healthSourceRange(options.from,options.to).from).toBe('2026-03-01');});
test('server ignores submitted scores and enforces org, capability and JWT',async()=>{
 const d=fixture();let deny=false;
 const handler=createReportingHandler({authenticate:async token=>token==='valid'?{id:'user'}:null,userClient:()=>({rpc:async(name,args)=>name==='get_my_operational_context'?{data:{organization_id:d.organization_id}}:deny?{error:{message:'denied'}}:{data:{...d,date_from:args.p_from,date_to:args.p_to,groups:d.groups.filter(g=>g.month>=args.p_from.slice(0,7)&&g.month<=args.p_to.slice(0,7))}}}),serviceClient:{rpc:()=>{throw Error('No writes');}}});
 const call=(body={},token='valid')=>handler(new Request('http://local',{method:'POST',headers:{authorization:`Bearer ${token}`},body:JSON.stringify({action:'health',organization_id:d.organization_id,...options,score:100,...body})}));
 const response=await call();expect(response.status).toBe(200);expect((await response.json()).health.health.score).not.toBe(100);expect((await call({organization_id:'other'})).status).toBe(400);expect((await call({},'invalid')).status).toBe(401);deny=true;expect((await call()).status).toBe(400);
});
