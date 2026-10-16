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
Object.assign(appStore,{contextState:'TENANT_READY',activeOrganizationId:'A',confirmedOrganizationName:'Pe?a Sur'});
appStore.permissions.organization={loaded:true,orgId:'A',codes:['RECORD_VIEW','REPORT_EXPORT','IMPORT_VIEW','IMPORT_CREATE','SALARY_IMPORT','PERCEPTION_IMPORT']};
appStore.items=[{organization_id:'A',fecha:'16/10/2026',tipo:'emitido',razonSocial:'Pe?a',cuit:'20111111112',comprobante:'1',total:-121,iva:-21,moneda:'USD'}];
appStore.perceptions=[{organization_id:'A',fecha:'16/10/2026',fuente:'IVA',amount:10}];
appStore.salaries={organization_id:'A',periodo:'2026-10',sueldoNeto:100};
window.writes=[];window.XLSX.writeFile=(book,name)=>writes.push({name,sheets:book.SheetNames});
window.blobs=[];URL.createObjectURL=blob=>{blobs.push(blob);return 'blob:test';};HTMLAnchorElement.prototype.click=function(){window.csvName=this.download;};
window.render=()=>UIManager.render();window.show=id=>{document.querySelectorAll('.tab-content').forEach(s=>s.classList.toggle('hidden',s.id!==id));UIManager.render();};
document.getElementById('login-container').style.display='none';document.getElementById('app-container').classList.remove('hidden');
UIManager.render();window.ready=true;
</script>`;
const html=fs.readFileSync(path.join(root,'index.html'),'utf8').replace('</body>',fixture+'</body>');
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
 await cdp('Runtime.enable');for(let i=0;i<60&&!await evaluate('!!window.ready');i++)await new Promise(r=>setTimeout(r,100));await assert('window.ready','Fixture load failed');
 await cdp('Page.enable');
 for(const [width,height,mobile] of [[1440,1000,false],[390,844,true]]){
  await cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile});
  for(const [module,id] of [['comprobantes','tab-conciliador'],['percepciones','tab-percepciones'],['sueldos','tab-sueldos']]){
   await evaluate(`show('${id}')`);
   await assert(`Array.from(document.querySelectorAll('[data-module-export="${module}"]')).every(b=>!b.disabled && b.getBoundingClientRect().width>0)`,'Export controls not usable');
   await assert(`Array.from(document.querySelectorAll('[data-module-export="${module}"]')).every(b=>b.getBoundingClientRect().right<=innerWidth)`,'Export controls overflow');
   await assert(`(()=>{const groups=[...document.querySelectorAll('.module-export-actions')];const withExports=document.documentElement.scrollWidth;groups.forEach(g=>g.style.display='none');const withoutExports=document.documentElement.scrollWidth;groups.forEach(g=>g.style.display='flex');return withExports<=Math.max(innerWidth,withoutExports);})()`,'Exports introduced horizontal overflow');
   await evaluate(`document.querySelector('[data-module-export="${module}"][onclick*="csv"]').click();document.querySelector('[data-module-export="${module}"][onclick*="xlsx"]').click()`);
   await assert(`csvName.startsWith('mica_${module}_') && writes.at(-1).name.startsWith('mica_${module}_')`,'Download not triggered');
  }
 }
 await assert('blobs.length===6 && writes.length===6','Six format/viewport downloads expected');
 await assert(`(async()=>{const csv=await blobs[0].text();return csv.includes('USD') && csv.includes('-121');})()`,'Currency or sign lost');
 await evaluate(`grids.comprobantes.setSearch('does-not-exist');render()`);
 await assert(`document.querySelector('[data-module-export="comprobantes"]').disabled`,'Filtered empty state not disabled');
 await evaluate(`store.contextState='SWITCHING';store.notify()`);
 await assert(`Array.from(document.querySelectorAll('[data-module-export]')).every(b=>b.disabled)`,'Switching did not disable export');
 await evaluate(`store.clearTenantState();store.activeOrganizationId='B';store.contextState='TENANT_READY';store.permissions.organization={loaded:true,orgId:'B',codes:['RECORD_VIEW','REPORT_EXPORT']};render()`);
 await assert(`Array.from(document.querySelectorAll('[data-module-export]')).every(b=>b.disabled)`,'Previous-company records available after switch');
 if(errors.length)throw Error(errors.join('; '));
 console.log('PASS: actual module UI, desktop/mobile, six downloads per viewport, control bounds, filter empty state, organization transition');
 }finally{ws?.close();browser.kill();server.close();}
