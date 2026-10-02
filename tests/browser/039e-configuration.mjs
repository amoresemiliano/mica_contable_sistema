// Local browser check with explicit fixture service. No Supabase connection or SQL.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=process.cwd(),port=18939,debugPort=18940;
const html=`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>MICA · Configuración · Fixture 039e</title>
<link rel="stylesheet" href="/src/css/styles.css"><link rel="stylesheet" href="/src/css/administration.css">
<style>body{display:block;padding:32px;background:var(--bg-main)}main{max-width:1280px;margin:auto}h1{margin-bottom:24px}@media(max-width:640px){body{padding:16px}}</style>
<main><h1>Configuración</h1><div id="mica-administration"></div></main>
<script type="module">
import {createAdministrationView} from '/src/js/components/administration.js';
import {MICA_PERMISSION_CATALOG as capabilities,MICA_PRESET_DEFINITIONS,presetCapabilities} from '/src/js/core/micaPermissionContract.js';
const presets=Object.entries(MICA_PRESET_DEFINITIONS).filter(([code])=>code!=='ROOT_TECHNICAL_MICA').map(([id,p])=>({...p,id,name:p.label,is_active:true,organization_id:null,recipients:1,capabilities:presetCapabilities(id,p.scope),bridge:p.scope==='PLATFORM'?presetCapabilities(id,'ORGANIZATION'):[]}));
const data={rights:{organizations:true,create_organization:true,update_organization:true,archive_organization:true,users:true,global_users:true,presets:true,global_presets:true,assignments:true,memberships:true},
organizations:[{id:'norte',name:'Norte S.A.',tax_id:'30-12345678-9',is_active:true},{id:'sur',name:'Sur S.R.L.',tax_id:'30-98765432-1',is_active:true}],
users:[{id:'marianela',email:'marianela@example.invalid',is_active:true},{id:'ana',email:'ana@example.invalid',is_active:true},{id:'pendiente',email:'pendiente@example.invalid',is_active:false,pending:true}],
presets,capabilities:capabilities.filter(c=>c.assignable),platform_roles:[{user_profile_id:'marianela',role_template_id:'ACCOUNTING_SUPERADMIN',is_active:true}],
memberships:[{user_profile_id:'ana',organization_id:'norte',role_template_id:'MICA_ACCOUNTANT',is_active:true}],
scopes:[{user_profile_id:'marianela',organization_id:'norte',is_active:true}],overrides:[],contexts:[{user_profile_id:'marianela',organization_id:'norte'}]};
const store={sessionUserId:'root',contextGeneration:1,contextState:'TENANT_READY',activeOrganizationId:'norte',pendingOperations:0,subscribe(){}};
window.saved=[];
await createAdministrationView(document.getElementById('mica-administration'),store,{read:async()=>data,apply:async(...args)=>{window.saved.push(args);return 'saved';},invitation:async(action)=>action==='list'?[]:{}}).load();
window.ready=true;
</script></html>`;
const server=http.createServer((req,res)=>{
    if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end(html);}
    if(req.url==='/src/js/core/services/supabaseClient.js'){res.setHeader('Content-Type','application/javascript');return res.end('export const supabase={};');}
    const file=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));
    if(!file.startsWith(root+path.sep)||!fs.existsSync(file)){res.statusCode=404;return res.end();}
    res.setHeader('Content-Type',file.endsWith('.css')?'text/css':'application/javascript');res.end(fs.readFileSync(file));
});
await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
const browser=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',[
    '--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--disable-extensions',
    '--remote-debugging-port='+debugPort,'--user-data-dir='+path.join(root,'scratch/039e-browser-profile'),
    'http://127.0.0.1:'+port],{windowsHide:true,stdio:'ignore'});
let ws;
try {
    let pages;
    for(let i=0;i<40;i++){try{pages=await(await fetch('http://127.0.0.1:'+debugPort+'/json')).json();break;}catch{await new Promise(r=>setTimeout(r,250));}}
    if(!pages)throw Error('No local browser debugger');
    ws=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);
    await new Promise(r=>ws.addEventListener('open',r,{once:true}));
    let seq=0;const pending=new Map(),errors=[];
    ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}else if(m.method==='Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.text);});
    const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
    const evaluate=async(expression)=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
    await cdp('Runtime.enable');
    for(let i=0;i<40 && !await evaluate('!!window.ready');i++)await new Promise(r=>setTimeout(r,100));
    const assert=async(expression,message)=>{if(!await evaluate(expression))throw Error(message);};
    await assert('window.ready','Fixture did not load');
    await cdp('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
    await assert("document.querySelectorAll('[role=tabpanel]').length===1",'Multiple panels mounted');
    await evaluate("[...document.querySelectorAll('[role=tab]')].find(b=>b.textContent==='Usuarios').click()");
    await assert("document.querySelectorAll('tbody tr').length===4",'Users/invitations list missing');
    await evaluate("document.querySelector('[name=user-state]').value='pending';document.querySelector('[name=user-state]').dispatchEvent(new Event('change'))");
    await assert("document.querySelectorAll('.mica-admin-content tbody tr').length===2",'State filter failed');
    await evaluate("document.querySelector('[name=user-state]').value='';document.querySelector('[name=user-state]').dispatchEvent(new Event('change'))");
    await cdp('Page.enable');
    fs.writeFileSync('scratch/039e-users-desktop.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
    await evaluate("[...document.querySelectorAll('button')].find(b=>b.textContent==='Ver detalle').click()");
    await assert("document.querySelector('dialog').open && document.querySelector('dialog').contains(document.activeElement)",'Drawer/focus missing');
    await evaluate("document.querySelector('dialog button').focus();document.querySelector('dialog').dispatchEvent(new KeyboardEvent('keydown',{key:'Tab',shiftKey:true,bubbles:true,cancelable:true}))");
    await assert("document.activeElement.textContent==='Preset y permisos'",'Focus trap failed');
    fs.writeFileSync('scratch/039e-user-drawer.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
    await evaluate("document.querySelector('dialog').dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}))");
    await assert("!document.querySelector('dialog')",'Escape failed');
    await evaluate("[...document.querySelectorAll('[role=tab]')].find(b=>b.textContent==='Roles y permisos').click()");
    await evaluate("document.querySelector('.mica-preset-list button').click();document.querySelector('fieldset details').open=true");
    await assert("document.querySelectorAll('input[role=switch]').length>10",'Permission switches missing');
    fs.writeFileSync('scratch/039e-presets-desktop.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
    await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await assert('document.documentElement.scrollWidth<=window.innerWidth','Mobile overflow');
    await evaluate("[...document.querySelectorAll('[role=tab]')].find(b=>b.textContent==='Organizaciones').click();[...document.querySelectorAll('button')].find(b=>b.textContent==='Nueva organización').click()");
    await assert("Math.abs(document.querySelector('dialog').getBoundingClientRect().width-window.innerWidth)<2",'Mobile drawer width');
    fs.writeFileSync('scratch/039e-mobile-drawer.png',Buffer.from((await cdp('Page.captureScreenshot')).data,'base64'));
    await evaluate("document.querySelector('dialog [name=name]').value='Nueva org';document.querySelector('dialog form').requestSubmit()");
    for(let i=0;i<30 && !await evaluate('window.saved.length');i++)await new Promise(r=>setTimeout(r,50));
    await assert("window.saved[0][0]==='organization' && window.saved[0][1].name==='Nueva org'",'Organization form failed');
    if(errors.length)throw Error(errors.join(', '));
    console.log('Local Edge: one panel, user filter, drawer focus/Escape, permission switches, mobile width, organization submit PASS. Fixture service only; no LIVE access.');
    await cdp('Browser.close').catch(()=>{});
} finally {ws?.close();browser.kill();server.close();}
