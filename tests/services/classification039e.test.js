import { jest } from '@jest/globals';
import { unresolvedPurchases, purchaseCategoryTotals } from '../../src/js/core/classification.js';
import { saveClassificationControl } from '../../src/js/components/classificationControl.js';
const rpc = jest.fn();
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({ supabase: { rpc } }));
const { AppStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
let records, financials, store, denied, failId, waitWrite;
function actor() {
    const s = new AppStore({ deferOperationalData: true });
    s.contextState = 'TENANT_READY'; s.activeOrganizationId = 'org'; s.contextGeneration = 1;
    s.permissions = {platform:{loaded:true,codes:[]},organization:{loaded:true,orgId:'org',codes:['RECORD_VIEW','RECORD_CLASSIFY','REPORT_VIEW']}};
    return s;
}
beforeEach(async () => {
    denied=false; failId=null; waitWrite=null;
    records = ['r1','r2'].map(id=>({id,organization_id:'org',record_type:'ARCA_RECIBIDOS',category_id:null,activity_id:null,
        normalized_payload:{category_id:'stale',activity_id:'stale',confirmada:true}}));
    financials = ['BANCO','SUELDO'].map((op,i)=>({id:'f'+i,organization_id:'org',operation_type:op,category_id:null,activity_id:null,
        normalized_payload:{category_id:'stale',activity_id:'stale',confirmada:true,monto:20}}));
    rpc.mockReset().mockImplementation(async (name, args) => {
        if(name.startsWith('update_')) {
            if(waitWrite) await waitWrite;
            if(denied) return {error:{message:'RECORD_CLASSIFY denied'}};
            const id=args.p_record_id||args.p_movement_id;
            if(id===failId) return {error:{message:'write failed'}};
            const row=[...records,...financials].find(r=>r.id===id);
            row.category_id=args.p_category_id;row.activity_id=args.p_activity_id;
            return {data:null};
        }
        if(name==='get_my_operational_context')return {data:{organization_id:'org',organization_name:'Org',profile_name:'Actor',profile_scope:'PLATFORM'}};
        if(name==='get_operational_records_page'||name==='get_operational_financials_page')
            return {data:structuredClone((name.includes('records')?records:financials).filter(r=>!args.p_after_id||r.id>args.p_after_id))};
        throw Error('Unexpected RPC '+name);
    });
    store=actor(); await store.ensureOperationalData('tab-client-dashboard');
    expect(store.operationalDataStatus('tab-client-dashboard').error).toBe('');rpc.mockClear();
});
test.each([['records','r1','updateCategory','updateActivity'],['financials','f0','updateBankCategory','updateBankActivity']])(
    '%s saves both fields and a fresh store rehydrates the server classification',async(family,id,category,activity)=>{
        await store[category](id,'cat'); await store[activity](id,'act');
        expect(rpc).toHaveBeenCalledWith(family==='records'?'update_record_classification':'update_movement_classification',
            expect.objectContaining({p_category_id:'cat',p_activity_id:'act'}));
        const fresh=actor(); await fresh.ensureOperationalData('tab-client-dashboard');
        const rows=family==='records'?fresh.items:fresh.bankTransactions;
        expect(rows.find(r=>r.id===id)).toMatchObject({category_id:'cat',activity_id:'act',confirmada:true});
        if(family==='records')expect(unresolvedPurchases(fresh.items)).toBe(1);
    });
test('all adapters ignore payload classifications, including perceptions and salaries',async()=>{
    expect(store.bankTransactions[0]).toMatchObject({category_id:null,activity_id:null,confirmada:false});
    expect(store.salariesList[0]).toMatchObject({category_id:null,activity_id:null,confirmada:false});
    const [perception]=await persistenceService.loadActivePerceptions([{...records[0],record_type:'PERCEPCION',category_id:'cat',activity_id:'act'}]);
    expect(perception).toMatchObject({category_id:'cat',activity_id:'act',confirmada:true});
});
test('report expense breakdown uses persisted IDs and current catalog names, never legacy labels',()=>{
    const rows=[{tipo:'recibido',category_id:'cat',categoria:'Old label',total:100},
        {tipo:'recibido',category_id:null,categoria:'Fake saved label',total:25}];
    expect(purchaseCategoryTotals(rows,[{id:'cat',name:'Servicios'}])).toEqual([
        {id:'cat',label:'Servicios',amount:100},{id:null,label:'Sin Categorizar',amount:25}]);
});
test('no optimistic success; report updates from reread after server acknowledgement',async()=>{
    let release;waitWrite=new Promise(resolve=>release=resolve);
    const save=store.updateCategory('r1','cat'); await Promise.resolve();
    expect(store.items[0].category_id).toBeNull();expect(unresolvedPurchases(store.items)).toBe(2);expect(store.pendingOperations).toBe(1);
    release();await save;expect(unresolvedPurchases(store.items)).toBe(1);expect(store.pendingOperations).toBe(0);
});
test('concurrent category/activity edits serialize and preserve both fields',async()=>{
    await Promise.all([store.updateCategory('r1','cat'),store.updateActivity('r1','act')]);
    expect(records[0]).toMatchObject({category_id:'cat',activity_id:'act'});
});
test('bulk readback matches report; partial failure does not mark failed rows as saved',async()=>{
    failId='r2';await expect(store.saveClassification('records',['r1','r2'],{category_id:'cat'})).rejects.toThrow('write failed');
    expect(store.items.find(r=>r.id==='r1').category_id).toBe('cat');expect(store.items.find(r=>r.id==='r2').category_id).toBeNull();expect(unresolvedPurchases(store.items)).toBe(1);
    failId=null;await store.saveClassification('records',['r1','r2'],{category_id:'cat',activity_id:'act'});
    expect(unresolvedPurchases(store.items)).toBe(0);
});
test('backend DENY is visible and leaves the canonical record unchanged',async()=>{
    denied=true;await expect(store.updateCategory('r1','cat')).rejects.toThrow('RECORD_CLASSIFY');
    expect(store.items[0].category_id).toBeNull();expect(store.pendingOperations).toBe(0);
    store.permissions.organization.codes=['RECORD_VIEW'];rpc.mockClear();
    await expect(store.updateBankActivity('f0','act')).rejects.toThrow('permiso');expect(rpc).not.toHaveBeenCalled();
});
test('context change stops remaining bulk writes and never applies old responses to new tenant',async()=>{
    let release;waitWrite=new Promise(resolve=>release=resolve);
    const save=store.saveClassification('records',['r1','r2'],{category_id:'cat'}); await Promise.resolve();await Promise.resolve();
    store.contextGeneration++;store.activeOrganizationId='other';store.items=[];release();
    await expect(save).rejects.toThrow('contexto');expect(store.items).toEqual([]);
    expect(rpc.mock.calls.filter(([name])=>name==='update_record_classification')).toHaveLength(1);
});
test('successful void response with stale readback is an error, never a fake save',async()=>{
    const real=rpc.getMockImplementation();rpc.mockImplementation((name,args)=>name.startsWith('update_')?{data:null}:real(name,args));
    await expect(store.updateCategory('r1','cat')).rejects.toThrow('no confirma');expect(unresolvedPurchases(store.items)).toBe(2);
});
test('clearing category persists null while preserving activity',async()=>{
    await store.updateActivity('r1','act');await store.updateCategory('r1','cat');await store.updateCategory('r1','');
    expect(records[0]).toMatchObject({category_id:null,activity_id:'act'});expect(unresolvedPurchases(store.items)).toBe(2);
});
test('UI catches server error, restores rendered values and ends busy state',async()=>{
    denied=true;const control={value:'cat',setAttribute:jest.fn(),removeAttribute:jest.fn()},render=jest.fn(),error=jest.fn();
    await saveClassificationControl(store,control,'updateCategory','r1',render,error);
    expect(error).toHaveBeenCalledWith('RECORD_CLASSIFY denied');expect(render).toHaveBeenCalledTimes(1);
    expect(control.removeAttribute).toHaveBeenCalledWith('aria-busy');expect(store.items[0].category_id).toBeNull();
});
