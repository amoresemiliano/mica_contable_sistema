import {jest} from '@jest/globals';
import fs from 'node:fs';
import {buildModel,buildReport} from '../../src/js/core/reporting/engine.js';
import {reportingData} from '../fixtures/reporting.js';
import {reportingCurrency046Data} from '../fixtures/reportingCurrency046.js';
jest.unstable_mockModule('../../src/js/core/services/reportingService.js',()=>({reportingService:{}}));
const {renderManagement,renderReport,comparisonPeriod,quickPeriod,createReportingController,metricTrace}=await import('../../src/js/components/managementReporting.js');
test('annual diagnostic shape exposes supported purchase subtotal and exact exclusions while independent KPI cards stay numeric',()=>{
 const model=buildModel(reportingCurrency046Data()),html=renderManagement(model,null);
 const card=code=>html.match(new RegExp(`<button[^>]*data-trace="${code}"[^>]*>[\\s\\S]*?</button>`))?.[0];
 expect(html).toContain('137 comprobantes de compra en ARS incluidos');expect(html).toContain('4 comprobantes de compra en USD');
 expect(card('purchases')).toContain('ARS incluido');expect(card('purchases')).toContain('1.370,00');expect(card('bank_flow')).toContain('170,00');expect(card('sales')).toContain('4.000,00');
 expect(metricTrace(model,null,'result').value).toBeNull();expect(metricTrace(model,null,'result').supported_value).toBeNull();expect(renderReport(buildReport(model,'RESULTADOS'))).toContain('ARS incluido:');
});
test('all eight summary cards retain full-period source trace including comparison and fiscal carry',()=>{
 const current=buildModel(reportingData()),previous=buildModel(reportingData({date_from:'2026-08-01',date_to:'2026-08-31'}));
 for(const code of ['sales','sales_change','result','margin','purchases','bank_balance','taxes','bank_flow']){const trace=metricTrace(current,previous,code);expect(trace.formula).toBeTruthy();expect(Array.isArray(trace.sources)).toBe(true);}
 expect(metricTrace(current,previous,'margin').unit).toBe('percent');expect(metricTrace(current,previous,'taxes').value).toBe(119500);
});
test('Gerencia renders eight analytical cards and accessible charts across five views',()=>{
 const model=buildModel(reportingData());const html=renderManagement(model,model,'Resumen');expect((html.match(/class="mr-kpi /g)||[])).toHaveLength(8);expect(html).toContain('role="img"');expect(html).toContain('Ver datos del gráfico');
 expect(renderManagement(model,model,'Tesorería')).toContain('Saldos observados por cuenta');expect(renderManagement(model,model,'Fiscal')).toContain('IVA mensual');expect(renderManagement(model,model,'Análisis')).toContain('cohorte mínima de 10');
});
test('one Gerencia and one Reportes section replace duplicate legacy panel IDs',()=>{
 const html=fs.readFileSync('index.html','utf8');expect((html.match(/id="tab-client-dashboard"/g)||[])).toHaveLength(1);expect((html.match(/id="tab-reports"/g)||[])).toHaveLength(1);expect(html).not.toContain('id="client-sales-val"');
});
test('preview exposes drill-down and manual attribution without claiming review',()=>{
 const html=renderReport(buildReport(buildModel(reportingData()),'IVA'));expect(html).toContain('BORRADOR');expect(html).toContain('data-report-line');expect(html).toContain('entrada manual');
});
test('comparison respects calendar months and leap years; YTD ends today',()=>{
 expect(comparisonPeriod('2026-03-01','2026-03-31','previous')).toEqual({from:'2026-02-01',to:'2026-02-28'});
 expect(comparisonPeriod('2024-02-01','2024-02-29','year')).toEqual({from:'2023-02-01',to:'2023-02-28'});
 expect(quickPeriod('ytd',new Date(2026,9,15))).toEqual({from:'2026-01-01',to:'2026-10-15'});
});
test('organization switch invalidates pending response and clears sensitive UI',async()=>{
 let resolve;const service={request:()=>new Promise(r=>{resolve=r;})},listeners=[];
 const store={contextState:'TENANT_READY',activeOrganizationId:'org-a',contextGeneration:1,hasCapability:()=>true,tenantResetListeners:[],subscribe:f=>listeners.push(f)};
 const root={innerHTML:'',addEventListener:jest.fn()},controller=createReportingController({store,root,mode:'management',service});
 const pending=controller.load();store.activeOrganizationId='org-b';store.contextGeneration++;listeners.forEach(f=>f());expect(root.innerHTML).toBe('');
 resolve({model:{organization:{name:'Secret A'},organization_id:'org-a'}});await pending;expect(controller.state.model).toBeNull();expect(root.innerHTML).not.toContain('Secret A');
});
test('REPORT_VIEW revocation clears results while RECORD_VIEW remains',async()=>{
 let allowed=true;const listeners=[],store={contextState:'TENANT_READY',activeOrganizationId:'org-a',contextGeneration:1,hasCapability:c=>c!=='REPORT_VIEW'||allowed,tenantResetListeners:[],subscribe:f=>listeners.push(f)};
 const root={innerHTML:'',addEventListener:jest.fn()},controller=createReportingController({store,root,mode:'reports',service:{request:async()=>({model:buildModel(reportingData())})}});
 await controller.load();allowed=false;listeners.forEach(f=>f());expect(root.innerHTML).toBe('');expect(controller.state.model).toBeNull();
});
