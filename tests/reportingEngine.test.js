import {buildModel,buildReport,validateInput,ivaEngine,iibbEngine,annualEngine,alertEngine,change,monthsBetween,ALERT_DEFAULTS} from '../src/js/core/reporting/engine.js';
import {reportingData} from './fixtures/reporting.js';
const get=(lines,code)=>lines.find(l=>l.code===code);

test('signed credit note reduces sales; payroll, category purchases and manual adjustments form one result',()=>{
 const model=buildModel(reportingData()),m=model.monthly[0];
 expect(m.sales).toBe(900000);expect(get(m.lines,'gross_sales').value).toBe(1000000);expect(get(m.lines,'credit_notes').value).toBe(-121000);
 expect(m.result).toBe(575000);expect(m.purchases).toBe(200000);expect(m.payroll).toBe(100000);expect(m.bank_flow).toBe(300000);
 expect(get(m.lines,'result').manual[0].user).toBe('accountant');expect(get(m.lines,'purchases').sources[0].filter.category_id).toBe('office');
});
test('monthly plus cumulative report uses the same canonical lines; bank cash is never sales',()=>{
 const data=reportingData();data.date_to='2026-10-31';data.groups.push(...data.groups.map(r=>({...r,month:'2026-10'})));data.inputs.push({...data.inputs[1],period:'2026-10'});
 const model=buildModel(data),report=buildReport(model,'RESULTADOS');
 expect(report.rows.filter(r=>r.code==='result').reduce((n,r)=>n+r.value,0)).toBe(1150000);expect(report.rows.filter(r=>r.code==='sales').reduce((n,r)=>n+r.value,0)).toBe(1800000);
 expect(report.status).toBe('BORRADOR');
});
test('missing data, manual invoice without VAT and foreign currencies remain unavailable',()=>{
 const empty=buildModel(reportingData({groups:[]}));expect(empty.monthly[0].sales).toBeNull();
 const data=reportingData();data.groups[0].currency='DOL';expect(buildModel(data).monthly[0].sales).toBeNull();
 const manual=reportingData();manual.groups.push({...manual.groups[1],kind:'MANUAL_PURCHASE',net:null,vat:null,missing_net:1,missing_vat:1});expect(buildModel(manual).iva[0].payable).toBeNull();expect(buildModel(manual).monthly[0].result).toBeNull();
});
test('IVA CF, DF, technical prior, LD, retentions, perceptions, compensation and payable',()=>{
 const month=ivaEngine(reportingData())[0];
 expect(get(month.lines,'iva_cf').value).toBe(42000);expect(get(month.lines,'iva_df').value).toBe(189000);
 expect(get(month.lines,'technical_period').value).toBe(127000);expect(month.payable).toBe(102000);expect(month.technical).toBe(0);expect(month.free).toBe(20000);
 expect(get(month.lines,'retentions').value).toBe(5000);expect(get(month.lines,'perceptions').value).toBe(10000);
});
test('IVA carries both credits month by month; never applies compensation without instruction',()=>{
 const data=reportingData();data.date_to='2026-10-31';data.groups[0].vat=10000;data.inputs[1].payload.iva_compensation=0;
 data.groups.push(...data.groups.filter(r=>['SALES','PURCHASES'].includes(r.kind)).map(r=>({...r,month:'2026-10',vat:r.kind==='SALES'?100000:20000})));
 const [sep,oct]=ivaEngine(data);expect(sep.technical).toBe(52000);expect(sep.free).toBe(45000);expect(oct.payable).toBe(28000);expect(oct.free).toBe(45000);
 const missing=reportingData();missing.inputs=missing.inputs.filter(i=>i.kind!=='IVA_OPENING');expect(ivaEngine(missing)[0].payable).toBeNull();
});
test('IVA rejects excessive or negative compensation and carries invalid month as missing',()=>{
 const data=reportingData();data.inputs[1].payload.iva_compensation=999999;expect(ivaEngine(data)[0].payable).toBeNull();
 expect(()=>validateInput('PERIOD_ADJUSTMENT','2026-09',{iva_compensation:-1})).toThrow();
});
test('IIBB LOCAL uses canonical activity/rate and explicit credits/prior/interest',()=>{
 const month=iibbEngine(reportingData())[0];expect(month.payable).toBe(17500);
 expect(get(month.lines,'determined').value).toBe(27000);expect(get(month.lines,'bank_retention').value).toBe(3000);
 expect(get(month.lines,'iibb_activity').rate_id).toBe('rate-caba');
});
test('CM handles two provinces, activities and yearly coefficient/rate changes',()=>{
 const data=reportingData();data.inputs.find(i=>i.kind==='IIBB_CONFIG').payload={regime:'CONVENIO_MULTILATERAL'};
 const template=data.inputs[2];data.inputs.push({...template,kind:'CM_COEFFICIENTS',payload:{rows:[{jurisdiction:'CABA',coefficient:.6},{jurisdiction:'BUENOS AIRES',coefficient:.4}]}});
 data.groups.push({...data.groups[0],activity_id:'activity-b',net:100000,rates:[{id:'b-caba',activity_id:'activity-b',jurisdiction:'CABA',rate:5},{id:'b-ba',activity_id:'activity-b',jurisdiction:'BUENOS AIRES',rate:2}]});
 const month=iibbEngine(data)[0];expect(month.lines.filter(l=>l.code==='iibb_activity')).toHaveLength(4);expect(month.payable).toBe(24900);
 data.date_to='2027-01-31';data.groups.push({...data.groups[0],month:'2027-01',rates:[{id:'new-caba',activity_id:'activity-a',jurisdiction:'CABA',rate:6},{id:'new-ba',activity_id:'activity-a',jurisdiction:'BUENOS AIRES',rate:4}]});
 data.inputs.push({...template,period:'2027',payload:{regime:'CONVENIO_MULTILATERAL'}},{...template,kind:'CM_COEFFICIENTS',period:'2027',payload:{rows:[{jurisdiction:'CABA',coefficient:.5},{jurisdiction:'BUENOS AIRES',coefficient:.5}]}});
 expect(iibbEngine(data).at(-1).payable).toBe(45000);
});
test('rate versions are applied per aggregate segment and ambiguous rate/missing activity fails closed',()=>{
 const data=reportingData();data.groups[0].net=10000;data.inputs[1].payload.iibb=[];data.groups.push({...data.groups[0],net:10000,rates:[{id:'new',activity_id:'activity-a',jurisdiction:'CABA',rate:4}]});expect(iibbEngine(data)[0].payable).toBe(700);
 data.groups[0].rates.push({...data.groups[0].rates[0],id:'overlap'});expect(iibbEngine(data)[0].payable).toBeNull();
 data.groups[0].activity_id=null;expect(iibbEngine(data)[0].missing.join(' ')).toContain('actividad');
 expect(()=>validateInput('CM_COEFFICIENTS','2026',{rows:[{jurisdiction:'CABA',coefficient:.8}]})).toThrow();
});
test('annual assets, liabilities, deductions and year comparison are manual, auditable and separate from imported auxiliaries',()=>{
 const data=reportingData(),template=data.inputs[2];
 const row=(family,amount,code='CUSTOM')=>({family,amount,code,category:'Categoría configurable',currency:'ARS',description:'Dato respaldado'});
 data.inputs.push({...template,kind:'ANNUAL_TAX',payload:{confirmed:true,rows:[row('income',1000000,'TAXED'),row('deduction',200000),row('asset',5000000),row('liability',1000000)],tax_determined:100000,payments:10000,retentions:20000,prior:0,opening_equity:3000000,consumed:200000}},
 {...template,kind:'ANNUAL_TAX',period:'2025',payload:{confirmed:true,rows:[row('asset',4000000),row('liability',1000000)]}});
 const report=annualEngine(data,'2026');expect(get(report.lines,'annual_base').value).toBe(800000);expect(get(report.lines,'annual_payable').value).toBe(70000);expect(get(report.lines,'annual_equity').value).toBe(4000000);expect(get(report.lines,'annual_equity_change').value).toBe(1000000);
 expect(buildModel(data).annual.lines.some(l=>l.code==='annual_auto_payroll')).toBe(true);
 expect(annualEngine(reportingData(),'2026').lines.every(l=>l.value==null)).toBe(true);
});
test('alerts use organization thresholds, disabled rules, historical comparisons and positive signals',()=>{
 const data=reportingData();data.date_to='2026-10-31';data.groups.push(...data.groups.map(r=>({...r,month:'2026-10',net:r.net==null?null:r.net*2})));data.inputs.push({...data.inputs[1],period:'2026-10'});
 const model=buildModel(data);expect(Object.keys(ALERT_DEFAULTS)).toHaveLength(13);expect(model.alerts.some(a=>a.code==='RECORD_SALES')).toBe(true);
 const alerts=alertEngine(model,{rules:{RECORD_SALES:{enabled:false},EXPENSE_GROWTH:{threshold:500,mode:'historical'}}});expect(alerts.some(a=>a.code==='RECORD_SALES')).toBe(false);expect(alerts.some(a=>a.code==='EXPENSE_GROWTH')).toBe(false);
 expect(alertEngine(model,{rules:{EXPENSE_GROWTH:{threshold:10,mode:'historical'}}}).find(a=>a.code==='EXPENSE_GROWTH').comparison_value).toBe(200000);
});
test('every calculated line exposes formula and source filters; manual input from another tenant is rejected',()=>{
 const data=reportingData(),report=buildReport(buildModel(data),'IVA');
 for(const line of report.rows){expect(line.formula).toBeTruthy();expect(Array.isArray(line.sources)).toBe(true);}
 expect(get(report.rows,'iva_cf').sources[0].filter.kind).toBe('PURCHASES');
 data.inputs[0].organization_id='another-org';expect(()=>buildModel(data)).toThrow('otra organización');
 expect(()=>monthsBetween('2026-02-31','2026-03-31')).toThrow();expect(change(10,0)).toBeNull();
});
