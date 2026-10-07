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
import {createAdministrationService} from '/src/js/core/services/administrationService.js';
import {MICA_PERMISSION_CATALOG as capabilities,MICA_PRESET_DEFINITIONS,presetCapabilities} from '/src/js/core/micaPermissionContract.js';
const presets=Object.entries(MICA_PRESET_DEFINITIONS).filter(([code])=>code!=='ROOT_TECHNICAL_MICA').map(([id,p])=>({...p,id,code:id,name:p.label,is_active:true,organization_id:null,recipients:1,capabilities:presetCapabilities(id,p.scope),bridge:p.scope==='PLATFORM'?presetCapabilities(id,'ORGANIZATION'):[]}));
presets.push({id:'operativa',code:'ADMINISTRACION_OPERATIVA_MICA',name:'Administración operativa',scope:'PLATFORM',is_active:true,capabilities:[],bridge:[]});
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
window.catalogLoads=0;
store.loadTaxCategories=store.loadEconomicActivities=async()=>{window.catalogLoads++;UIManager.renderSettings();};
store.loadIibbRates=async()=>{store.iibbRates=window.rateDefinitions.filter(r=>(r.assignedOrganizations||[]).includes(store.activeOrganizationId)).map(r=>({...r,rate_percent:r.rate}));UIManager.renderSettings();};
window.rpcCalls=[];
window.companyUsers=[];window.accessWrites=[];window.rateWrites=[];
window.rateDefinitions=[{id:'rate1',activity_id:'activity',activity_name:'Real activity',jurisdiction:'CABA',rate:3,valid_from:'2026-01-01',valid_to:null,is_active:true,assigned:false}];
const service=createAdministrationService({rpc:async(name,args)=>{
window.rpcCalls.push([name,args]);
if((name==='mica_admin_read'||name==='mica_invitation')&&args.p_org&&args.p_org!==store.activeOrganizationId)return {error:{message:'Tenant administration denied: confirmed context and action required'}};
if(name==='mica_platform_access') {
 if(store.contextState!=='PLATFORM_READY'||(args.p_org&&!['sur','norte'].includes(args.p_org)))return {error:{message:'Organization outside explicit Platform scope'}};
 const roles=presets.filter(p=>p.scope==='ORGANIZATION'&&p.is_active);
 if(args.p_action==='options')return {data:{organizations:data.organizations.map(o=>({...o,roles})),platform_roles:presets.filter(p=>p.id==='operativa')}};
 if(args.p_action==='list')return {data:{users:window.companyUsers.filter(u=>u.organization_id===args.p_org),invitations:[]}};
 const role=presets.find(p=>p.id===args.p_data.role_template_id);
 if(args.p_action==='save'&&(!role||role.scope!==(args.p_org?'ORGANIZATION':'PLATFORM')||role.code==='ACCOUNTING_SUPERADMIN'))return {error:{message:'Incompatible or protected role'}};
 window.accessWrites.push(args);
 if(args.p_action==='save'&&args.p_data.email==='ana@example.invalid') {
 window.companyUsers.push({id:'ana',name:'Ana',email:'ana@example.invalid',organization_id:args.p_org,role_template_id:role.id,role_name:role.name,member_active:true,is_active:true});
 data.memberships.push({user_profile_id:'ana',organization_id:args.p_org,role_template_id:role.id,is_active:true});
 }
 return {data:{status:args.p_data.email==='ana@example.invalid'?'ASSIGNED':'PENDING_AUTHENTICATION'}};
}
if(name==='mica_platform_iibb') {
 if(store.contextState!=='PLATFORM_READY')return {error:{message:'Confirmed Platform administration authority required'}};
 if(args.p_action==='list')return {data:{definitions:window.rateDefinitions.map(r=>({...r,assigned:(r.assignedOrganizations||[]).includes(args.p_org)})),organizations:data.organizations,activities:[{id:'activity',name:'Real activity'}]}};
 window.rateWrites.push(args);
 const rate=window.rateDefinitions.find(r=>r.id===args.p_data.id);
 if(args.p_action==='assign')rate.assignedOrganizations=[...new Set([...(rate.assignedOrganizations||[]),args.p_org])];
 if(args.p_action==='unassign')rate.assignedOrganizations=(rate.assignedOrganizations||[]).filter(org=>org!==args.p_org);
 if(args.p_action==='set_active')rate.is_active=args.p_data.is_active;
 if(args.p_action==='create')window.rateDefinitions.push({...args.p_data,id:'created-rate',activity_name:'Real activity',rate:Number(args.p_data.rate),is_active:true,assigned:false});
 return {data:{id:rate?.id||'created-rate'}};
}
return {data:name==='mica_admin_read'?data:name==='mica_invitation'?[]:{}};
}});
window.view=createAdministrationView(document.getElementById('mica-administration'),store,service);await window.view.load({section:'Categorización'});
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
    await assert('window.catalogLoads===1','Target reloaded catalog instead of local assignment state');
    await assert("window.rpcCalls.length===2&&window.rpcCalls.every(call=>call[1].p_org===null)",'Target invoked administration/invitation RPC');
    await assert("!document.querySelector('#mica-administration').textContent.includes('administration denied')",'Denied screen');
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
    await choose('sur');
    await evaluate("[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==='Impuestos').click()");
    for(let i=0;i<20&&!await evaluate("!!document.querySelector('[data-definition-id=rate1]')");i++)await new Promise(r=>setTimeout(r,50));
    await assert("document.querySelector('[data-definition-id=rate1]').textContent.includes('CABA')",'Global IIBB version missing');
    await evaluate("[...document.querySelector('[data-definition-id=rate1]').querySelectorAll('button')].find(n=>n.textContent==='Asignar').click()");
    await new Promise(r=>setTimeout(r,100));
    await evaluate("[...document.querySelector('[data-definition-id=rate1]').querySelectorAll('button')].find(n=>n.textContent==='Quitar asignación').click()");
    await new Promise(r=>setTimeout(r,100));
    await assert("window.rateWrites.length===2&&window.rateWrites.every(c=>c.p_org==='sur')&&window.store.activeOrganizationId===null",'Rate target forwarding/context');
    await evaluate("[...document.querySelectorAll('button')].find(n=>n.textContent==='+ Nueva definición IIBB').click()");
    await evaluate("document.querySelector('[name=jurisdiction]').value='ARBA';document.querySelector('[name=rate]').value='1.25';document.querySelector('[name=valid_from]').value='2026-01-01';document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    await new Promise(r=>setTimeout(r,100));
    await assert("window.rateWrites[2].p_action==='create'&&window.rateWrites[2].p_org===null&&document.querySelector('[data-definition-id=created-rate]').textContent.includes('ARBA')",'Global definition creation');
    await evaluate("document.querySelector('dialog header button').click()");
    await evaluate("[...document.querySelector('[data-definition-id=created-rate]').querySelectorAll('button')].find(n=>n.textContent==='Asignar').click()");
    await new Promise(r=>setTimeout(r,100));
    await evaluate("[...document.querySelectorAll('[role=tab]')].find(n=>n.textContent==='Usuarios').click()");
    await new Promise(r=>setTimeout(r,100));
    await assert("document.querySelector('.mica-company-users').textContent.includes('No hay usuarios asignados a esta empresa.')",'Missing useful company users empty state');
    await evaluate("[...document.querySelectorAll('button')].find(n=>n.textContent==='+ Invitar / asignar usuario').click()");
    await new Promise(r=>setTimeout(r,100));
    await assert("document.querySelector('[name=access-type]').value==='ORGANIZATION'&&document.querySelector('[name=access-company]').value==='sur'",'Company invitation default');
    await evaluate("document.querySelector('[name=access-company]').value='norte';document.querySelector('[name=access-company]').onchange()");
    await assert("document.querySelector('[name=access-company]').value==='norte'&&document.querySelector('[name=access-role]').options.length>0",'Authorized organization selector');
    await evaluate("document.querySelector('[name=access-company]').value='sur';document.querySelector('[name=access-company]').onchange()");
    await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await assert("document.documentElement.scrollWidth<=innerWidth&&document.querySelector('dialog').getBoundingClientRect().right<=innerWidth",'Access editor mobile overflow');
    await assert("[...document.querySelector('[name=access-role]').options].every(o=>window.data.presets.find(p=>p.id===o.value).scope==='ORGANIZATION')",'Role scope filtering');
    await evaluate("document.querySelector('[name=email]').value='ana@example.invalid';document.querySelector('[name=access-role]').value='MICA_ACCOUNTANT';document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    await new Promise(r=>setTimeout(r,100));
    await assert("window.companyUsers.length===1&&window.accessWrites[0].p_org==='sur'&&document.querySelector('.mica-company-users').textContent.includes('ana@example.invalid')",'Existing user assignment');
    await evaluate("[...document.querySelectorAll('button')].find(n=>n.textContent==='+ Invitar / asignar usuario').click()");
    await new Promise(r=>setTimeout(r,100));
    await evaluate("document.querySelector('[name=email]').value='new-company@example.invalid';document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    await new Promise(r=>setTimeout(r,100));
    await assert("window.accessWrites[1].p_org==='sur'&&window.accessWrites[1].p_data.email==='new-company@example.invalid'&&window.companyUsers.length===1",'New company invitation created an identity or lost target');
    await evaluate("[...document.querySelectorAll('button')].find(n=>n.textContent==='+ Invitar / asignar usuario').click()");
    await new Promise(r=>setTimeout(r,100));
    await evaluate("document.querySelector('[name=access-type]').value='PLATFORM';document.querySelector('[name=access-type]').onchange()");
    await assert("[...document.querySelector('[name=access-role]').options].every(o=>o.value==='operativa')&&document.querySelector('[name=access-company]').closest('label').hidden",'Protected/platform role filtering');
    await evaluate("document.querySelector('[name=email]').value='new@example.invalid';document.querySelector('dialog form').dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}))");
    await new Promise(r=>setTimeout(r,100));
    await assert("window.accessWrites[2].p_org===null&&window.accessWrites[2].p_data.role_template_id==='operativa'",'Platform invitation target');
    await evaluate("[...document.querySelectorAll('button')].find(n=>n.textContent==='Permisos avanzados').click()");
    await assert("[...document.querySelector('.mica-admin-advanced-nav').children].map(n=>n.textContent).join(',')==='Usuarios,Roles,Accesos'",'Human advanced navigation');
    await evaluate("[...document.querySelector('.mica-admin-advanced-nav').children].find(n=>n.textContent==='Roles').click()");
    await assert("!document.querySelector('dialog')",'Role screen auto-opens giant form');
    await evaluate("[...document.querySelector('.mica-admin-advanced-nav').children].find(n=>n.textContent==='Accesos').click();[...document.querySelector('.mica-admin-advanced').querySelectorAll('button')].find(n=>n.textContent==='Ver detalle').click()");
    await assert("[...document.querySelectorAll('dialog details')].some(n=>n.querySelector('summary').textContent==='Excepciones avanzadas'&&!n.open)",'Overrides not collapsed');
    await assert("!document.querySelector('dialog').textContent.includes('Las membresías requieren el contexto operativo')",'Platform access still demands tenant context');
    await evaluate("document.querySelector('dialog header button').click()");
    await evaluate("[...document.querySelector('.mica-admin-advanced').querySelectorAll('tr')].find(n=>n.textContent.includes('ana@example.invalid')).querySelector('button').click()");
    await assert("document.querySelector('dialog').textContent.includes('Cambiar rol')&&document.querySelector('dialog').textContent.includes('Quitar acceso')",'Company access actions missing');
    await evaluate("[...document.querySelector('dialog').querySelectorAll('button')].find(n=>n.textContent==='Cambiar rol').click()");
    await new Promise(r=>setTimeout(r,100));
    await assert("document.querySelector('[name=access-type]').value==='ORGANIZATION'&&document.querySelector('[name=access-company]').value==='norte'&&document.querySelector('[name=access-role]').value==='MICA_ACCOUNTANT'",'Role change confused existing access company with management target');
    await evaluate("document.querySelector('dialog header button').click()");
    await evaluate("[...document.querySelectorAll('[role=tab]')].find(n=>n.textContent==='Empresas').click();document.querySelector('[aria-label=\"Ver detalle de Sur S.R.L.\"]').click()");
    await evaluate("const sidebar=document.createElement('aside');sidebar.id='fixture-sidebar';sidebar.style.cssText='position:fixed;left:0;top:0;width:240px;height:100vh;z-index:2147483647;background:#eee';document.body.append(sidebar)");
    for(const width of [1440,390]) {
        await cdp('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<640});
        await assert("document.querySelector('dialog').matches(':modal')&&document.querySelector('dialog').getBoundingClientRect().left>=0&&document.querySelector('dialog').getBoundingClientRect().right<=innerWidth",'Company drawer viewport '+width);
        await assert("[...document.querySelectorAll('dialog dt')].map(n=>n.textContent).join(',')==='Empresa,Razón Social,CUIT,Teléfono,Email,Contacto,Website,Domicilio,Estado'",'Company fields');
        await assert("document.documentElement.scrollWidth<=innerWidth",'Company drawer overflow '+width);
        await assert("(()=>{const r=document.querySelector('dialog').getBoundingClientRect();return !!document.elementFromPoint(r.left+20,r.top+20).closest('dialog')})()",'Drawer behind sidebar '+width);
    }
    await evaluate("document.querySelector('dialog header button').click();[...document.querySelectorAll('[role=tab]')].find(n=>n.textContent==='Categorización').click();[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==='Categorías').click()");
    await evaluate("window.store.contextState='TENANT_READY';window.store.activeOrganizationId='sur';window.store.contextGeneration++;window.view.load()");
    await assert("!document.querySelector('[name=administration-target]')&&document.querySelector('#mica-categorizacion-subview #table-tax-categories-body')",'Tenant target duplication/content');
    await evaluate("[...document.querySelectorAll('.mica-admin-subnav-btn')].find(n=>n.textContent==='Impuestos').click()");
    await new Promise(r=>setTimeout(r,100));
    await assert("document.querySelector('#mica-categorizacion-subview #table-iibb-rates-body')&&document.querySelector('#mica-categorizacion-subview #table-iva-rates-body')",'Tenant taxes missing');
    await assert("document.querySelector('#table-iibb-rates-body').textContent.includes('ARBA')&&!document.querySelector('#table-iibb-rates-body').textContent.includes('CABA')",'Tenant configuration not limited to explicit assignments');
    await cdp('Emulation.setTimezoneOverride',{timezoneId:'America/Argentina/Buenos_Aires'});
    await evaluate("window.store.iibbRates[0].jurisdiction='<img src=x onerror=alert(1)>';window.UIManager.renderSettings()");
    await assert("document.querySelector('#table-iibb-rates-body').textContent.includes('01/01/2026')&&!document.querySelector('#table-iibb-rates-body img')",'IIBB dates shifted or label executed HTML');
    await assert("!document.querySelector('#card-iibb-rates button')&&document.querySelector('#toolbar-iibb-rates').hidden",'Tenant global rate creation/editing exposed');
    for(const width of [1440,390,320]) {
        await cdp('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:width<640});
        await assert('document.documentElement.scrollWidth<=window.innerWidth','Mobile overflow '+width);
    }
    if(errors.length)throw Error(errors.join(', '));
    console.log('PASS: real cards/catalog handlers, 8 assignment actions, Platform preserved, global IIBB creation/assignment/unassignment, company/new/existing/Platform access, role filtering, Usuarios/Roles/Accesos, native drawer above sidebar at 1440/390px, tenant read-only rates, mobile overflow. Local RPC fixtures only; no SQL.');
    await cdp('Browser.close').catch(()=>{});
} finally {ws?.close();browser.kill();server.close();}
