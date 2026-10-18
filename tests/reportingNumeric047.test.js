import fs from 'node:fs';
import crypto from 'node:crypto';
import {jest} from '@jest/globals';
import {buildModel,buildReport,aggregateMetric} from '../src/js/core/reporting/engine.js';
import {createReportingHandler} from '../src/js/core/reporting/server.js';
import {reportingData} from './fixtures/reporting.js';
import {numeric047Vectors,voucher047Vectors,totalZero047,totalZero047Group} from './fixtures/reportingNumeric047.js';
const read=p=>fs.readFileSync(p,'utf8').replace(/\r/g,'');
const up=read('sql/047_reporting_numeric_voucher.sql'),down=read('sql/047_reporting_numeric_voucher_down.sql');
const numberBody=up.split('CREATE FUNCTION private.reporting_047_number')[1].split('$$;')[0];
const pattern=new RegExp(numberBody.match(/p_value ~ '([^']+)'/)[1]);
const bound=numberBody.match(/abs\(p_value::NUMERIC\)<=([\d.]+)/)[1];
// Independent exact decimal oracle for the declared SQL boundary, without executing SQL.
function oracle(text){
 if(typeof text!=='string'||!pattern.test(text))return null;
 const negative=text.startsWith('-'),[whole,fraction='']=text.replace(/^-/,'').split('.');
 const digits=BigInt(whole+fraction),scale=10n**BigInt(fraction.length);
 const [maxWhole,maxFraction]=bound.split('.');
 if(digits*100n>BigInt(maxWhole+maxFraction)*scale)return null;
 const rounded=(digits*100n*2n+scale)/(2n*scale);
 return Number(negative?-rounded:rounded);
}
test.each(numeric047Vectors)('historical decimal %s has exact rounded cents %s', (source,cents)=>expect(oracle(source)).toBe(cents));
test.each(['NaN','Infinity','-Infinity','1e3','1E-3','1,20','1.234,56',' 1','1 ','+1','.5','1.','--1','1x','',null,'10000000000000','9999999999999.991','1.'+'1'.repeat(25)])('rejects malformed/unbounded value %s',source=>expect(oracle(source)).toBeNull());
test.each([['1.005',101],['-1.005',-101],['0',0],['-0.004',0],['9999999999999.99',999999999999999]])('rounds decimal ties away from zero %s',(source,cents)=>expect(oracle(source)).toBe(cents));
test('SQL boundary uses guarded NUMERIC cast and two-place rounding, never floating arithmetic',()=>{
 expect(numberBody).toContain("CASE WHEN p_value ~");expect(numberBody).toContain('THEN round(p_value::NUMERIC,2) END END');
 expect(numberBody).not.toMatch(/float|double|real|COALESCE/i);
});
const signBody=up.split('CREATE FUNCTION private.reporting_047_voucher_sign')[1].split('$$;')[0];
const signs=new Map([...signBody.matchAll(/\('(\d+)',(-?1)\)/g)].map(([,code,sign])=>[code,Number(sign)]));
test.each(voucher047Vectors)('audited voucher $tipo_cbte has sign $sign',({tipo_cbte,sign})=>expect(signs.get(String(tipo_cbte))??null).toBe(sign));
test('supported table is complete and unique; every legacy sign survives; other codes stay unknown',()=>{
 expect(signs.size).toBe(21);expect([...signBody.matchAll(/\('(\d+)',(-?1)\)/g)]).toHaveLength(21);
 for(const code of [1,2,6,7,11,12,201,202,206,207,211,212])expect(signs.get(String(code))).toBe(1);
 for(const code of [3,8,13,203,208,213])expect(signs.get(String(code))).toBe(-1);
 for(const code of ['0','19','33','51','82','505','001','17x'])expect(signs.has(code)).toBe(false);
 expect(signBody).toContain('WHERE code=p_code');expect(signBody).not.toMatch(/ELSE\s+1/i);
});
const old=up.split('CREATE TEMP VIEW reporting_047_expected_046 AS\n')[1].split(';\nDO $view_pin$')[0];
const repaired=up.split('CREATE OR REPLACE VIEW private.reporting_045_facts AS\n')[1].split(';\nDO $postflight$')[0];
test('pins frozen 046 view and all seven original reporting bodies before installing helpers',()=>{
 const previous=read('sql/046_reporting_currency_scope.sql').split('CREATE OR REPLACE VIEW private.reporting_045_facts AS\n')[1].split(';\nDO $postflight$')[0];
 expect(old).toBe(previous);
 const original=read('sql/045_management_reporting.sql');
 const bodies=[...original.matchAll(/CREATE FUNCTION ((?:public|private)\.(?:mica_reporting_\w+|reporting_045_(?:number|context)))\([\s\S]*?AS \$\$([\s\S]*?)\$\$;/g)];
 expect(bodies).toHaveLength(7);for(const [,,body] of bodies)expect(up).toContain(crypto.createHash('md5').update(body.trim()).digest('hex'));
 expect(up.indexOf('END; $view_pin$')).toBeLessThan(up.indexOf('CREATE FUNCTION private.reporting_047_number'));
 expect(up).toContain('047 requires installed 046');expect(up).toContain('helper exists: drift or partial installation');expect(up).toContain('installed 046 marker drift');
});
test('installed 045 and 046 files remain unchanged',()=>{
 for(const [path,hash] of [
  ['sql/045_management_reporting.sql','1d1918898dfd68971c2190524f3db0c11e1fdcec15e7a1f07bfb41e8b21a136f'],
  ['sql/045_management_reporting_down.sql','4be1c302bea037e9ea36d39be4088058308ff021771c3832075c9fcf95ba35dc'],
  ['sql/046_reporting_currency_scope.sql','001fac0058edcc00a572dc8fe2819e96453051526886b267f5aa7ed7be25589b'],
  ['sql/046_reporting_currency_scope_down.sql','13c2daa019b73457b082dc1e25b05bd30e567d995a55d85f177079c8a174091e']
 ])expect(crypto.createHash('sha256').update(read(path)).digest('hex')).toBe(hash);
});
test('projection scope keeps financial/manual branches, currencies, tenant/status predicates and security unchanged',()=>{
 expect(repaired.split('UNION ALL').slice(1)).toEqual(old.split('UNION ALL').slice(1));
 const currency=s=>s.split(' AS jurisdiction,\n')[1].split(' END AS currency,')[0];expect(currency(repaired)).toBe(currency(old));
 const joins=s=>s.split(' FROM public.eco_normalized_records')[1].split('\n)')[0];expect(joins(repaired)).toBe(joins(old));
 expect(repaired).toContain("private.reporting_047_voucher_sign(n.normalized_payload->>'tipo_cbte') AS sign");
 expect(repaired).toContain('THEN NULL ELSE sign*abs(total) END ELSE total END AS amount');
 expect(repaired).toContain('CASE WHEN total=0 AND (');
 expect(up).toContain('reporting function/ACL changed');expect(up).toContain('relation security changed');
 expect(up).toContain('relforcerowsecurity');expect(up).toContain('SET search_path=\'\'');
 expect(up).not.toMatch(/(?:UPDATE|DELETE FROM|INSERT INTO) (?:public\.eco_|private\.eco_)/);
 expect(up).not.toContain('CREATE OR REPLACE FUNCTION');
});
test('rollback pins helpers and view, restores exact saved view and drops only its own additions',()=>{
 expect(down).toContain('pg_get_viewdef');expect(down).toContain("||b.definition");expect(down).toContain('rollback helper/security drift');
 expect(down).toContain('pg_get_functiondef(p.oid)');expect(down).toContain('p.proacl::TEXT');expect(down).not.toContain('CASCADE');
 expect(down).toContain('DROP FUNCTION private.reporting_047_number(TEXT),private.reporting_047_voucher_sign(TEXT)');
 expect(down).not.toContain('DROP TABLE private.migration_046_reporting');
});
function dataWith(group=totalZero047Group){const data=reportingData();data.inputs.find(i=>i.kind==='PERIOD_ADJUSTMENT').payload.iva_compensation=0;data.groups=data.groups.filter(r=>r.kind!=='PURCHASES');data.groups.push({...group});return data;}
test('source total remains zero; valid net and IVA are independently available with missing amount',()=>{
 const before=JSON.stringify(totalZero047),data=dataWith(),model=buildModel(data);
 expect(oracle(totalZero047.netoGravado)+oracle(totalZero047.netoNoGravado)).toBe(totalZero047Group.net);
 expect(oracle(totalZero047.totalIva)).toBe(totalZero047Group.vat);
 expect(aggregateMetric(model,'purchases').value).toBe(23807198);
 expect(model.iva[0].lines.find(l=>l.code==='iva_cf').value).toBe(6145163);
 expect(buildReport(model,'IVA').missing).toEqual([]);expect(JSON.stringify(totalZero047)).toBe(before);
});
test('unknown sign leaves net/VAT unavailable rather than creating positive totals',()=>{
 const model=buildModel(dataWith({...totalZero047Group,net:null,vat:null,missing_net:1,missing_vat:1}));
 expect(aggregateMetric(model,'purchases').value).toBeNull();expect(buildReport(model,'IVA').missing.length).toBeGreaterThan(0);
});
test('046 USD policy remains unchanged even with recovered decimal precision',()=>{
 const data=dataWith();data.groups.push({...totalZero047Group,currency:'USD'});const model=buildModel(data);
 const purchases=aggregateMetric(model,'purchases');expect(purchases.value).toBeNull();expect(purchases.supported_value).toBe(23807198);expect(purchases.excluded_count).toBe(1);
 expect(model.iva[0].lines.find(l=>l.code==='iva_cf').value).toBeNull();
});
test('trusted endpoint still blocks genuinely missing VAT for review and close',async()=>{
 const data=dataWith({...totalZero047Group,vat:null,missing_vat:1}),writer=jest.fn();
 const handler=createReportingHandler({authenticate:async()=>({id:'actor'}),userClient:()=>({rpc:async name=>name==='get_my_operational_context'?{data:{organization_id:data.organization_id}}:{data}}),serviceClient:{rpc:writer}});
 for(const action of ['review','close']){
  const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({organization_id:data.organization_id,from:data.date_from,to:data.date_to,type:'IVA',action,input_hash:data.input_hash})}));expect(response.status).toBe(400);
 }expect(writer).not.toHaveBeenCalled();
});
test('tenant/context mismatch cannot access repaired reporting data',async()=>{
 const data=dataWith(),reader=jest.fn();
 const handler=createReportingHandler({authenticate:async()=>({id:'actor'}),userClient:()=>({rpc:async name=>name==='get_my_operational_context'?{data:{organization_id:'another-tenant'}}:reader()}),serviceClient:{rpc:jest.fn()}});
 const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer fixture'},body:JSON.stringify({organization_id:data.organization_id,from:data.date_from,to:data.date_to,type:'IVA',action:'data'})}));expect(response.status).toBe(400);expect(reader).not.toHaveBeenCalled();
});
