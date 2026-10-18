import {jest} from '@jest/globals';
import {OperationalGrid} from '../../src/js/core/operationalGrid.js';
import {classificationValues,semanticExtractors,canonicalCatalog,duplicateDefinitions} from '../../src/js/core/operationalSemantics.js';
import {moduleExportRecords,modulePrintHtml} from '../../src/js/core/moduleExports.js';
import {nativeModuleClick} from '../../src/js/components/operationalWorkspace.js';
import {mountContextInvalidation} from '../../src/js/core/multiTabContext.js';
const store=()=>({activeOrganizationId:'A',contextState:'TENANT_READY',sessionUserId:'user',contextGeneration:1,
 confirmedOrganizationName:'Peña & Sur',canOperationalAction:()=>true,hasCapability:()=>true,
 taxCategories:[{id:'c2',name:'Zeta'},{id:'c1',name:'Combustible y Lubricantes'}],
 economicActivities:[{id:'a2',name:'Ventas',arca_code:'2'},{id:'a1',name:'Agrícola',arca_code:'1'}]});
const rows=()=>[{id:'z',organization_id:'A',fecha:'20/10/2026',category_id:'c2',activity_id:'a2',confirmada:false,total:10},
 {id:'a',organization_id:'A',fecha:'02/10/2026',category_id:'c1',activity_id:'a1',confirmada:true,total:-12},
 {id:'none',organization_id:'A',fecha:'01/09/2026',confirmada:false,total:0}];
test.each(['categoria','actividad','estado'])('%s sorts semantic labels ascending and descending without source mutation',key=>{
 const s=store(),source=rows(),original=JSON.stringify(source),grid=new OperationalGrid({moduleId:'comprobantes'});
 grid.toggleSort(key);const asc=grid.filterAndSort(source,semanticExtractors(s));
 expect(asc.map(r=>classificationValues(s,r)[key])).toEqual(asc.map(r=>classificationValues(s,r)[key]).sort((a,b)=>a.localeCompare(b,'es',{sensitivity:'base'})));
 grid.toggleSort(key);expect(grid.filterAndSort(source,semanticExtractors(s)).map(r=>classificationValues(s,r)[key])).toEqual(asc.map(r=>classificationValues(s,r)[key]).reverse());
 expect(JSON.stringify(source)).toBe(original);
});
test('sorting spans filtered full dataset before pagination and is stable for ties',()=>{
 const s=store(),grid=new OperationalGrid({moduleId:'comprobantes'});
 s.items=Array.from({length:120},(_,i)=>({...rows()[i%2],id:String(i)}));
 grid.setPeriod('2026-10');grid.toggleSort('categoria');
 const exported=moduleExportRecords(s,'comprobantes',grid);
 expect(exported).toHaveLength(120);expect(exported[0].id).toBe('1');expect(exported[59].id).toBe('119');expect(exported[60].id).toBe('0');
});
test('date sorting parses DD/MM/YYYY and ISO consistently',()=>{
 const grid=new OperationalGrid({moduleId:'comprobantes'});grid.toggleSort('fecha','date');
 expect(grid.filterAndSort(rows()).map(r=>r.id)).toEqual(['none','a','z']);
});
test.each(['comprobantes','percepciones','bancos','sueldos'])('%s PDF snapshot includes company, count and escaped values',module=>{
 const s=store(),records=[{...rows()[1],razonSocial:'<script>bad</script>',moneda:'USD',tipoCambio:1000,periodo:'2026-10',monto:-12}];
 const report=modulePrintHtml(s,module,null,records,new Date('2026-10-16T10:00:00Z'));
 expect(report).toContain('Peña &amp; Sur');expect(report).toContain('1 registros');expect(report).toContain('2026-10-16T10:00:00.000Z');expect(report).not.toContain('<script>');expect(report).not.toContain('organization_id');
});
test('PDF visible columns, currency context and CSV dataset scope',()=>{
 const s=store(),grid=new OperationalGrid({moduleId:'comprobantes',defaultColumns:['fecha','total']});
 s.items=rows();grid.setPeriod('2026-10');const records=moduleExportRecords(s,'comprobantes',grid);
 const report=modulePrintHtml(s,'comprobantes',grid,records);
 expect(report).toContain('2 registros');expect(report).toContain('<th>Total</th>');expect(report).toContain('<th>Moneda</th>');expect(report).not.toContain('<th>CUIT</th>');expect(report).not.toContain('01/09/2026');
});
test('canonical category identity dedupes assignments, never merges distinct definitions',()=>{
 const input=[{id:'a',name:'Honorarios Profesionales',category_type:'EXPENSE'},{id:'a',name:'Honorarios Profesionales',category_type:'EXPENSE'},
 {id:'b',name:'Honorarios Profesionales',category_type:'EXPENSE'},{id:'c',name:'Honorarios Profesionales',category_type:'INCOME'}];
 expect(canonicalCatalog(input)).toHaveLength(3);expect(duplicateDefinitions(input)).toEqual([['a','b']]);
});
test.each([{button:1},{button:0,ctrlKey:true},{button:0,metaKey:true},{button:0,shiftKey:true}])('native modified clicks stay native: %p',keys=>{
 const event={...keys,preventDefault:jest.fn()},navigate=jest.fn();nativeModuleClick(event,navigate,'tab-bancos');expect(navigate).not.toHaveBeenCalled();expect(event.preventDefault).not.toHaveBeenCalled();
});
test('plain click navigates SPA',()=>{const event={button:0,preventDefault:jest.fn()},navigate=jest.fn();nativeModuleClick(event,navigate,'tab-bancos');expect(navigate).toHaveBeenCalledWith('tab-bancos');expect(event.preventDefault).toHaveBeenCalled();});
test('other-tab context change clears old data and advances stale-response generation',()=>{
 const s=store(),listeners=[];Object.assign(s,{items:rows(),clearTenantState(){this.items=[];},notify(){listeners.forEach(f=>f());},subscribe:f=>listeners.push(f)});
 const channel={postMessage:jest.fn(),close:jest.fn()};const events={};
 const controller=mountContextInvalidation(s,{BroadcastChannel:function(){return channel;},addEventListener:(type,fn)=>events[type]=fn});
 channel.onmessage({data:{user:'someone-else'}});expect(s.items).toHaveLength(3);
 channel.onmessage({data:{user:'user'}});expect(s.items).toEqual([]);expect(s.contextState).toBe('ERROR');expect(s.contextGeneration).toBe(2);
 s.contextState='SWITCHING';s.notify();expect(channel.postMessage).toHaveBeenCalledWith(expect.objectContaining({user:'user'}));controller.close();
});
test('storage fallback invalidates without copying another tab organization into this tab',()=>{
 const s=store(),events={};Object.assign(s,{clearTenantState:jest.fn(),notify:jest.fn(),subscribe:jest.fn()});
 mountContextInvalidation(s,{addEventListener:(type,fn)=>events[type]=fn});
 events.storage({key:'mica-context-invalidation',newValue:JSON.stringify({user:'user',organization_id:'B'})});
 expect(s.activeOrganizationId).toBe('A');expect(s.contextState).toBe('ERROR');expect(s.clearTenantState).toHaveBeenCalled();
});
