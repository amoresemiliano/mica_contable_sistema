import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(new URL(`../${p}`,import.meta.url),'utf8').replace(/\r/g,'');
const up=read('sql/044_fix_resumable_perception_file_reuse.sql');
const original=read('sql/039c_functional_stabilization.sql');
const m43=read('sql/043_resumable_import_chunks.sql');
const body=(s,n)=>s.match(new RegExp(`CREATE(?: OR REPLACE)? FUNCTION (?:public|private)\\.${n}\\([\\s\\S]*?AS \\$\\$([\\s\\S]*?)\\$\\$;`))[1];
const transform=s=>s.replaceAll('private.reuse_039c_file(','private.reuse_import_chunk_file(').replaceAll("'IMPORT_COMPLETED'","'IMPORT_CHUNK_APPLIED'").replaceAll("v_import_record.status != 'PENDING'","v_import_record.status NOT IN ('PENDING', 'PROCESSING')");
test('044 pins every expected installed 043 worker/helper/RPC body',()=>{
 const bodies=[...['persist_perceptions_batch','persist_financial_movements_batch'].map(n=>transform(body(original,n))),
  ...['reuse_import_chunk_file','persist_import_chunk','get_resumable_import'].map(n=>body(m43,n))];
 for(const b of bodies) expect(up).toContain(crypto.createHash('md5').update(b.trim()).digest('hex'));
 expect(up).toContain('044 installed 043 definition drift');
});
test('repair removes exactly the early perception guard and leaves authorized reuse and bounded rows',()=>{
 const worker=transform(body(original,'persist_perceptions_batch'));
 const pattern=up.match(/guard TEXT:=\$guard\$([\s\S]*?)\$guard\$/)[1].replace('\\m','\\b');
 const guard=new RegExp(pattern,'g');
 expect([...worker.matchAll(guard)]).toHaveLength(1);
 expect(worker.search(guard)).toBeLessThan(worker.indexOf('private.reuse_import_chunk_file('));
 const repaired=worker.replace(guard,'');
 expect(repaired).not.toContain('File already registered for import');
 for(const c of ['private.require_039_batch','> 500','private.reuse_import_chunk_file(','IF v_existing_file_id IS NULL THEN','ELSE v_file_id := v_existing_file_id; END IF;']) expect(repaired).toContain(c);
 expect(body(original,'persist_financial_movements_batch')).not.toContain('File already registered for import');
 expect(up).not.toMatch(/GRANT|CREATE OR REPLACE FUNCTION public/);
});

test('DEV diagnostic multiline guard and PostgreSQL whitespace variants are removed precisely',()=>{
 // Guard formatting supplied by the read-only DEV diagnostic in the repair request.
 const captured=`IF EXISTS (
  SELECT 1
  FROM public.eco_source_files
  WHERE import_id = p_import_id
) THEN
  RAISE EXCEPTION 'File already registered for import %', p_import_id;
END IF;`;
 const pattern=up.match(/guard TEXT:=\$guard\$([\s\S]*?)\$guard\$/)[1].replace('\\m','\\b');
 const worker=transform(body(original,'persist_perceptions_batch'));
 const canonical=new RegExp(pattern,'g');
 for(const guard of [captured,captured.replaceAll('\n','\r\n\t'),captured.replaceAll(' = ','='),captured.replace(/\n\s*/g,' ')]) {
  const variant=worker.replace(canonical,()=>guard);
  expect([...variant.matchAll(new RegExp(pattern,'g'))]).toHaveLength(1);
  expect(variant.replace(new RegExp(pattern,'g'),'')).toBe(worker.replace(canonical,''));
 }
 expect(up).toContain('prosrc=after_body AND prosecdef');
 expect(up).toContain('proowner=before_owner AND proacl IS NOT DISTINCT FROM before_acl');
 expect(up).toContain('proconfig IS NOT DISTINCT FROM before_config');
 expect(up).toContain('partial installation');
 expect(up).toContain("strpos(after_body,'File already registered for import')>0");
 expect(up).toContain('replace(before_definition,before_body,after_body)');
 expect(up).not.toContain('before_definition:=replace(before_definition,chr(13)');
});
test('rollback refuses active imports and drift; harness retains requested boundaries',()=>{
 const down=read('sql/044_fix_resumable_perception_file_reuse_down.sql');
 expect(down).toContain('WHERE NOT complete');expect(down).toContain('IS DISTINCT FROM r.installed_definition');
 const harness=read('tests/db/043_resumable_import_chunks.sql');
 for(const c of ['ARRAY[1,499,500,501,1000,1001]','Same hash different import accepted','Changed file metadata accepted','Receipt replay changed canonical file_id','Failed chunk changed canonical file identity','Cross-org chunk accepted','RESET ROLE;','SET LOCAL ROLE authenticated;']) expect(harness).toContain(c);
 expect(harness.trim()).toMatch(/ROLLBACK;$/);
});
