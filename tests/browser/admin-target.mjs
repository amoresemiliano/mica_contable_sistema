// Local browser check with explicit fixture service. No Supabase connection or SQL.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const root=process.cwd(),port=18959,debugPort=18960;
const uiSource=fs.readFileSync('src/js/ui.js','utf8');
const indexSource=fs.readFileSync('index.html','utf8');
const cardStart=indexSource.indexOf('<section id="tab-categorizacion"');
const cards=indexSource.slice(cardStart,indexSource.indexOf('</section>',cardStart)+10);
const methods=uiSource.slice(uiSource.indexOf('    static renderRecordActionToolbar('),uiSource.indexOf('    static renderImportIssues()'));
const handlers=["toggleMasterTaxCategories","toggleMasterEconomicActivities","toggleTaxCategoryRowSelection","toggleEconomicActivityRowSelection","toggleSingleTaxCategoryAssignment","toggleSingleEconomicActivityAssignment","actionToggleTaxCategories","actionDeleteTaxCategories","actionAssignEconomicActivities","actionUnassignEconomicActivities","handleCatalogTargetChange"].map(name=>{const start=uiSource.indexOf('window.'+name+' =');return uiSource.slice(start,uiSource.indexOf('\n};',start)+3);}).join('\n');
const html=`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>MICA · Configuración · Fixture 039e</title>
<link rel="stylesheet" href="/src/css/styles.css"><link rel="stylesheet" href="/src/css/administration.css">
<style>body{display:block;padding:32px;background:var(--bg-main)}main{max-width:1280px;margin:auto}h1{margin-bottom:24px}@media(max-width:640px){body{padding:16px}}</style>
<main>${cards}<h1>Configuración</h1><div id="mica-administration"></div></main>
<script type="module">
import {OperationalGrid} from '/src/js/core/operationalGrid.js';
import {createAdministrationView} from '/src/js/components/administration.js';
import {MICA_PERMISSION_CATALOG as capabilities,MICA_PRESET_DEFINITIONS,presetCapabilities} from '/src/js/core/micaPermissionContract.js';
const presets=Object.entries(MICA_PRESET_DEFINITIONS).filter(([code])=>code!=='ROOT_TECHNICAL_MICA').map(([id,p])=>({...p,id,name:p.label,is_active:true,organization_id:null,recipients:1,capabilities:presetCapabilities(id,p.scope),bridge:p.scope==='PLATFORM'?presetCapabilities(id,'ORGANIZATION'):[]}));
const data={rights:{organizations:true,create_organization:true,update_organization:true,archive_organization:true,users:true,global_users:true,presets:true,global_presets:true,assignments:true,memberships:true},
organizations:[{id:'norte',name:'Norte S.A.',tax_id:'30-12345678-9',is_active:true},{id:'sur',name:'Sur S.R.L.',tax_id:'30-98765432-1',is_active:true}],
users:[{id:'marianela',email:'marianela@example.invalid',is_active:true},{id:'ana',email:'ana@example.invalid',is_active:true},{id:'pendiente',email:'pendiente@example.invalid',is_active:false,pending:true}],
presets,capabilities:capabilities.filter(c=>c.assignable),platform_roles:[{user_profile_id:'marianela',role_template_id:'ACCOUNTING_SUPERADMIN',is_active:true}],
memberships:[{user_profile_id:'ana',organization_id:'norte',role_template_id:'MICA_ACCOUNTANT',is_active:true}],
scopes:[{user_profile_id:'marianela',organization_id:'norte',is_active:true}],overrides:[],contexts:[{user_profile_id:'marianela',organization_id:'norte'}]};
const store={sessionUserId:'root',contextGeneration:1,contextState:'PLATFORM_READY',activeOrganizationId:null,pendingOperations:0,subscribe(fn){this.listener=fn;},hasCapability:()=>true,isCatalogPlatformContext(){return this.contextState==='PLATFORM_READY';},canAssignCatalog:()=>true,canManageGlobalCatalog(){return this.contextState==='PLATFORM_READY';},canActivateCatalog:()=>true,canOperationalAction:()=>true,async switchOrganizationContext(){throw Error('Forbidden context switch');}};
window.saved=[];window.assignments=[];window.confirm=()=>true;window.alert=m=>{throw Error(m);};
const appStore=store;window.appStore=store;window.data=data;window.store=store;
store.catalogAssignmentTargets=[{organization_id:'norte',organization_name:'Norte S.A.'},{organization_id:'sur',organization_name:'Sur S.R.L.'}];
store.taxCategories=[{id:'category',name:'Real category',is_active:true,assignedOrganizationIds:[]}];
store.displayedEconomicActivities=[{id:'activity',name:'Real activity',arca_code:'123',is_active:true,assignedOrganizationIds:[]}];
store.economicActivities=store.displayedEconomicActivities;store.iibbRates=[];
const taxCategoriesGrid=new OperationalGrid({moduleId:'tax'}),economicActivitiesGrid=new OperationalGrid({moduleId:'activities'}),iibbRatesGrid=new OperationalGrid({moduleId:'iibb'});
const UIManager=class {static closeModal(){} ${methods} };window.UIManager=UIManager;
${handlers}
for(const method of ['assignTaxCategoryToOrg','unassignTaxCategoryFromOrg','bulkAssignTaxCategories','bulkUnassignTaxCategories','assignEconomicActivityToOrg','unassignEconomicActivityFromOrg','bulkAssignEconomicActivitiesToOrg','bulkUnassignEconomicActivitiesFromOrg'])store[method]=async(...args)=>{window.assignments.push([method,...args]);};
store.loadTaxCategories=store.loadEconomicActivities=store.loadIibbRates=async()=>UIManager.renderSettings();
window.view=
createAdministrationView(document.getElementById('mica-administration'),store,{read:async()=>data,apply:async(...args)=>{window.saved.push(args);return 'saved';},invitation:async(action)=>action==='list'?[]:{}});await window.view.load({section:'Categorización'});
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
    '--remote-debugging-port='+debugPort,'--user-data-dir='+path.join(root,'scratch/target-browser-profile'),
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
    await assert("document.querySelector('#mica-admin-content').textContent.includes('Seleccioná una empresa para gestionar')",'No empty state');
    await assert("!!document.querySelector('#mica-categorizacion-subview #table-tax-categories-body') && document.querySelector('#table-tax-categories-body').textContent.includes('Real category')",'Actual index categories missing');
    await assert("!document.querySelector('#table-tax-categories-body button[onclick*=toggleSingle]')",'Assignments enabled without target');
    const choose=async org=>evaluate("document.querySelector('[name=administration-target]').value="+JSON.stringify(org)+";document.querySelector('[name=administration-target]').onchange()");
    await choose('sur');
    await assert("window.store.activeOrganizationId===null&&window.store.contextState==='PLATFORM_READY'",'Platform became tenant');
    await assert("document.querySelector('#target-org-tax-categories-container').style.display==='none'",'Duplicate target');
    await evaluate("window.toggleSingleTaxCategoryAssignment('category');");
    await evaluate("window.toggleMasterTaxCategories(true);window.actionToggleTaxCategories()");
    await evaluate("window.toggleMasterTaxCategories(true);window.actionDeleteTaxCategories()");
    await evaluate("window.store.taxCategories[0].assignedOrganizationIds=['sur'];window.toggleSingleTaxCategoryAssignment('category')");
    await evaluate("[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==='Actividades').click()");
    await assert("document.querySelector('#mica-categorizacion-subview #table-economic-activities-body').textContent.includes('Real activity')",'Actual activities missing');
    await evaluate("window.toggleSingleEconomicActivityAssignment('activity')");
    await evaluate("window.toggleMasterEconomicActivities(true);window.actionAssignEconomicActivities()");
    await evaluate("window.toggleMasterEconomicActivities(true);window.actionUnassignEconomicActivities()");
    await evaluate("window.store.displayedEconomicActivities[0].assignedOrganizationIds=['sur'];window.toggleSingleEconomicActivityAssignment('activity')");
    await assert("window.assignments.length===8&&window.assignments.every(call=>call[2]==='sur')",'Single/bulk target forwarding');
    for(const label of ['Impuestos','Categorías','Actividades','Categorías']) {
        await evaluate("[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==="+JSON.stringify(label)+").click()");
        await assert("document.querySelector('[name=administration-target]').value==='sur'",'Target lost');
        await assert("document.querySelector('#mica-categorizacion-subview').textContent.trim().length>20",'Blank subview '+label);
        await assert("[...document.querySelector('#mica-categorizacion-subview').children].some(n=>n.getBoundingClientRect().height>0)",'Content invisible '+label);
    }
    for(const label of ['Empresas','Usuarios','Categorización']) {
        await evaluate("[...document.querySelectorAll('[role=tab]')].find(n=>n.textContent==="+JSON.stringify(label)+").click()");
        await assert("document.querySelector('[name=administration-target]').value==='sur'&&window.store.activeOrganizationId===null",'Target/context changed');
    }
    await choose('norte');
    await assert("document.querySelector('#mica-categorizacion-subview #table-tax-categories-body').textContent.includes('Real category')",'Target change emptied cards');
    await evaluate("window.store.contextState='TENANT_READY';window.store.activeOrganizationId='sur';window.store.contextGeneration++;window.view.load()");
    await assert("!document.querySelector('[name=administration-target]')&&document.querySelector('#mica-categorizacion-subview #table-tax-categories-body')",'Tenant target duplication/content');
    await evaluate("[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==='Impuestos').click()");
    await assert("document.querySelector('#mica-categorizacion-subview #table-iibb-rates-body')&&document.querySelector('#mica-categorizacion-subview #table-iva-rates-body')",'Tenant taxes missing');
    for(const width of [1440,390,320]) {
        await cdp('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<640});
        await assert('document.documentElement.scrollWidth<=window.innerWidth','Mobile overflow '+width);
    }
    if(errors.length)throw Error(errors.join(', '));
    console.log('PASS: real index.html cards and production catalog handlers; visible content, all 8 single/bulk assignment targets, Platform preserved, target changes, primary/subtab roundtrips, tenant context change, IIBB gap/IVA reference, mobile overflow. Local fixture only; no SQL.');
    await cdp('Browser.close').catch(()=>{});
} finally {ws?.close();browser.kill();server.close();}
