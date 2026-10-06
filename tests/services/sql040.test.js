// Static SQL contract verification only; no SQL execution or database connection.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/040_organization_profile_fields.sql');
const down=read('sql/040_organization_profile_fields_down.sql');
const fn=(sql,name)=>sql.match(new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?END; \\$\\$;`))[0];
const apply=fn(up,'mica_admin_apply'),rpcRead=fn(up,'mica_admin_read');
const oldApply=fn(read('sql/039i_fix_mica_admin_apply_ambiguity.sql'),'mica_admin_apply');
const oldRead=fn(read('sql/039h_operational_administration.sql'),'mica_admin_read');
const fields=['phone','email','contact_person','website','address'];
const extra=fields.map(f=>`'${f}'`).join(',');
const organization=apply.split("IF p_action='organization' THEN")[1].split("ELSIF p_action='preset'")[0];

test('allowlist accepts exactly the existing and five profile fields; rejects arbitrary keys',()=>{
 const list=organization.match(/IF k NOT IN \(([^)]+)\)/)[1].split(',').map(s=>s.replaceAll("'",''));
 expect(list).toEqual(['id','name','legal_name','trade_name','tax_id','is_active',...fields]);
 expect(list).not.toContain('unexpected');
 expect(organization).toContain("FOR k IN SELECT jsonb_object_keys(p_data) LOOP");
 expect(organization).toContain("RAISE EXCEPTION 'Unsupported organization field %',k");
});

test('CREATE maps every profile field to its payload value in matching column order',()=>{
 const insert=organization.match(/INSERT INTO public\.eco_organizations\(([^)]+)\)[\s\S]*?RETURNING id INTO result/)[0];
 expect(insert).toContain(`is_active,${fields.join(',')})`);
 expect(insert).toContain(`TRUE,${fields.map(f=>`p_data->>'${f}'`).join(',')}) RETURNING`);
});

test('UPDATE allows profile-only changes and preserves each absent field, permitting explicit NULL',()=>{
 expect(organization).toContain(`ARRAY['name','legal_name','trade_name','tax_id','is_active',${extra}]`);
 for(const field of fields) {
  expect(organization).toContain(`${field}=CASE WHEN p_data?'${field}' THEN p_data->>'${field}' ELSE ${field} END,`);
  expect(organization).not.toContain(`${field}=COALESCE(`);
 }
});

test('profile-only UPDATE runs the existing authorization and active explicit scope check',()=>{
 expect(organization).toContain(`IF p_data ?| ARRAY['name','legal_name','trade_name','tax_id',${extra}] THEN\n        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_UPDATE',NULL);`);
 for(const text of ["admin_038_authorize(NULL,'ORGANIZATION_CREATE',NULL)","admin_038_authorize(NULL,'ORGANIZATION_ARCHIVE',NULL)",
  'IF NOT private.is_platform_owner() AND NOT EXISTS (SELECT 1 FROM private.eco_platform_org_scopes',
  'WHERE user_profile_id=actor AND organization_id=result AND is_active',"RAISE EXCEPTION 'Organization outside explicit scope' USING ERRCODE='42501'",
  'SELECT * INTO STRICT old_org FROM public.eco_organizations WHERE id=result FOR UPDATE']) expect(organization).toContain(text);
});

test('full canonical apply differs ONLY by reviewed profile allowlist, permission triggers and persistence',()=>{
 const restored=apply.replace(`'is_active',${extra}) THEN RAISE EXCEPTION 'Unsupported`,"'is_active') THEN RAISE EXCEPTION 'Unsupported")
  .replace(`ARRAY['name','legal_name','trade_name','tax_id','is_active',${extra}]`,"ARRAY['name','legal_name','trade_name','tax_id','is_active']")
  .replace(`ARRAY['name','legal_name','trade_name','tax_id',${extra}]`,"ARRAY['name','legal_name','trade_name','tax_id']")
  .replace(`is_active,${fields.join(',')})`,'is_active)')
  .replace(`TRUE,${fields.map(f=>`p_data->>'${f}'`).join(',')}) RETURNING`,'TRUE) RETURNING')
  .replace(fields.map(f=>`        ${f}=CASE WHEN p_data?'${f}' THEN p_data->>'${f}' ELSE ${f} END,\n`).join(''),'');
 expect(restored).toBe(oldApply);
});

test('explicit readback adds only five JSON properties; all visibility rules remain identical',()=>{
 const addition=','+fields.map(f=>`'${f}',${f}`).join(',');
 expect(rpcRead).toContain(`'is_active',is_active${addition}))`);
 expect(rpcRead.replace(addition,'')).toBe(oldRead);
});

test('rollback restores BOTH exact canonical functions before dropping any columns',()=>{
 expect(fn(down,'mica_admin_apply')).toBe(oldApply);
 expect(fn(down,'mica_admin_read')).toBe(oldRead);
 expect(down.indexOf(oldRead)+oldRead.length).toBeLessThan(down.indexOf('ALTER TABLE public.eco_organizations DROP'));
 for(const f of fields) {
  expect(up).toContain(`ADD COLUMN IF NOT EXISTS ${f} TEXT;`);
  expect(down).toContain(`DROP COLUMN IF EXISTS ${f};`);
 }
 expect(down.replace(/--[^\n]*/g,'')).not.toContain('CASCADE');
});

test('transactional migrations pin canonical bodies and preserve OID, owner, ACL, definer and fixed path',()=>{
 const hash=f=>createHash('md5').update(f.split('AS $$')[1].split('$$;')[0].trim()).digest('hex');
 for(const sql of [up,down]) {
  for(const body of [oldApply,oldRead,apply,rpcRead]) expect(sql).toContain(hash(body));
  for(const text of ['BEGIN;','pg_advisory_xact_lock(380038)',"current_user<>'postgres'",
   "pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef",`p.proconfig=ARRAY['search_path=""']::TEXT[]`,
   'p.proowner IS DISTINCT FROM saved.proowner','p.proacl IS DISTINCT FROM saved.proacl',
   'p.prosecdef IS DISTINCT FROM saved.prosecdef','p.proconfig IS DISTINCT FROM saved.proconfig',
   'p.oid IS NULL','ON COMMIT DROP']) expect(sql).toContain(text);
  expect(sql.trim().endsWith('COMMIT;')).toBe(true);
  expect(sql).not.toMatch(/(?:GRANT|REVOKE|ALTER FUNCTION|DROP FUNCTION|CREATE POLICY|ALTER POLICY|DISABLE TRIGGER)\s/);
 }
});

test('prepared DB harness covers create/update/partial/null/rejection/readback and authorization; never executed here',()=>{
 const harness=read('tests/db/040_organization_profile_fields.sql');
 for(const text of ['040 create/readback mismatch','040 update/readback mismatch','040 partial update lost fields',
  '040 explicit null failed','040 unsupported field accepted','040 out-of-scope update accepted',
  '040 hidden organization leaked','040 missing UPDATE allowed','040 denied UPDATE allowed',
  'Creation without capability allowed','Archive allowed','DENY failed to override base']) expect(harness).toContain(text);
 expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});
