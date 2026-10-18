// Real local browser with canonical fixtures; no remote service access.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=process.cwd(),port=18977,debugPort=20000+Math.floor(Math.random()*20000);
const fixture=`<script type="module">
import {appStore} from '/src/js/store.js';
import {UIManager, comprobantesGrid, percepcionesGrid} from '/src/js/ui.js';
window.store=appStore;window.grids={comprobantes:comprobantesGrid,percepciones:percepcionesGrid};
Object.assign(appStore,{contextState:'TENANT_READY',activeOrganizationId:'A',confirmedOrganizationName:'Pe\u00f1a Sur',sessionUserId:'local-user',sessionEmail:'accountant@example.com',effectiveProfileName:'Contador'});
appStore.permissions.organization={loaded:true,orgId:'A',codes:['RECORD_VIEW','REPORT_EXPORT','IMPORT_VIEW','IMPORT_CREATE','PAYROLL_IMPORT','PERCEPTION_IMPORT','BANK_IMPORT','FISCAL_DOCUMENT_IMPORT']};
appStore.operationalDatasetsLoaded.add('records');appStore.operationalDatasetsLoaded.add('financials');
appStore.items=[{organization_id:'A',fecha:'16/10/2026',tipo:'emitido',razonSocial:'Pe\u00f1a',cuit:'20111111112',comprobante:'1',total:-121,iva:-21,moneda:'USD'}];
appStore.perceptions=[{organization_id:'A',fecha:'16/10/2026',fuente:'IVA',amount:10}];
appStore.salaries={organization_id:'A',periodo:'2026-10',sueldoNeto:100,sueldoBruto:100,anticipos:0,sindicatoAporte:0};
appStore.bankTransactions=[{organization_id:'A',fecha:'16/10/2026',descripcion:'Banco',monto:-25,tipo:'debit'}];
window.writes=[];window.XLSX.writeFile=(book,name)=>writes.push({name,sheets:book.SheetNames});
window.blobs=[];URL.createObjectURL=blob=>{blobs.push(blob);return 'blob:test';};HTMLAnchorElement.prototype.click=function(){window.csvName=this.download;};
window.render=()=>UIManager.render();window.show=id=>{document.querySelectorAll('.tab-content').forEach(s=>s.classList.toggle('hidden',s.id!==id));UIManager.render();};
document.getElementById('login-container').style.display='none';document.getElementById('app-container').classList.remove('hidden');
UIManager.render();document.addEventListener('DOMContentLoaded',()=>{appStore.notify();window.ready=true;});
</script>`;
const html=fs.readFileSync(path.join(root,'index.html'),'utf8').replace('<head>','<head><script>window.fixtureErrors=[];addEventListener("error",event=>fixtureErrors.push(event.message));</script>').replace('</body>',fixture+'</body>');
const server=http.createServer((req,res)=>{
 if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(html);}
 if(req.url==='/src/js/core/services/supabaseClient.js'){res.setHeader('Content-Type','application/javascript');return res.end('export const supabase={auth:{getSession:()=>new Promise(()=>{}),onAuthStateChange:()=>{}},rpc:async()=>({data:[]})};');}
 const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
 res.setHeader('Content-Type',file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'application/javascript');res.end(fs.readFileSync(file));
});
await new Promise(r=>server.listen(port,'127.0.0.1',r));
const browser=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--disable-extensions','--remote-debugging-port='+debugPort,'--user-data-dir='+path.join(root,'scratch/module-exports-browser-profile-'+debugPort),'http://127.0.0.1:'+port],{windowsHide:true,stdio:'ignore'});
let ws;
try{
 let pages;for(let i=0;i<40;i++){try{pages=await(await fetch('http://127.0.0.1:'+debugPort+'/json')).json();break;}catch{await new Promise(r=>setTimeout(r,250));}}
 if(!pages)throw Error('Local browser unavailable');ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));
 let seq=0;const pending=new Map(),errors=[];ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 const assert=async(expression,message)=>{if(!await evaluate(expression))throw Error(message);};
 await cdp('Runtime.enable');for(let i=0;i<60&&!await evaluate('!!window.ready');i++)await new Promise(r=>setTimeout(r,100));if(!await evaluate('!!window.ready'))throw Error('Fixture load failed: '+JSON.stringify(await evaluate('fixtureErrors')));
 await cdp('Page.enable');await assert("document.querySelectorAll('[data-workspace]').length===4",'Shared workspace not mounted');
 for(const [width,height,mobile] of [[1440,1000,false],[390,844,true]]){
  await cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile});
  for(const [module,id] of [['comprobantes','tab-conciliador'],['percepciones','tab-percepciones'],['bancos','tab-bancos'],['sueldos','tab-sueldos']]){
   await evaluate(`show('${id}');document.querySelector('#${id} .workspace-download').open=true`);
   if(!mobile && module!=='sueldos') {
    await assert(`(()=>{const root=document.getElementById('${id}'),rect=s=>root.querySelector(s).getBoundingClientRect(),col=rect('[id$="-col-btn"]'),filter=rect('.workspace-filters'),actions=rect('.workspace-actions'),period=rect('.workspace-period'),search=rect('.workspace-search');return Math.abs(col.y-actions.y)<10 && col.y<period.y && Math.abs(period.y-search.y)<10 && actions.x>filter.x && search.x>period.x;})()`,'Two-row geometry '+module);
   }
   if(!mobile && module==='sueldos')await assert(`document.querySelector('#tab-sueldos .workspace-period').getBoundingClientRect().y>document.querySelector('#tab-sueldos .workspace-actions').getBoundingClientRect().y`,'Payroll period on second row');
   await evaluate(`if(grids['${module}']){grids['${module}'].visibleColumns=new Set(Array.from(document.querySelectorAll('#${id} th[data-col-key]')).map(th=>th.dataset.colKey));render();}`);
   await assert(`Array.from(document.querySelectorAll('[data-module-export="${module}"]')).every(b=>!b.disabled && b.getBoundingClientRect().width>0)`,'Export controls not usable');
   await assert(`Array.from(document.querySelectorAll('[data-module-export="${module}"]')).every(b=>b.getBoundingClientRect().right<=innerWidth)`,'Export controls overflow');
   await assert(`(()=>{const groups=[...document.querySelectorAll('.module-export-actions')];const withExports=document.documentElement.scrollWidth;groups.forEach(g=>g.style.display='none');const withoutExports=document.documentElement.scrollWidth;groups.forEach(g=>g.style.display='flex');return withExports<=Math.max(innerWidth,withoutExports);})()`,'Exports introduced horizontal overflow');
   await evaluate(`document.querySelector('[data-module-export="${module}"][data-export-format="csv"]').click();document.querySelector('[data-module-export="${module}"][data-export-format="xlsx"]').click()`);
   await assert(`csvName.startsWith('mica_${module}_') && writes.at(-1).name.startsWith('mica_${module}_')`,'Download not triggered');
   await assert(`document.querySelector('#${id} .workspace-user').textContent==='accountant@example.com · Contador'`,'User badge repeats company');
   await assert(`document.querySelector('#${id} .operational-context-toolbar').textContent.split('Peña Sur').length===2`,'Company not shown once');
   await evaluate(`document.querySelector('[data-module-export="${module}"][data-export-format="pdf"]').click();document.querySelector('iframe[title="Vista de impresión"]').onload=()=>{}`);
   await assert(`document.querySelector('iframe[title="Vista de impresión"]').srcdoc.includes('Peña Sur')`,'PDF company missing');
   await evaluate(`document.querySelector('iframe[title="Vista de impresión"]').remove()`);
   await assert(`(()=>{const table=document.querySelector('#${id} .workspace-table-viewport');if(!table)return false;return getComputedStyle(table).overflowX==='auto';})()`,'Table viewport cannot scroll');
   await assert(`(()=>{const view=document.querySelector('#${id} .workspace-table-viewport');if(view.scrollWidth<=view.clientWidth)return true;view.scrollLeft=view.scrollWidth;return view.scrollLeft>0;})()`,'Rightmost table columns inaccessible');
   await assert(`document.documentElement.scrollWidth<=innerWidth`,'Page-wide overflow');
  }
  await evaluate(`show('tab-conciliador');document.querySelector('#tab-conciliador .workspace-download').open=false`);
  const screenshot=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
  fs.mkdirSync(path.join(root,'scratch'),{recursive:true});
  fs.writeFileSync(path.join(root,`scratch/operational-workspace-${mobile?'mobile':'desktop'}.png`),Buffer.from(screenshot.data,'base64'));
 }
 await assert('blobs.length===8 && writes.length===8','Eight format/viewport downloads expected');
 await evaluate(`show('tab-conciliador');document.querySelector('.workspace-import').open=true;window.pickers=[];for(const type of ['recibidos','emitidos']){document.getElementById('file-'+type).click=()=>pickers.push(type);document.querySelector('[data-import-input="file-'+type+'"]').click();}`);
 await assert(`pickers.join(',')==='recibidos,emitidos'`,'Existing import file pickers not invoked');
 await assert(`Array.from(document.querySelectorAll('.sidebar-nav a[data-tab]')).every(a=>a.getAttribute('href')==='#'+a.dataset.tab)`,'Sidebar links lack native href');
 // A second real browser page follows its hash without navigating the first page.
 const second=await cdp('Target.createTarget',{url:'http://127.0.0.1:'+port+'/#tab-bancos',background:true});
 const pages2=await(await fetch('http://127.0.0.1:'+debugPort+'/json')).json();
 const secondSocket=new WebSocket(pages2.find(page=>page.id===second.targetId).webSocketDebuggerUrl);
 await new Promise(resolve=>secondSocket.addEventListener('open',resolve,{once:true}));
 let secondSequence=0;const secondPending=new Map();
 secondSocket.addEventListener('message',event=>{const message=JSON.parse(event.data);if(message.id){secondPending.get(message.id)?.(message.result);secondPending.delete(message.id);}});
 const secondEvaluate=expression=>new Promise(resolve=>{const id=++secondSequence;secondPending.set(id,result=>resolve(result.result?.value));secondSocket.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,returnByValue:true,awaitPromise:true}}));});
 try {
  for(let n=0;n<60&&!await secondEvaluate('!!window.ready');n++)await new Promise(resolve=>setTimeout(resolve,100));
  if(!await secondEvaluate(`document.querySelector('.tab-content:not(.hidden)').id==='tab-bancos' && store.activeOrganizationId==='A'`))throw Error('Second tab did not preserve its module');
  await assert(`document.querySelector('.tab-content:not(.hidden)').id==='tab-conciliador' && store.activeOrganizationId==='A'`,'Second tab changed first module');
  await secondEvaluate(`store.contextState='SWITCHING';store.notify();true`);
  for(let n=0;n<30&&!await evaluate(`store.contextState==='ERROR'`);n++)await new Promise(resolve=>setTimeout(resolve,100));
  await assert(`store.contextState==='ERROR' && store.items.length===0`,'Second-tab company switch did not invalidate first');
 } finally {secondSocket.close();await cdp('Target.closeTarget',{targetId:second.targetId});}
 await evaluate(`store.contextState='TENANT_READY';store.items=[{organization_id:'A',fecha:'16/10/2026',razonSocial:'Peña',cuit:'20',comprobante:'1',total:1}];render()`);
 await assert(`(async()=>{const csv=await blobs[0].text();return csv.includes('USD') && csv.includes('-121');})()`,'Currency or sign lost');
 await evaluate(`grids.comprobantes.setSearch('does-not-exist');render()`);
 await assert(`document.querySelector('[data-module-export="comprobantes"]').disabled`,'Filtered empty state not disabled');
 await evaluate(`store.contextState='SWITCHING';store.notify()`);
 await assert(`Array.from(document.querySelectorAll('[data-module-export]')).every(b=>b.disabled)`,'Switching did not disable export');
 await evaluate(`store.clearTenantState();store.activeOrganizationId='B';store.contextState='TENANT_READY';store.permissions.organization={loaded:true,orgId:'B',codes:['RECORD_VIEW','REPORT_EXPORT']};render()`);
 await assert(`Array.from(document.querySelectorAll('[data-module-export]')).every(b=>b.disabled)`,'Previous-company records available after switch');
 // Real route activation uses the shared administration host, including hash changes.
 await evaluate(`store.permissions.platform={loaded:true,codes:['GLOBAL_CATALOG_VIEW','PLATFORM_MANAGE']};store.activeOrganizationId=null;store.contextState='PLATFORM_READY';history.replaceState(null,'','#tab-bancos');store.notify()`);
 await assert(`document.body.dataset.activeModule==='tab-categorizacion' && location.hash==='#tab-categorizacion'`,'Platform canonical fallback');
 for(const route of ['tab-configuracion','tab-categorizacion']) {
  await evaluate(`switchTab('${route}');for(let n=0;n<10;n++)store.notify()`);
  await assert(`document.body.dataset.activeModule==='${route}' && location.hash==='#${route}' && !document.getElementById('tab-configuracion').classList.contains('hidden')`,'Shared host route stability '+route);
 }
 await evaluate(`location.hash='#tab-bancos'`);
 await new Promise(resolve=>setTimeout(resolve,100));
 await assert(`location.hash==='#tab-categorizacion'`,'Unavailable hash fallback');
 if(errors.length)throw Error(errors.join('; '));
 console.log('PASS: four shared workspaces, desktop/mobile, CSV/XLSX/PDF, headers, native links, two real tabs and context invalidation, import pickers, scroll bounds, filtered empty state, organization transition');
 }finally{ws?.close();browser.kill();server.close();}
