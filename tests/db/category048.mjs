// Executes real PostgreSQL locally through PGlite. Never opens a network connection.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {categoryNameKey} from '../../src/js/core/categoryNames.js';
const modulePath=resolve(process.env.MICA_PGLITE_MODULE || 'scratch/category048-db/node_modules/@electric-sql/pglite/dist/index.js');
const {PGlite}=await import(pathToFileURL(modulePath).href);
const db=new PGlite();await db.waitReady;
const read=path=>readFileSync(path,'utf8');
const up=read('sql/048_canonicalize_tax_categories.sql'),down=read('sql/048_canonicalize_tax_categories_down.sql');
const fixture=read('tests/db/048_category_fixture.sql');
const source=read('sql/030_separate_assignment_and_activation.sql');
const rpc=source.slice(source.indexOf('CREATE OR REPLACE FUNCTION public.create_global_tax_category('),source.indexOf('CREATE OR REPLACE FUNCTION public.update_global_tax_category('));
const H='c15675d7-be33-4400-84c3-9985e1a59579',T='02768384-f366-4fd9-aa0c-a437866cfeb4';
const HO='326eaed3-d6cb-4d63-8adb-47116ad94bf5',HN='3c86c6f9-aea0-4dc3-98e0-e30836daf0e5',HM='46200cf5-c488-47b8-b946-e637885c7c82',HU='e26570a7-6e09-40a4-8901-62b835df145e',TD='a209c838-d3e3-4e3c-9b4f-4619c83cc336';
const A='00000000-0000-0000-0000-000000000001',O='00000000-0000-0000-0000-000000000002',N='00000000-0000-0000-0000-000000000003',M='00000000-0000-0000-0000-000000000004';
const query=async(sql,params=[]) => (await db.query(sql,params)).rows;
const run=async sql=>{try{await db.exec(sql);}catch(error){await db.exec('ROLLBACK');throw error;}};
const zeroTables=['eco_classification_rules','eco_movement_allocations','eco_tax_subcategories'];
const dump=async()=>{const result={};for(const table of ['eco_tax_categories','eco_org_tax_categories','eco_normalized_records','eco_financial_movements',...zeroTables])result[table]=await query(`SELECT to_jsonb(t) AS row FROM public.${table} t ORDER BY id`);return result;};
const reset=async()=>{
 await db.exec('RESET ROLE;DROP SCHEMA IF EXISTS public CASCADE;DROP SCHEMA IF EXISTS private CASCADE;DROP ROLE IF EXISTS anon;DROP ROLE IF EXISTS authenticated;CREATE SCHEMA public;');
 await db.exec(fixture+rpc);
};
const expectAbort=async(sql,pattern)=>assert.rejects(()=>run(sql),pattern);
const cases=[];const test=(name,fn)=>cases.push([name,fn]);

test('read-only preflight inventories diagnosed rows and all incoming FKs without writes',async()=>{
 const before=await dump();const results=await db.exec(read('sql/048_preflight_readonly.sql'));
 assert.equal(results[1].rows.length,6);assert.equal(results[2].rows.length,7);
 assert.equal(results[1].rows.filter(row=>row.migration_scope==='VERIFIED_ZERO').length,3);
 for(const row of results[2].rows.filter(row=>row.kind.endsWith('duplicate'))){
  for(const column of ['classification_rules','movement_allocations','tax_subcategories'])assert.equal(Number(row[column]),0);
 }
 assert.equal(results[4].rows.length,2);assert.deepEqual(await dump(),before);
});

test('explicit survivors, five duplicate deletions, reference and assignment postconditions',async()=>{
 const before=await dump();await run(up);
 const after=await dump();for(const table of zeroTables)assert.deepEqual(after[table],before[table]);
 const inventory=(await query("SELECT payload->'after'->'foreign_keys' AS fks FROM private.migration_048_category_backup"))[0].fks;
 assert.equal(inventory.length,6);assert(inventory.some(fk=>fk.table==='public.eco_tax_subcategories'&&fk.definition.includes('ON DELETE CASCADE')));
 assert.deepEqual((await query('SELECT id FROM eco_tax_categories ORDER BY id')).map(r=>r.id),['00000000-0000-0000-0000-000000000010',T,H].sort());
 for(const id of [HO,HN,HM,HU,TD])assert.equal((await query('SELECT count(*)::int AS n FROM eco_tax_categories WHERE id=$1',[id]))[0].n,0);
 assert.equal((await query('SELECT count(*)::int AS n FROM eco_normalized_records WHERE category_id=$1',[H]))[0].n,15);
 assert.equal((await query('SELECT category_id FROM eco_normalized_records WHERE id=$1',['00000000-0000-0000-0000-000000000099']))[0].category_id,T);
 const assignments=await query('SELECT * FROM eco_org_tax_categories ORDER BY id');
 assert.equal(assignments.length,7);
 for(const org of [A,O,N,M])assert(assignments.some(a=>a.organization_id===org&&a.category_id===H));
 for(const org of [A,N,M])assert(assignments.some(a=>a.organization_id===org&&a.category_id===T));
 for(const row of before.eco_org_tax_categories.map(r=>r.row)){
  const now=assignments.find(a=>a.id===row.id);assert(now);assert.equal(now.custom_name,row.custom_name);assert.equal(now.is_active,row.is_active);assert.equal(now.is_assigned,row.is_assigned);
 }
 assert.equal((await query('SELECT count(*)::int n FROM eco_normalized_records r LEFT JOIN eco_tax_categories c ON c.id=r.category_id WHERE r.category_id IS NOT NULL AND c.id IS NULL'))[0].n,0);
 assert.equal((await query('SELECT count(*)::int n FROM (SELECT organization_id,category_id FROM eco_org_tax_categories GROUP BY 1,2 HAVING count(*)>1) x'))[0].n,0);
 const telefono=(await query('SELECT to_jsonb(r) AS row FROM eco_normalized_records r WHERE id=$1',['00000000-0000-0000-0000-000000000099']))[0].row;
 const original=before.eco_normalized_records.find(r=>r.row.id===telefono.id).row;
 assert.deepEqual(telefono,{...original,category_id:T});
 for(const id of [H,T]){const original=before.eco_tax_categories.find(r=>r.row.id===id).row;const actual=(await query('SELECT to_jsonb(c)-\'canonical_name_key\' AS row FROM eco_tax_categories c WHERE id=$1',[id]))[0].row;assert.deepEqual(actual,original);}
});
test('real UP/DOWN restores every original row, UUID and metadata exactly',async()=>{
 const before=await dump();await run(up);await run(down);assert.deepEqual(await dump(),before);
 assert.equal((await query("SELECT to_regclass('private.migration_048_category_backup') IS NULL AS gone"))[0].gone,true);
});
test('compatible overlapping assignments merge without duplicate keys and rollback exactly',async()=>{
 await db.exec(`INSERT INTO eco_org_tax_categories(organization_id,category_id,custom_name,is_active) VALUES ('${O}','${H}','Honorarios Oeste',FALSE),('${N}','${T}',NULL,TRUE)`);
 const before=await dump();await run(up);
 assert.equal((await query('SELECT count(*)::int n FROM eco_org_tax_categories'))[0].n,7);
 assert.equal((await query('SELECT custom_name FROM eco_org_tax_categories WHERE organization_id=$1 AND category_id=$2',[N,T]))[0].custom_name,'Telefonía Norte');
 await run(down);assert.deepEqual(await dump(),before);
});
test('SQL/JavaScript Unicode, accents, whitespace and type keys agree',async()=>{
 await run(up);
 for(const name of [' TELEFONÍA  ','Telefoni\u0301a','\tHONORARIOS\n PROFESIONALES ','\u00a0Teléfonía\ufeff','Čañón  Útil','A \u0301 B']){
  assert.equal((await query('SELECT public.mica_category_name_key($1) AS key',[name]))[0].key,categoryNameKey(name));
 }
 await expectAbort("INSERT INTO eco_tax_categories(name,category_type) VALUES ('  TELEFONIA  ','EXPENSE')",/eco_tax_categories_canonical_name_048_key/);
 await expectAbort("UPDATE eco_tax_categories SET name='telefonía' WHERE name='Otra categoría'",/eco_tax_categories_canonical_name_048_key/);
 await expectAbort("INSERT INTO eco_tax_categories(name,category_type) VALUES ('   ','EXPENSE')",/eco_tax_categories_nonempty_name_048_check/);
 await db.exec("INSERT INTO eco_tax_categories(name,category_type) VALUES ('Telefonía','INCOME')");
 assert.equal((await query("SELECT count(*)::int n FROM eco_tax_categories WHERE canonical_name_key='telefonia'"))[0].n,2);
});
test('original SECURITY DEFINER creation RPC remains authoritative and permissions unchanged',async()=>{
 await run(up);await db.exec("SET ROLE authenticated;SET mica.test_org='';SET mica.test_manage='yes';");
 await expectAbort("SELECT public.create_global_tax_category('  TELEFONIA ','duplicate','EXPENSE')",/eco_tax_categories_canonical_name_048_key/);
 await db.exec("SELECT public.create_global_tax_category('Telefonía','distinct income','INCOME')");
 await db.exec("SET mica.test_manage='no'");await expectAbort("SELECT public.create_global_tax_category('New','unauthorized','EXPENSE')",/Unauthorized/);
 await db.exec('RESET ROLE');
});
test('tenant catalogs retain canonical IDs without cross-company record access; ledger is private',async()=>{
 await run(up);await db.exec(`SET ROLE authenticated;SET mica.test_org='${N}';`);
 assert.deepEqual((await query('SELECT category_id FROM eco_org_tax_categories ORDER BY category_id')).map(r=>r.category_id),[T,H].sort());
 assert.deepEqual((await query('SELECT organization_id,category_id FROM eco_normalized_records')).map(r=>[r.organization_id,r.category_id]),[[N,T]]);
 await expectAbort('SELECT * FROM private.migration_048_category_backup',/permission denied/);
 await db.exec(`SET mica.test_org='${A}';`);assert.equal((await query('SELECT count(*)::int n FROM eco_normalized_records'))[0].n,15);
 await db.exec('RESET ROLE');
});

for(const [name,mutation,pattern] of [
 ['missing survivor',`DELETE FROM eco_classification_rules WHERE target_category_id='${H}';DELETE FROM eco_normalized_records WHERE category_id='${H}';DELETE FROM eco_org_tax_categories WHERE category_id='${H}';DELETE FROM eco_tax_categories WHERE id='${H}'`,/missing/],
 ['missing orphan duplicate',`DELETE FROM eco_tax_categories WHERE id='${HU}'`,/missing/],
 ['wrong concept',`UPDATE eco_tax_categories SET name='Unexpected' WHERE id='${HO}'`,/concept name/],
 ['wrong category type',`UPDATE eco_tax_categories SET category_type='INCOME' WHERE id='${HO}'`,/category_type/],
 ['nullable canonical name',"ALTER TABLE eco_tax_categories ALTER COLUMN name DROP NOT NULL",/nullable name\/type schema drift/],
 ['extra normalized reference',`INSERT INTO eco_normalized_records(organization_id,category_id) VALUES ('${O}','${HO}')`,/normalized reference count drift/],
 ['unexpected financial reference',`INSERT INTO eco_financial_movements(organization_id,category_id,amount) VALUES ('${O}','${HO}',12)`,/financial reference/],
 ['changed assignment',`UPDATE eco_org_tax_categories SET organization_id='${N}' WHERE category_id='${HO}'`,/organization assignment drift/],
 ['unknown incoming category FK',`CREATE TABLE extra_reference(id UUID PRIMARY KEY,category_id UUID REFERENCES eco_tax_categories)`,/FK inventory drift/],
 ['missing expected FK',"ALTER TABLE eco_movement_allocations DROP CONSTRAINT eco_movement_allocations_category_id_fkey",/FK inventory drift/],
 ['unvalidated expected FK',"ALTER TABLE eco_movement_allocations DROP CONSTRAINT eco_movement_allocations_category_id_fkey;ALTER TABLE eco_movement_allocations ADD FOREIGN KEY(category_id) REFERENCES eco_tax_categories(id) NOT VALID",/FK inventory drift/],
 ['wrong expected FK column',"ALTER TABLE eco_classification_rules ADD COLUMN wrong_category_id UUID;ALTER TABLE eco_classification_rules DROP CONSTRAINT eco_classification_rules_target_category_id_fkey;ALTER TABLE eco_classification_rules ADD FOREIGN KEY(wrong_category_id) REFERENCES eco_tax_categories(id)",/FK inventory drift/],
 ['subcategory delete-action drift',"ALTER TABLE eco_tax_subcategories DROP CONSTRAINT eco_tax_subcategories_category_id_fkey;ALTER TABLE eco_tax_subcategories ADD FOREIGN KEY(category_id) REFERENCES eco_tax_categories(id)",/FK inventory drift/],
 ['classification rule duplicate reference',`INSERT INTO eco_classification_rules(target_category_id,name) VALUES ('${HO}','Do not reassign')`,/verified-zero reference drift.*eco_classification_rules/],
 ['movement allocation duplicate reference',`INSERT INTO eco_movement_allocations(category_id,amount) VALUES ('${TD}',10)`,/verified-zero reference drift.*eco_movement_allocations/],
 ['cascading subcategory duplicate reference',`INSERT INTO eco_tax_subcategories(category_id,name) VALUES ('${HN}','Do not cascade delete')`,/verified-zero reference drift.*eco_tax_subcategories/],
 ['incoming assignment FK',`CREATE TABLE extra_assignment_reference(id UUID PRIMARY KEY,assignment_id UUID REFERENCES eco_org_tax_categories)`,/incoming references/],
 ['hidden JSON reference',`CREATE TABLE hidden_references(payload JSONB);INSERT INTO hidden_references VALUES ('{"category":"${HO}"}')`,/unreviewed reference/],
 ['undeclared scalar reference',`CREATE TABLE hidden_references(category_id UUID);INSERT INTO hidden_references VALUES ('${HO}')`,/unreviewed reference/],
 ['additional diagnosed concept',"INSERT INTO eco_tax_categories(name,category_type) VALUES (' Telefonia ','EXPENSE')",/additional definition/],
 ['unrelated duplicated concept',"INSERT INTO eco_tax_categories(name,category_type) VALUES ('OTRA CATEGORIA','EXPENSE')",/other canonical-name conflicts/],
 ['incompatible activation collision',`INSERT INTO eco_org_tax_categories(organization_id,category_id,is_active) VALUES ('${O}','${H}',TRUE)`,/metadata conflict/],
 ['incompatible custom-label collision',`INSERT INTO eco_org_tax_categories(organization_id,category_id,custom_name,is_active) VALUES ('${O}','${H}','Different label',FALSE)`,/metadata conflict/],
 ['unreviewed business trigger',"CREATE FUNCTION public.touch_fixture() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW;END;$$;CREATE TRIGGER unknown_touch BEFORE UPDATE ON eco_normalized_records FOR EACH ROW EXECUTE FUNCTION touch_fixture()",/unreviewed user triggers/]
])test('UP aborts atomically on '+name,async()=>{
 await db.exec(mutation);const before=await dump();await expectAbort(up,pattern);assert.deepEqual(await dump(),before);
 assert.equal((await query("SELECT to_regclass('private.migration_048_category_backup') IS NULL AND to_regprocedure('public.mica_category_name_key(text)') IS NULL AS clean"))[0].clean,true);
});

for(const [name,mutation] of [
 ['edited record',"UPDATE eco_normalized_records SET total=999 WHERE id='00000000-0000-0000-0000-000000000099'"],
 ['new survivor reference',`INSERT INTO eco_normalized_records(organization_id,category_id,total) VALUES ('${A}','${H}',1)`],
 ['removed affected record',"DELETE FROM eco_normalized_records WHERE id='00000000-0000-0000-0000-000000000099'"],
 ['edited category',`UPDATE eco_tax_categories SET description='post-048 edit' WHERE id='${T}'`],
 ['edited assignment',`UPDATE eco_org_tax_categories SET is_active=FALSE WHERE category_id='${T}' AND organization_id='${N}'`],
 ['new incoming FK',"CREATE TABLE extra_reference(id UUID PRIMARY KEY,category_id UUID REFERENCES eco_tax_categories)"],
 ['changed additional FK definition',"ALTER TABLE eco_classification_rules DROP CONSTRAINT eco_classification_rules_target_category_id_fkey;ALTER TABLE eco_classification_rules ADD FOREIGN KEY(target_category_id) REFERENCES eco_tax_categories(id) ON DELETE CASCADE"],
 ['changed policy',"ALTER POLICY record_read ON eco_normalized_records USING(TRUE)"],
 ['changed schema',"ALTER TABLE eco_normalized_records ADD COLUMN post048 TEXT"],
 ['new index on generated key',"CREATE INDEX post048_key_index ON eco_tax_categories(canonical_name_key)"],
 ['changed column ACL',"GRANT SELECT(canonical_name_key) ON eco_tax_categories TO anon"],
 ['changed key function',"CREATE OR REPLACE FUNCTION public.mica_category_name_key(p_name TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE STRICT AS $$SELECT lower($1)$$"]
])test('DOWN refuses '+name+' without reverting anything',async()=>{
 await run(up);await db.exec(mutation);const post=await dump();await expectAbort(down,/post-migration data\/schema\/function drift/);assert.deepEqual(await dump(),post);
 assert.equal((await query("SELECT to_regclass('private.migration_048_category_backup') IS NOT NULL AS kept"))[0].kept,true);
});
test('reruns fail closed; unrelated post-migration records survive a safe rollback',async()=>{
 await run(up);await expectAbort(up,/already installed/);
 await db.exec(`INSERT INTO eco_normalized_records(organization_id,category_id,total) VALUES ('${O}','00000000-0000-0000-0000-000000000010',777)`);
 await run(down);assert.equal((await query('SELECT count(*)::int n FROM eco_normalized_records WHERE total=777'))[0].n,1);
 await expectAbort(down,/requires intact/);
});
test('rollback preserves new survivor references in the unmutated additional tables',async()=>{
 await run(up);await db.exec(`INSERT INTO eco_tax_subcategories(category_id,name) VALUES ('${H}','New survivor subcategory')`);
 const after=await dump();await run(down);const restored=await dump();
 for(const table of zeroTables)assert.deepEqual(restored[table],after[table]);
});
let passed=0;
try{
 for(const [name,fn] of cases){await reset();try{await fn();passed++;console.log('PASS '+name);}catch(error){console.error('FAIL '+name,JSON.stringify({message:error.message,code:error.code,detail:error.detail,position:error.position,where:error.where}));process.exitCode=1;break;}}
 console.log(`048 PostgreSQL integration: ${passed}/${cases.length} passed; remote connections: 0`);
}finally{await db.close();}
