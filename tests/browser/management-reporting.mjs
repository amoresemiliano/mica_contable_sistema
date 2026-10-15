// Local fixture browser validation only. No SQL, Supabase or external requests.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=process.cwd(),port=18965,debugPort=18966;
const html=`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>MICA Gerencia y Reportes · Validación local</title><link rel="stylesheet" href="/src/css/styles.css"><link rel="stylesheet" href="/src/css/managementReporting.css"><style>body{display:block;padding:24px;background:#f4f7fa}main{max-width:1300px;margin:auto}@media(max-width:600px){body{padding:10px}}</style><script src="/src/js/vendor/xlsx.full.min.js"></script><main><div id="management-root"></div><div id="reports-root" hidden></div></main><script type="module">
import {createReportingController} from '/src/js/components/managementReporting.js';
import {buildModel,buildReport} from '/src/js/core/reporting/engine.js';
import {reportingData} from '/tests/fixtures/reporting.js';
import {reportingCurrency046Data} from '/tests/fixtures/reportingCurrency046.js';
const listeners=[];window.store={contextState:'TENANT_READY',activeOrganizationId:reportingData().organization_id,contextGeneration:1,confirmedOrganizationName:'Empresa de prueba',tenantResetListeners:[],hasCapability:()=>true,subscribe:f=>listeners.push(f)};
window.saved=[];window.snapshots=[];window.data=reportingData();
const service={request:async args=>{
 if(args.action==='input'){window.saved.push(args);const previous=window.data.inputs.find(i=>i.kind===args.kind&&i.period===args.period);if(previous)window.data.inputs.splice(window.data.inputs.indexOf(previous),1);window.data.inputs.push({id:'new-input',organization_id:window.store.activeOrganizationId,kind:args.kind,period:args.period,payload:args.payload,note:args.note,created_by:'accountant',created_at:new Date().toISOString(),revision:args.revision+1});return {};}
 const data={...structuredClone(window.data),date_from:args.from,date_to:args.to},model=buildModel(data);
 if(args.action==='data')return {model};const report=buildReport(model,args.type);if(args.action==='close'){window.snapshots.push(structuredClone(report));return {snapshot_id:'snapshot-1',report:{...report,status:'CERRADO'}};}return {report};},
 detail:async(org,from,to,filter,offset,snapshot)=>({organization_id:org,total:1,rows:[{id:snapshot?'frozen-id':'persisted-id',day:'2026-09-01',source_type:'eco_normalized_records',organization_id:org,supplier:'Proveedor de prueba',currency:filter.currency||'PES',amount:2420}]}),
 history:async(org,from,to,type,snapshot)=>snapshot?{id:'snapshot-1',version:1,organization_id:org,calculated:window.snapshots[0],inputs:window.data}:{events:[{status:'CERRADO',actor:'accountant',happened_at:'2026-10-15'}],snapshots:window.snapshots.map((s,i)=>({id:'snapshot-1',version:i+1,generated_at:s.generated_at,generated_by:s.generated_by}))}};
window.management=createReportingController({store:window.store,root:document.getElementById('management-root'),mode:'management',service});window.reports=createReportingController({store:window.store,root:document.getElementById('reports-root'),mode:'reports',service});
Object.assign(window.management.state,{from:'2026-09-01',to:'2026-09-30'});Object.assign(window.reports.state,{from:'2026-09-01',to:'2026-09-30'});await window.management.load();await window.reports.load();window.ready=true;window.switchFixture=mode=>{document.getElementById('management-root').hidden=mode!=='management';document.getElementById('reports-root').hidden=mode!=='reports';};window.revoke=()=>{window.store.hasCapability=()=>false;listeners.forEach(f=>f());};
window.currencyFixture=async()=>{window.data=reportingCurrency046Data();Object.assign(window.management.state,{from:'2026-01-01',to:'2026-12-31'});await window.management.load();window.switchFixture('management');};
</script></html>`;
const server=http.createServer((req,res)=>{
 if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(html);}
 if(req.url==='/src/js/core/services/supabaseClient.js'){res.setHeader('Content-Type','application/javascript');return res.end('export const supabase={};');}
 const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));
 if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',file.endsWith('.css')?'text/css':'application/javascript');res.end(fs.readFileSync(file));
});
await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
const browser=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--disable-extensions','--remote-debugging-port='+debugPort,'--user-data-dir='+path.join(root,'scratch/reporting-browser-profile'),'http://127.0.0.1:'+port],{windowsHide:true,stdio:'ignore'});
let ws;
try{
 let pages;for(let i=0;i<40;i++){try{pages=await(await fetch('http://127.0.0.1:'+debugPort+'/json')).json();break;}catch{await new Promise(r=>setTimeout(r,250));}}
 if(!pages)throw Error('Local browser unavailable');ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let seq=0;const pending=new Map(),errors=[];ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 const assert=async(expression,message)=>{if(!await evaluate(expression))throw Error(message);};
 await cdp('Runtime.enable');for(let i=0;i<60&&!await evaluate('!!window.ready');i++)await new Promise(r=>setTimeout(r,100));await assert('window.ready','Fixture load failed');
 await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});await cdp('Page.enable');
 await assert("document.querySelectorAll('#management-root .mr-kpi').length===8",'Eight KPI cards');
 for(const view of ['Resumen','Resultados','Tesorería','Fiscal','Análisis']){await evaluate(`document.querySelector('[data-view="${view}"]').click()`);await assert("document.querySelector('#management-root svg[role=img]')!==null",'Accessible chart '+view);}
 await evaluate("document.querySelector('[data-view=Resumen]').click()");fs.writeFileSync('scratch/reporting-desktop.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate("document.querySelector('#management-root [data-trace=sales]').click()");await assert("document.querySelector('.mr-dialog').textContent.includes('persisted-id')",'Drill-down source IDs');await evaluate("document.querySelector('[data-close-detail]').click()");
 await evaluate("window.switchFixture('reports');document.querySelector('[data-preview]').click()");await assert("document.querySelector('#reports-root').textContent.includes('IVA CF')",'IVA preview');
 await evaluate("document.querySelector('[data-status=close]').click()");await assert('window.snapshots.length===1','Close snapshot');await evaluate("window.data.groups[0].vat=999999;document.querySelector('[data-history]').click()");await evaluate("document.querySelector('[data-snapshot]').click()");await assert("window.reports.state.report.rows.find(r=>r.code==='iva_df').value===189000",'Frozen snapshot after source change');
 await evaluate("document.querySelector('[data-report-line=\"0\"]').click()");await assert("document.querySelector('.mr-dialog').textContent.includes('frozen-id')",'Frozen drill-down');await evaluate("document.querySelector('[data-close-detail]').click()");
 await evaluate("document.querySelector('details.mr-panel').open=true;document.querySelector('[name=technical]').value='250';document.querySelector('[name=free]').value='300';document.querySelector('[data-input-form]').requestSubmit()");await assert("window.saved.length===1 && window.saved[0].payload.technical===25000",'Manual opening form and cents');
 for(const kind of ['PERIOD_ADJUSTMENT','IIBB_CONFIG','CM_COEFFICIENTS','ANNUAL_TAX','ALERT_SETTINGS']){await evaluate(`document.querySelector('[name=input-kind]').value='${kind}';document.querySelector('[name=input-kind]').dispatchEvent(new Event('change',{bubbles:true}))`);await assert(`document.querySelector('[data-input-form]').dataset.kind==='${kind}'`,'Input form '+kind);}
 await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await assert('document.documentElement.scrollWidth<=window.innerWidth','Report mobile overflow');fs.writeFileSync('scratch/reporting-mobile.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate("window.switchFixture('management')");await assert('document.documentElement.scrollWidth<=window.innerWidth','Management mobile overflow');fs.writeFileSync('scratch/management-mobile.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate('window.currencyFixture()');
 await assert("document.querySelector('#management-root [data-trace=sales]').textContent.includes('4.000,00')",'046 annual peso sales');
 await assert("document.querySelector('#management-root [data-trace=bank_flow]').textContent.includes('170,00')",'046 bank not poisoned');
 await assert("document.querySelector('#management-root [data-trace=purchases]').textContent.includes('1.370,00') && document.querySelector('#management-root [data-trace=purchases]').textContent.includes('137 comprobantes de compra en ARS incluidos')",'046 purchase subtotal and count');
 await assert("document.querySelector('#management-root [data-trace=result]').textContent.includes('4 comprobantes de compra en USD')",'046 result precise incomplete warning');
 await assert('document.documentElement.scrollWidth<=window.innerWidth','046 mobile exclusion disclosure overflow');
 fs.writeFileSync('scratch/currency046-mobile.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate("document.querySelector('#management-root [data-trace=purchases]').click();[...document.querySelectorAll('[data-detail-source]')].find(b=>b.textContent.includes('USD')).click()");
 await assert("document.querySelector('.mr-dialog').textContent.includes('2.420,00 USD')",'046 native USD detail label');await evaluate("document.querySelector('[data-close-detail]').click()");
 await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});fs.writeFileSync('scratch/currency046-desktop.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate('window.revoke()');await assert("document.querySelector('#management-root').innerHTML===''&&document.querySelector('#reports-root').innerHTML===''", 'revocation');
 if(errors.length)throw Error(errors.join(', '));console.log('PASS: five views, 8 KPIs, IVA preview, immutable snapshot/drill-down, six forms, 046 annual currency/scoped warnings/native USD detail, mobile overflow and revocation. Local fixtures only.');await cdp('Browser.close').catch(()=>{});
}finally{ws?.close();browser.kill();server.close();}
