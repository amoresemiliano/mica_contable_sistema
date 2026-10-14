import {jest} from '@jest/globals';
import {createReportingHandler} from '../src/js/core/reporting/server.js';
import {reportingData} from './fixtures/reporting.js';
function fixture({data=reportingData(),context=data.organization_id,denied=false}={}){
 const rpc=jest.fn(async(name,args)=>name==='get_my_operational_context'?{data:{organization_id:context}}:denied?{error:{message:'capability denied'}}:{data:structuredClone({...data,date_from:args.p_from,date_to:args.p_to})});
 const snapshots=[],writer=jest.fn(async(name,args)=>{if(args.p_action==='close')snapshots.push(structuredClone(args.p_data));return {data:{snapshot_id:'immutable-snapshot',organization_id:context}};});
 const handler=createReportingHandler({authenticate:async token=>token==='valid'?{id:'verified-auth-user'}:null,userClient:()=>({rpc}),serviceClient:{rpc:writer},allowedOrigins:['https://mica.example'],now:()=> '2026-10-15T10:00:00Z'});
 const call=(body,token='valid',origin='https://mica.example')=>handler(new Request('https://edge.example/reporting',{method:'POST',headers:{authorization:`Bearer ${token}`,origin},body:JSON.stringify({organization_id:data.organization_id,from:data.date_from,to:data.date_to,type:'IVA',...body})}));
 return {call,rpc,writer,snapshots,data};
}
test('verified JWT, allowed origin and confirmed tenant are mandatory',async()=>{
 const f=fixture();expect((await f.call({action:'data'},'invalid')).status).toBe(401);expect((await f.call({action:'data'},'valid','https://evil.example')).status).toBe(403);
 expect((await f.call({action:'data',organization_id:'org-b'})).status).toBe(400);expect(f.writer).not.toHaveBeenCalled();
 const denied=fixture({denied:true});expect((await denied.call({action:'data'})).status).toBe(400);
});
test('export requires server export permission; unauthorized reads cannot reach writer',async()=>{
 const f=fixture();expect((await f.call({action:'export'})).status).toBe(200);expect(f.rpc).toHaveBeenCalledWith('mica_reporting_data',expect.objectContaining({p_export:true,p_expected_org:f.data.organization_id}));
 const denied=fixture({denied:true});await denied.call({action:'input',kind:'IVA_OPENING',period:'2026-09',payload:{technical:0,free:0},revision:0});expect(denied.writer).not.toHaveBeenCalled();
});
test('closing recalculates canonical outputs, ignores browser calculations and freezes versioned snapshot',async()=>{
 const f=fixture();const response=await f.call({action:'close',input_hash:f.data.input_hash,calculated:{rows:[{value:999999999}]}});
 expect(response.status).toBe(200);expect(f.snapshots).toHaveLength(1);
 const snapshot=f.snapshots[0];expect(snapshot.calculated.rows.find(r=>r.code==='iva_payable').value).toBe(102000);expect(snapshot.engine_version).toBe('management-v1');
 expect(f.writer.mock.calls[0][1].p_subject).toBe('verified-auth-user');
 f.data.groups[0].vat=999999;expect(snapshot.calculated.rows.find(r=>r.code==='iva_df').value).toBe(189000);
});
test('changed sources and incomplete reports block review/closing before trusted writer',async()=>{
 const f=fixture();expect((await f.call({action:'close',input_hash:'stale'})).status).toBe(400);expect(f.writer).not.toHaveBeenCalled();
 f.data.inputs=f.data.inputs.filter(i=>i.kind!=='IVA_OPENING');expect((await f.call({action:'review',input_hash:f.data.input_hash})).status).toBe(400);expect(f.writer).not.toHaveBeenCalled();
});
test('trusted endpoint validates inputs and refuses invalid coefficient totals',async()=>{
 const f=fixture();expect((await f.call({action:'input',kind:'CM_COEFFICIENTS',period:'2026',payload:{rows:[{jurisdiction:'CABA',coefficient:.5}]},revision:0})).status).toBe(400);expect(f.writer).not.toHaveBeenCalled();
 expect((await f.call({action:'input',kind:'IVA_OPENING',period:'2026-09',payload:{technical:0,free:0},revision:0})).status).toBe(200);expect(f.writer.mock.calls[0][1].p_subject).toBe('verified-auth-user');
});
test('data selection retains selected dates while IVA uses full chain from opening',async()=>{
 const f=fixture();f.data.inputs[0].period='2026-08';const response=await f.call({action:'data'});const json=await response.json();expect(response.status).toBe(200);expect(json.model.date_from).toBe('2026-09-01');expect(f.rpc).toHaveBeenCalledWith('mica_reporting_data',expect.objectContaining({p_from:'2026-08-01'}));
});
test('fiscal months and annual exercise cannot be partial; explicit reopen accepts changed sources',async()=>{
 const f=fixture();expect((await f.call({action:'preview',from:'2026-09-15'})).status).toBe(400);expect((await f.call({action:'preview',type:'GANANCIAS'})).status).toBe(400);
 expect((await f.call({action:'reopen',input_hash:'old-closed-inputs'})).status).toBe(200);expect(f.writer.mock.calls[0][1].p_action).toBe('reopen');
});
