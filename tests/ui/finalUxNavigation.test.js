import {jest} from '@jest/globals';
import {renderModuleAccess, moduleSectionId, canVisitModule} from '../../src/js/core/moduleAccess.js';

function fixture(hash='tab-conciliador') {
 const store={contextState:'LOADING',activeOrganizationId:null,hasCapability:()=>true};
 const sections=['tab-conciliador','tab-bancos','tab-configuracion','tab-access'].map(id=>{
  const classes=new Set(id==='tab-conciliador'?[]:['hidden']);
  return {id,classList:{add:c=>classes.add(c),contains:c=>classes.has(c),remove:c=>classes.delete(c)}};
 });
 const links=['tab-conciliador','tab-bancos','tab-categorizacion','tab-configuracion'].map(tab=>({dataset:{tab},setAttribute(){}}));
 const doc={body:{dataset:{}},defaultView:{location:{hash:'#'+hash}},
  querySelector:()=>sections.find(s=>!s.classList.contains('hidden')),
  querySelectorAll:q=>q==='.tab-content'?sections:links};
 const navigate=jest.fn(id=>{
  doc.body.dataset.activeModule=id;doc.defaultView.location.hash='#'+id;
  for(const section of sections)section.classList.add('hidden');
  sections.find(s=>s.id===moduleSectionId(id)).classList.remove('hidden');
 });
 const hydrate=()=>{store.contextState='PLATFORM_READY';render();};
 const render=()=>renderModuleAccess(store,doc,navigate);
 return {store,doc,links,navigate,render,hydrate};
}
test('platform hydration redirects once to categorization and remains stable over repeated notifications',()=>{
 const f=fixture();f.render();expect(f.navigate).not.toHaveBeenCalled();f.hydrate();
 for(let n=0;n<12;n++)f.render();
 expect(f.navigate.mock.calls).toEqual([['tab-categorizacion']]);
 expect(f.links.filter(l=>!l.hidden).map(l=>l.dataset.tab)).toEqual(['tab-categorizacion','tab-configuracion']);
});
test.each(['tab-configuracion','tab-categorizacion'])('manual selection and refresh preserve %s',route=>{
 const f=fixture(route);f.hydrate();for(let n=0;n<8;n++)f.render();
 expect(f.doc.body.dataset.activeModule).toBe(route);expect(f.navigate).toHaveBeenCalledTimes(1);
 f.navigate(route);f.render();expect(f.navigate).toHaveBeenCalledTimes(2);
});
test('managed company expands routes; returning to platform falls back exactly once',()=>{
 const f=fixture();f.hydrate();f.store.activeOrganizationId='A';f.store.contextState='TENANT_READY';
 f.doc.defaultView.location.hash='#tab-bancos';f.render();expect(canVisitModule(f.store,'tab-bancos')).toBe(true);
 expect(f.links.find(l=>l.dataset.tab==='tab-bancos').hidden).toBe(false);
 f.store.activeOrganizationId=null;f.store.contextState='PLATFORM_READY';f.render();f.render();
 expect(f.navigate.mock.calls).toEqual([['tab-categorizacion'],['tab-bancos'],['tab-categorizacion']]);
});
test('two independent tabs restore their own hashes without alternating shared administration routes',()=>{
 const first=fixture('tab-configuracion'),second=fixture('tab-bancos');first.hydrate();second.hydrate();
 for(let n=0;n<8;n++){first.render();second.render();}
 expect(first.navigate.mock.calls).toEqual([['tab-configuracion']]);
 expect(second.navigate.mock.calls).toEqual([['tab-categorizacion']]);
});
test('unavailable hash is repaired even when already displaying the fallback host',()=>{
 const f=fixture();f.hydrate();f.doc.defaultView.location.hash='#tab-bancos';f.render();f.render();
 expect(f.navigate.mock.calls).toEqual([['tab-categorizacion'],['tab-categorizacion']]);
 expect(f.doc.defaultView.location.hash).toBe('#tab-categorizacion');
});
