import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(new URL(`../${p}`,import.meta.url),'utf8');
const sql=read('sql/043_resumable_import_chunks.sql');
test('canonical worker pin matches both checked-in bodies',()=>{
 const original=read('sql/039c_functional_stabilization.sql').replace(/\r/g,'');
 for(const name of ['persist_perceptions_batch','persist_financial_movements_batch']){
  const body=original.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?AS \\$\\$([\\s\\S]*?)\\$\\$;`))[1].trim();
  expect(sql).toContain(crypto.createHash('md5').update(body).digest('hex'));
 }
});
test('bounded receipts protect identity, sequence, source trace, tenant and creator',()=>{
 for(const contract of ['private.require_039_batch','FOR UPDATE','Only import creator may resume','n>500','Chunk manifest changed','Chunk replay payload changed',
  'Source trace overlaps earlier chunk','Use persist_import_chunk','completed_at=CASE WHEN progress.complete','source_file_reused','UNIQUE(organization_id,sha256_hash)']) expect(sql).toContain(contract);
 expect(sql).toMatch(/REVOKE ALL ON FUNCTION private\.reuse_import_chunk_file[\s\S]*FROM PUBLIC,anon,authenticated/);
 expect(sql).not.toMatch(/GRANT.*(?:USAGE.*private|private\.)/);
});
test('rollback refuses incomplete imports and keeps audit receipts; harness rolls back',()=>{
 const down=read('sql/043_resumable_import_chunks_down.sql');expect(down).toContain('WHERE NOT complete');
 expect(down).toContain('import_chunk_receipts_043_archive');expect(down).not.toMatch(/DELETE FROM public\./);
 const harness=read('tests/db/043_resumable_import_chunks.sql');expect(harness.trim()).toMatch(/ROLLBACK;$/);
 expect(harness).toContain('ARRAY[1,499,500,501,1000,1001]');expect(harness).toContain('Cross-org chunk accepted');
});
