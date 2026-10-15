import {jest} from '@jest/globals';
import fs from 'node:fs';
import crypto from 'node:crypto';
import {normalizeReportingCurrency,isArsCurrency} from '../src/js/core/reporting/currency.js';
import {buildModel,buildReport,aggregateMetric,CALCULATION_REVISION} from '../src/js/core/reporting/engine.js';
import {createReportingHandler} from '../src/js/core/reporting/server.js';
import {reportSheets} from '../src/js/core/reporting/exports.js';
import {reportingCurrency046Data} from './fixtures/reportingCurrency046.js';
const find=(model,code,month='2026-09')=>model.monthly.find(m=>m.month===month).lines.find(l=>l.code===code);
const taxLine=(model,code,month='2026-09')=>model.iva.find(m=>m.month===month).lines.find(l=>l.code===code);

test.each(['$','PES','ARS',' pes ','ars'])('%s is an ARS alias, not a conversion',currency=>{
 expect(normalizeReportingCurrency(currency)).toBe('ARS');expect(isArsCurrency({currency})).toBe(true);
});
test.each(['USD','DOL','EUR','',null])('%s is not ARS',currency=>expect(isArsCurrency({currency})).toBe(false));
test('diagnostic-shaped fixture retains 4 sales, 137 peso/4 USD purchases, 83 banks, 1 payroll and 64 taxes',()=>{
 const data=reportingCurrency046Data();const count=(kind,currency)=>data.groups.filter(r=>r.kind===kind&&(!currency||r.currency===currency)).reduce((n,r)=>n+r.count,0);
 expect(count('SALES','$')).toBe(4);expect(count('PURCHASES','$')).toBe(137);expect(count('PURCHASES','USD')).toBe(4);expect(count('BANK','PES')).toBe(83);expect(count('PAYROLL','PES')).toBe(1);expect(count('TAX')).toBe(64);
});
test('USD purchases do not poison sales, bank or payroll; full purchases/result remain incomplete',()=>{
 const model=buildModel(reportingCurrency046Data());
 expect(find(model,'sales').value).toBe(400000);expect(find(model,'bank_flow').value).toBe(17000);expect(find(model,'payroll').value).toBe(15000);
 const purchases=find(model,'purchases');expect(purchases.value).toBeNull();expect(purchases.supported_value).toBe(137000);expect(purchases.included_count).toBe(137);expect(purchases.excluded_count).toBe(4);expect(purchases.excluded_group_count).toBe(4);
 expect(find(model,'result').value).toBeNull();expect(find(model,'result').missing.join(' ')).toContain('4 comprobantes de compra en USD');
 expect(purchases.excluded_currencies).toEqual([{currency:'USD',record_count:4,group_count:4,source_value:40000,field:'net'}]);
});
test('annual cards sum imported activity with NO_ACTIVITY zeros; NO_DATA stays unknown',()=>{
 const model=buildModel(reportingCurrency046Data());
 for(const [code,value] of [['sales',400000],['bank_flow',17000],['payroll',15000]]){
  expect(aggregateMetric(model,code).value).toBe(value);expect(find(model,code,'2026-01').status).toBe('NO_ACTIVITY');expect(find(model,code,'2026-01').value).toBe(0);
 }
 const noData=reportingCurrency046Data();noData.groups=[];expect(aggregateMetric(buildModel(noData),'sales').status).toBe('NO_DATA');expect(aggregateMetric(buildModel(noData),'sales').value).toBeNull();
 expect(aggregateMetric(model,'purchases').value).toBeNull();expect(aggregateMetric(model,'purchases').supported_value).toBe(137000);expect(aggregateMetric(model,'result').status).toBe('INCOMPLETE');
});
test('absence of a bank dataset stays NO_DATA despite invoice data; a missing purchase field stays scoped',()=>{
 const data=reportingCurrency046Data({annual:false});data.groups=data.groups.filter(r=>r.kind!=='BANK');data.groups.find(r=>r.kind==='PURCHASES').missing_net=1;
 const model=buildModel(data);expect(aggregateMetric(model,'bank_flow').status).toBe('NO_DATA');expect(aggregateMetric(model,'bank_flow').value).toBeNull();expect(aggregateMetric(model,'sales').value).toBe(400000);expect(aggregateMetric(model,'payroll').value).toBe(15000);
});
test('foreign-only evidence is incomplete, not absence and not peso zero',()=>{
 const data=reportingCurrency046Data();data.groups=data.groups.filter(r=>r.kind!=='SALES');data.groups.push({...data.groups.find(r=>r.kind==='PURCHASES'),kind:'SALES',currency:'USD',net:100000});
 const sales=aggregateMetric(buildModel(data),'sales');expect(sales.status).toBe('INCOMPLETE');expect(sales.value).toBeNull();expect(sales.supported_value).toBe(0);
});
test('tipoCambio is neither applied nor treated as proof of conversion; input rows remain byte-equivalent',()=>{
 const data=reportingCurrency046Data(),before=JSON.stringify(data),model=buildModel(data);
 expect(aggregateMetric(model,'purchases').supported_value).toBe(137000);expect(JSON.stringify(data)).toBe(before);
 expect(model.groups.find(r=>r.currency==='USD').net).toBe(10000);expect(model.groups.find(r=>r.kind==='SALES').currency).toBe('ARS');
 expect(find(model,'sales').sources[0].filter.currency).toBe('$'); // Works before 046; canonical 046 responses use ARS.
 expect(model.calculation_revision).toBe(CALCULATION_REVISION);
});
test('IVA DF stays independent of USD purchases; CF/full IVA are incomplete; foreign bank never poisons fiscal',()=>{
 const data=reportingCurrency046Data({annual:false}),model=buildModel(data);
 expect(taxLine(model,'iva_df').value).toBe(84000);expect(taxLine(model,'iva_cf').value).toBeNull();expect(taxLine(model,'iva_cf').supported_value).toBe(28770);expect(model.iva[0].payable).toBeNull();
 data.groups=data.groups.filter(r=>r.kind!=='TAX'||r.tax_type);data.groups=data.groups.filter(r=>r.kind!=='PURCHASES'||r.currency!=='USD');data.groups.find(r=>r.kind==='BANK').currency='USD';
 const clean=buildModel(data);expect(clean.iva[0].payable).not.toBeNull();expect(aggregateMetric(clean,'bank_flow').value).toBeNull();expect(aggregateMetric(clean,'sales').value).toBe(400000);
});
test('current foreign invoice does not erase independently known IVA opening/credits; technical and LD carries stay separate',()=>{
 const data=reportingCurrency046Data({annual:false});data.groups=data.groups.filter(r=>r.kind!=='TAX'||r.tax_type);const model=buildModel(data);
 expect(taxLine(model,'technical_prior').value).toBe(20000);expect(taxLine(model,'free_prior').value).toBe(30000);expect(taxLine(model,'perceptions').value).toBe(5000);expect(taxLine(model,'free_next').value).toBe(35000);expect(model.iva[0].technical).toBeNull();expect(model.iva[0].payable).toBeNull();
});
test('IIBB depends on sales/tax configuration, not USD purchases or foreign bank/payroll',()=>{
 const data=reportingCurrency046Data({annual:false});data.groups=data.groups.filter(r=>r.kind!=='TAX'||r.tax_type);data.groups.find(r=>r.kind==='BANK').currency='USD';data.groups.find(r=>r.kind==='PAYROLL').currency='USD';
 const model=buildModel(data);expect(model.iibb[0].payable).toBe(12000);expect(buildReport(model,'IIBB').missing).toEqual([]);
 data.groups.find(r=>r.kind==='SALES').currency='USD';expect(buildModel(data).iibb[0].payable).toBeNull();expect(buildReport(buildModel(data),'IIBB').missing.join(' ')).toContain('comprobantes de venta en USD');
});
test('RECORD_ANOMALIES still counts the four USD records, without counting supported peso aliases',()=>{
 const model=buildModel(reportingCurrency046Data({annual:false})),alert=model.alerts.find(a=>a.code==='RECORD_ANOMALIES');expect(alert.current_value).toBe(4);expect(alert.source).toBe('anomalies');
});
test('results and IVA reports preserve independent numeric lines and explicitly excluded source metadata',()=>{
 const model=buildModel(reportingCurrency046Data({annual:false})),report=buildReport(model,'RESULTADOS');
 expect(report.rows.find(r=>r.code==='sales').value).toBe(400000);expect(report.rows.find(r=>r.code==='payroll').value).toBe(15000);expect(report.rows.find(r=>r.code==='result').value).toBeNull();
 expect(report.missing.join(' ')).toContain('4 comprobantes de compra en USD');expect(report.currency_exclusions[0].record_count).toBe(4);
 expect(report.rows.find(r=>r.code==='purchases').sources.filter(s=>s.included_in_ars===false)).toHaveLength(4);
});
test.each(['IVA','RESULTADOS'])('trusted endpoint blocks REVIEW/CLOSE of incomplete %s',async type=>{
 const data=reportingCurrency046Data({annual:false}),writer=jest.fn();
 const handler=createReportingHandler({authenticate:async()=>({id:'verified-subject'}),userClient:()=>({rpc:async name=>name==='get_my_operational_context'?{data:{organization_id:data.organization_id}}:{data}}),serviceClient:{rpc:writer}});
 for(const action of ['review','close']){const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({organization_id:data.organization_id,from:data.date_from,to:data.date_to,type,action,input_hash:data.input_hash})}));expect(response.status).toBe(400);expect((await response.json()).error).toContain('datos faltantes');}
 expect(writer).not.toHaveBeenCalled();
});
test('independent IIBB may close with fully supported sales even when purchases contain USD',async()=>{
 const data=reportingCurrency046Data({annual:false});data.groups=data.groups.filter(r=>r.kind!=='TAX'||r.tax_type);
 const writer=jest.fn(async()=>({data:{snapshot_id:'new-snapshot'}})),handler=createReportingHandler({authenticate:async()=>({id:'verified-subject'}),userClient:()=>({rpc:async name=>name==='get_my_operational_context'?{data:{organization_id:data.organization_id}}:{data}}),serviceClient:{rpc:writer}});
 const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({organization_id:data.organization_id,from:data.date_from,to:data.date_to,type:'IIBB',action:'close',input_hash:data.input_hash})}));expect(response.status).toBe(200);expect(writer).toHaveBeenCalledTimes(1);
});
test('tenant isolation and active-context checks remain enforced with aliases and foreign rows',()=>{
 const data=reportingCurrency046Data();data.inputs[0].organization_id='foreign-tenant';expect(()=>buildModel(data)).toThrow('otra organización');
});
test('export retains the incomplete total, supported ARS subtotal and foreign source units',()=>{
 const report=buildReport(buildModel(reportingCurrency046Data({annual:false})),'RESULTADOS'),sheets=reportSheets(report);
 const purchase=sheets.Calculos.find(r=>r[2]==='Compras netas documentales');expect(purchase[3]).toBe('No disponible');expect(purchase[13]).toBe('INCOMPLETE');expect(purchase[14]).toBe(1370);expect(purchase[15]).toBe(137);expect(purchase[16]).toBe(4);
 expect(sheets.Fuentes.filter(r=>r[7]==='NO'&&r[8]==='USD').length).toBeGreaterThanOrEqual(4);
 expect(sheets.Metadatos).toContainEqual(['USD: importe de origen (amount)',484]);
});
test('installed 045 migration and rollback remain unchanged',()=>{
 for(const [path,hash] of [['sql/045_management_reporting.sql','1d1918898dfd68971c2190524f3db0c11e1fdcec15e7a1f07bfb41e8b21a136f'],['sql/045_management_reporting_down.sql','4be1c302bea037e9ea36d39be4088058308ff021771c3832075c9fcf95ba35dc']])expect(crypto.createHash('sha256').update(read(path)).digest('hex')).toBe(hash);
});

const read=p=>fs.readFileSync(p,'utf8').replace(/\r/g,'');
test('046 freezes the complete 045 view and pins every unchanged reporting function body',()=>{
 const original=read('sql/045_management_reporting.sql'),up=read('sql/046_reporting_currency_scope.sql');
 const originalView=original.split('CREATE VIEW private.reporting_045_facts AS\n')[1].split(';\nREVOKE ALL ON private.reporting_045_facts')[0];
 expect(up.split('CREATE TEMP VIEW reporting_046_expected_045 AS\n')[1].split(';\nCREATE TEMP VIEW')[0]).toBe(originalView);
 const functions=[...original.matchAll(/CREATE FUNCTION ((?:public|private)\.(?:mica_reporting_\w+|reporting_045_(?:number|context)))\([\s\S]*?AS \$\$([\s\S]*?)\$\$;/g)];expect(functions).toHaveLength(7);
 for(const [,name,body] of functions)expect(up).toContain(crypto.createHash('md5').update(body.trim()).digest('hex'));
 expect(up).toContain('pg_get_viewdef');expect(up).toContain('view drift or partial installation');expect(up).toContain('046 requires installed 045');expect(up).toContain('IN (\'PES\',\'ARS\',\'$\')');
});
test('046 only changes projected currency and keeps functions, row predicates, amounts and security intact',()=>{
 const up=read('sql/046_reporting_currency_scope.sql'),old=up.split('CREATE TEMP VIEW reporting_046_expected_045 AS\n')[1].split(';\nCREATE TEMP VIEW')[0],fixed=up.split('CREATE OR REPLACE VIEW private.reporting_045_facts AS\n')[1].split(';\nDO $postflight$')[0];
 const expected=old.replace("CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN p->>'moneda' ELSE 'PES' END AS currency",()=>"CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN\n  CASE WHEN upper(btrim(p->>'moneda')) IN ('PES','ARS','$') THEN 'ARS'\n   ELSE upper(btrim(p->>'moneda')) END ELSE 'ARS' END AS currency").replace("f.descripcion,NULL,'PES'","f.descripcion,NULL,'ARS'").replace("->>'razonSocial',NULL,'PES'","->>'razonSocial',NULL,'ARS'");
 expect(fixed).toBe(expected);expect(up).not.toContain('CREATE OR REPLACE FUNCTION');expect(up).toContain('relforcerowsecurity');expect(up).toContain('reporting function/ACL changed');
 const down=read('sql/046_reporting_currency_scope_down.sql');expect(down).toContain("||b.definition");expect(down).toContain('rollback view/security drift');expect(down).not.toMatch(/\b(DELETE FROM|TRUNCATE)\b/);expect(down).not.toContain('DROP TABLE private.eco_report');
});
