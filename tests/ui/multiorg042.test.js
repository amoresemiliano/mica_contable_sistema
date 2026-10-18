import { jest } from '@jest/globals';
import { mountOperationalOrgSelectors, renderOperationalHeader } from '../../src/js/components/operationalOrgSelector.js';
const rpc=jest.fn();
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js',()=>({supabase:{rpc}}));
const {AppStore}=await import('../../src/js/store.js');
const {persistenceService}=await import('../../src/js/core/services/persistenceService.js');
let current,store,allowed;
const targets=['A','B'].map(id=>({organization_id:id,organization_name:'Empresa '+id,context_type:'ORGANIZATION',role_template_id:'role-'+id,role_name:id==='A'?'Auditor':'Contador'}));
function server(name,args) {
 if(name==='get_my_operational_context')return Promise.resolve({data:{organization_id:current,organization_name:'Empresa '+current,profile_name:current==='A'?'Auditor':'Contador',can_switch_platform_context:false,can_switch_organization_context:true}});
 if(name==='list_my_organization_contexts')return {range:async offset=>({data:offset?[]:targets.filter(t=>allowed.includes(t.organization_id))})};
 if(name==='switch_my_organization_context') {
  if(!allowed.includes(args.p_org_id))return Promise.resolve({error:{message:'Active organization membership required'}});
  current=args.p_org_id;return Promise.resolve({error:null});
 }
 if(name==='get_my_effective_capabilities')return Promise.resolve({data:(current==='A'?['RECORD_VIEW','ORG_VIEW','CATALOG_ORG_VIEW']:['ORG_VIEW','CATALOG_ORG_VIEW']).map(code=>({code,scope:'ORGANIZATION',organization_id:current}))});
 if(name==='get_operational_snapshot')return Promise.resolve({data:{organization_id:current,categories:[{id:'cat-'+current,organization_id:current,name:current}],activities:[{id:'act-'+current,organization_id:current,name:current}],rates:[{id:'rate-'+current,organization_id:current,rate:3}]}});
 if(name==='get_operational_records_page')return Promise.resolve({data:args.p_after_id?[]:[{id:current+'-record',organization_id:current,record_type:'ARCA_RECIBIDOS'}]});
 if(name==='get_operational_financials_page')return Promise.resolve({data:args.p_after_id?[]:[{id:current+'-bank',organization_id:current,operation_type:'BANCO',normalized_payload:{monto:1}}]});
 throw Error('Unexpected RPC '+name);
}
beforeEach(()=>{current='A';allowed=['A','B'];rpc.mockReset().mockImplementation(server);store=new AppStore();});
test('normal multi-org session lists both memberships, changes role/permissions and clears every previous dataset',async()=>{
 await store.initializeSession({id:'member',email:'member@example.invalid'});
 expect(store.operationalOrgTargets).toEqual(targets);
 expect(store.canSwitchOperationalContext()).toBe(true);expect(store.canSelectPlatformContext()).toBe(false);
 store.manualMovements=store.ocrHistory=store.importIssues=[{organization_id:'A'}];
 expect(store.items[0].organization_id).toBe('A');
 await store.switchOrganizationContext('B');
 expect(store.activeOrganizationId).toBe('B');expect(store.effectiveProfileName).toBe('Contador');
 expect(store.canVisitModule('tab-conciliador')).toBe(false);expect(store.canVisitModule('tab-bancos')).toBe(false);
 expect(store.items).toEqual([]);expect(store.bankTransactions).toEqual([]);
 for(const key of ['manualMovements','ocrHistory','importIssues','perceptions','salariesList'])expect(store[key]).toEqual([]);
 for(const key of ['taxCategories','economicActivities','iibbRates'])expect(store[key].every(r=>r.organization_id==='B')).toBe(true);
 await store.loadOrganizations();expect(store.operationalOrgTargets).toEqual(targets);
 await store.switchOrganizationContext('A');expect(store.items[0].organization_id).toBe('A');expect(store.bankTransactions[0].organization_id).toBe('A');
 expect(store.effectiveProfileName).toBe('Auditor');
 expect(rpc.mock.calls.some(([name])=>name==='switch_superadmin_org_context'||name==='list_operational_org_targets')).toBe(false);
});
test('stale selector targets, inactive/removed membership, arbitrary UUID and Platform null are rejected by server',async()=>{
 await store.initializeSession({id:'member'});
 const original=store.items;allowed=['A'];
 for(const target of ['B','C',null])await expect(store.switchOrganizationContext(target)).rejects.toThrow('membership');
 expect(store.items).toBe(original);expect(store.activeOrganizationId).toBe('A');
});
test('late hydration after logout cannot restore another tenant',async()=>{
 await store.initializeSession({id:'member'});
 let release;
 rpc.mockImplementation((name,args)=>name==='get_operational_snapshot'?new Promise(resolve=>{release=resolve;}):server(name,args));
 const pending=store.switchOrganizationContext('B');
 while(!release)await new Promise(resolve=>setTimeout(resolve,0));
 store.endSession();release({data:{organization_id:'B',categories:[],activities:[],rates:[]}});await pending;
 expect(store.contextState).toBe('SIGNED_OUT');expect(store.items).toEqual([]);expect(store.canSwitchOperationalContext()).toBe(false);
});
test('failed hydration after a successful switch clears tenant permissions as well as data',async()=>{
 await store.initializeSession({id:'member'});
 rpc.mockImplementation((name,args)=>name==='get_operational_snapshot'?Promise.resolve({error:{message:'Snapshot failed'}}):server(name,args));
 await expect(store.switchOrganizationContext('B')).rejects.toThrow('Snapshot failed');
 expect(store.items).toEqual([]);expect(store.iibbRates).toEqual([]);expect(store.permissions.organization.loaded).toBe(false);
 expect(store.effectiveProfileName).toBe('');expect(store.contextState).toBe('ERROR');
});
class Element {
 constructor(id=''){this.id=id;this.children=[];}
 get firstChild(){return this.children[0];}
 append(...nodes){for(const node of nodes){if(node.parent)node.parent.children.splice(node.parent.children.indexOf(node),1);node.parent=this;this.children.push(node);}}
 setAttribute(){} replaceChildren(){this.children=[];}
}
test('real selectors never expose Platform to tenant and header updates without login/reload',async()=>{
 await store.initializeSession({id:'member',email:'member@example.invalid'});
 const sections=[new Element('tab-bancos'),new Element('tab-categorizacion')];
 const nodes={'user-header-info':{},'current-entity-label':{}};
 const doc={querySelectorAll:()=>sections,createElement:()=>new Element(),getElementById:id=>nodes[id]};
 mountOperationalOrgSelectors(store,doc);store.subscribe(()=>renderOperationalHeader(store,doc));
 const select=sections[0].children[0].children[0].children[0];
 expect(select.children.map(n=>n.value)).toEqual(['A','B']);
 select.value='B';await select.onchange();
 expect(nodes['user-header-info'].innerText).toBe('member@example.invalid · Empresa B · Contador');
 expect(sections[0].children[1].hidden).toBe(true);expect(sections[1].children[1].hidden).toBe(false);
});
test('single-org tenant uses a compact fixed name and never gains Platform authority',async()=>{
 allowed=['A'];await store.initializeSession({id:'member'});
 expect(store.canSwitchOperationalContext()).toBe(false);expect(store.getActiveOrganizationName()).toBe('Empresa A');
 expect(store.canSelectPlatformContext()).toBe(false);
});
test('membership list validates server shape and never accepts a Platform placeholder',async()=>{
 rpc.mockReturnValue({range:async()=>({data:[{organization_id:null,organization_name:'Platform',context_type:'PLATFORM'}]})});
 await expect(persistenceService.listMyOrganizationContexts()).rejects.toThrow('Invalid membership');
});
