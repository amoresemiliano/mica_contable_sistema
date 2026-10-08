import { jest } from '@jest/globals';
import { persistImportChunks } from '../../src/js/core/services/importChunks.js';
import { PersistenceService } from '../../src/js/core/services/persistenceService.js';
const rows=n=>Array.from({length:n},(_,i)=>({sourceRowNumber:i+4,rawRow:['synthetic'],normalizedData:{monto:i+1},errors:[],warnings:[]}));
// Receipt model is a client contract test; actual SQL execution is a separate DEV gate.
function server() {
 const receipts=new Map();let accepted=0,active=0;
 const rpc=jest.fn(async(name,args)=>{
  active++;expect(active).toBe(1);expect(name).toBe('persist_import_chunk');
  await Promise.resolve();const index=args.p_chunk_index, payload=JSON.stringify(args.p_staged_rows);
  if(receipts.has(index)) expect(receipts.get(index)).toBe(payload);
  else {expect(index).toBe(receipts.size);receipts.set(index,payload);accepted+=args.p_staged_rows.length;}
  active--;return {data:{import_id:args.p_import_id,file_id:'one-file',next_chunk_index:receipts.size,total_rows:accepted,
   accepted_rows:accepted,invalid_rows:0,duplicate_rows:0,complete:accepted===args.p_total_rows},error:null};
 });return {rpc,receipts};
}
test.each([501,1000,1001])('sequential boundary %i and stable identity',async n=>{
 const s=server();const result=await persistImportChunks(s.rpc,{importId:'one-import',fileInfo:{sha256_hash:'same-file'},stagedRows:rows(n),kind:'FINANCIAL'});
 expect(s.rpc).toHaveBeenCalledTimes(Math.ceil(n/500));expect(result.total_rows).toBe(n);expect(result.complete).toBe(true);
 expect(s.rpc.mock.calls.every(([,a])=>a.p_import_id==='one-import'&&a.p_staged_rows.length<=500)).toBe(true);
 expect(s.rpc.mock.calls.at(-1)[1].p_staged_rows.at(-1).sourceRowNumber).toBe(n+3);
});
test.each(['FINANCIAL','PERCEPCION'])('partial failure preserves source; retry receipts create no duplicate (%s)',async kind=>{
 const s=server();const flaky=jest.fn(async(name,a)=>a.p_chunk_index===1?{error:{message:'temporary failure'}}:s.rpc(name,a));
 const params={importId:'same-import',fileInfo:{sha256_hash:'same-file'},stagedRows:rows(1001),kind};
 await expect(persistImportChunks(flaky,params)).rejects.toMatchObject({preserveSourceFile:true});
 expect(s.receipts.size).toBe(1);expect(s.rpc.mock.results).toHaveLength(1);
 const result=await persistImportChunks(s.rpc,params);expect(result.accepted_rows).toBe(1001);expect(s.receipts.size).toBe(3);
});
test('lost final response safely replays all receipts',async()=>{
 const s=server();const params={importId:'same',fileInfo:{},stagedRows:rows(501),kind:'FINANCIAL'};
 await expect(persistImportChunks(async(n,a)=>{const r=await s.rpc(n,a);if(a.p_chunk_index===1)throw new Error('lost response');return r;},params)).rejects.toMatchObject({preserveSourceFile:true});
 const r=await persistImportChunks(s.rpc,params);expect(r.accepted_rows).toBe(501);expect(s.receipts.size).toBe(2);
});
test('never treats an incomplete final response as success',async()=>{
 await expect(persistImportChunks(async()=>({data:{import_id:'same',next_chunk_index:2,total_rows:500,complete:false}}),
  {importId:'same',fileInfo:{},stagedRows:rows(501),kind:'PERCEPCION'})).rejects.toMatchObject({preserveSourceFile:true});
});
test.each(['persistPerceptionsBatch','persistFinancialMovementsBatch'].flatMap(method=>[1,499,500,501,1000,1001].map(n=>[method,n])))('%s boundary %i uses the correct server contract',async (method,n)=>{
 const service=new PersistenceService();const calls=[];service.supabase.rpc=async(name,a)=>{
  calls.push([name,a]);return {data:name==='persist_import_chunk'?{import_id:'same',next_chunk_index:a.p_chunk_index+1,total_rows:Math.min((a.p_chunk_index+1)*500,a.p_total_rows),complete:(a.p_chunk_index+1)*500>=a.p_total_rows}: {total_rows:500},error:null};
 };
 await service[method]({importId:'same',fileInfo:{},stagedRows:rows(n)});
 const expected=n>500?'persist_import_chunk':method==='persistPerceptionsBatch'?'persist_perceptions_batch':'persist_financial_movements_batch';
 expect(calls.map(c=>c[0])).toEqual(Array(Math.ceil(n/500)).fill(expected));
 expect(calls.every(([,a])=>a.p_import_id==='same' && a.p_staged_rows.length<=500)).toBe(true);
});
test('resume lookup reuses canonical envelope without creating a second import',async()=>{
 const service=new PersistenceService();const canonical={import_id:'same',organization_id:'org',storage_prefix:'org/same',source_file_reused:true,storage_path:'org/same/source.csv'};
 const rpc=jest.fn(async()=>({data:canonical,error:null}));service.supabase.rpc=rpc;
 expect(await service.checkFileImportable('a'.repeat(64),{resumable:true})).toMatchObject({importable:true,resume_import:canonical});
 expect(rpc).toHaveBeenCalledTimes(1);expect(rpc).toHaveBeenCalledWith('get_resumable_import',{p_sha256_hash:'a'.repeat(64)});
});
test('hydration preserves retention semantics',async()=>{
 const service=new PersistenceService();service.supabase.rpc=async()=>({data:[{id:'retention',record_type:'PERCEPCIONES_ARBA',normalized_payload:{tipo:'retencion',jurisdiction:'ARBA',monto:10}}],error:null});
 expect((await service.loadActivePerceptions())[0].tipo).toBe('retencion');
});
