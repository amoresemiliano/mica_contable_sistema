// Real local browser with canonical fixtures; no remote service access.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=process.cwd(),port=18975,debugPort=20000+Math.floor(Math.random()*20000);
const html=`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/css/businessMetrics.css"><link rel="stylesheet" href="/src/css/financeWorkspace.css"><div id="root"></div><script type="module">
import {createMetricsController} from '/src/js/components/businessMetrics.js';
import {buildBusinessHealth} from '/src/js/core/metrics/engine.js';
import {reportingData} from '/tests/fixtures/reporting.js';
const listeners=[];window.store={contextState:'TENANT_READY',activeOrganizationId:reportingData().organization_id,contextGeneration:1,hasCapability:()=>true,subscribe:f=>listeners.push(f)};
window.delay=false;window.requests=[];window.data=reportingData();
const service={request:async args=>{window.requests.push(args);if(window.delay)await new Promise(r=>window.resolve=r);return {health:buildBusinessHealth(window.data,args)};},detail:async(org,from,to,filter)=>({organization_id:org,rows:[{id:'canonical-record',organization_id:org,month:filter.month}]})};
window.useHistory=async()=>{const base=reportingData(),groups=[],inputs=base.inputs.filter(i=>i.kind==='IIBB_CONFIG');for(let n=2;n<=9;n++){const month='2026-'+String(n).padStart(2,'0');groups.push(...base.groups.map(g=>({...g,month})));inputs.push(...base.inputs.filter(i=>i.kind==='PERIOD_ADJUSTMENT').map(i=>({...i,period:month,payload:{...i.payload,iva_compensation:0}})));}inputs.push({...base.inputs.find(i=>i.kind==='IVA_OPENING'),period:'2026-02'});window.data={...base,date_from:'2026-02-01',groups,inputs};await controller.load();};
window.controller=createMetricsController({store:window.store,root:document.getElementById('root'),service});Object.assign(controller.state,{from:'2026-09-01',to:'2026-09-30'});await controller.load();window.changeOrg=()=>{store.activeOrganizationId='other-org';store.contextGeneration++;listeners.forEach(f=>f());};window.revoke=()=>{store.hasCapability=()=>false;listeners.forEach(f=>f());};window.ready=true;
</script></html>`;
const server=http.createServer((req,res)=>{
 if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(html);}
 if(req.url==='/src/js/core/services/supabaseClient.js'){res.setHeader('Content-Type','application/javascript');return res.end('export const supabase={};');}
 const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',file.endsWith('.css')?'text/css':'application/javascript');res.end(fs.readFileSync(file));
});
await new Promise(r=>server.listen(port,'127.0.0.1',r));
const browser=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--disable-extensions','--remote-debugging-port='+debugPort,'--user-data-dir='+path.join(root,'scratch/metrics-browser-profile-'+debugPort),'http://127.0.0.1:'+port],{windowsHide:true,stdio:'ignore'});
let ws;
try{
 let pages;for(let i=0;i<40;i++){try{pages=await(await fetch('http://127.0.0.1:'+debugPort+'/json')).json();break;}catch{await new Promise(r=>setTimeout(r,250));}}
 if(!pages)throw Error('Local browser unavailable');ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let seq=0;const pending=new Map(),errors=[];ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 const assert=async(expression,message)=>{if(!await evaluate(expression))throw Error(message);};
 await cdp('Runtime.enable');for(let i=0;i<60&&!await evaluate('!!window.ready');i++)await new Promise(r=>setTimeout(r,100));await assert('window.ready','Fixture load failed');
 await cdp('Page.enable');
 for(const [width,height,mobile] of [[1440,1000,false],[390,844,true]]){
  await cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile});
  for(const view of ['Salud','Rentabilidad','Liquidez','Operaci\u00f3n','Riesgos y prioridades']){
   await evaluate(`document.querySelector('[data-view="${view}"]').click()`);await assert('document.documentElement.scrollWidth<=window.innerWidth','Overflow '+view+' '+width);
  }
  await evaluate(`document.querySelector('[data-view="Salud"]').click()`);
  await assert("document.querySelectorAll('.finance-priority-number').length===controller.state.health.priorities.length",'Priorities rendered once');
  await assert("document.querySelector('.finance-health-value').textContent.includes('No determinable')",'Unavailable score clearly distinguished');
  fs.writeFileSync('scratch/metrics-'+(mobile?'mobile':'desktop')+'.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 }
 await evaluate('window.useHistory()');
 await assert('controller.state.health.health.score===85 && document.querySelectorAll(".finance-pillar meter").length===6','Complete canonical score and six pillar meters');
 await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
 fs.writeFileSync('scratch/finance-metrics-complete-desktop.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 await assert('document.documentElement.scrollWidth<=window.innerWidth','Complete score mobile overflow');
 fs.writeFileSync('scratch/finance-metrics-complete-mobile.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
 await evaluate(`document.querySelector('[data-view="Operaci\u00f3n"]').click();document.querySelector('details').open=true;document.querySelector('[data-source]').click()`);
 for(let i=0;i<20&&!await evaluate(`document.getElementById('root').textContent.includes('canonical-record')`);i++)await new Promise(r=>setTimeout(r,50));
 await assert(`document.getElementById('root').textContent.includes('canonical-record')`,'Canonical detail');
 await evaluate('window.delay=true;void controller.load();window.changeOrg();window.resolve()');await new Promise(r=>setTimeout(r,100));
 await assert('controller.state.health===null','Stale response after org switch');await assert(`!document.getElementById('root').textContent.includes('canonical-record')`,'Old tenant records removed');
 await evaluate('(async()=>{window.delay=false;await controller.load()})()');await assert('controller.state.health===null','Cross org response rejected');
 await evaluate('window.revoke()');await assert("!document.querySelector('[data-view]')",'Revoked access cleared');
 if(errors.length)throw Error(errors.join(', '));console.log('PASS: desktop/mobile five views, no overflow, canonical detail, org reset, stale request rejection, cross-org response rejection, permission revocation. Local fixtures only.');await cdp('Browser.close').catch(()=>{});
}finally{ws?.close();browser.kill();server.close();}
