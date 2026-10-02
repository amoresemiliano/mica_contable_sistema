// Review artifacts only. Does not connect to a database or execute SQL.
import fs from 'node:fs';
import { createHash } from 'node:crypto';
const check = process.argv.includes('--check');
const read = p => fs.readFileSync(p, 'utf8').replaceAll('\r', '');
const quote = s => "'" + s.replaceAll("'", "''") + "'";
function output(p, value) {
    if (check) { if (!fs.existsSync(p) || read(p) !== value) throw Error('Outdated: ' + p); }
    else fs.writeFileSync(p, value);
}
const specs = [
    ['public.update_record_classification(uuid,uuid,uuid)', '039_module_and_import_capabilities.sql'],
    ['public.update_movement_classification(uuid,uuid,uuid)', '039_module_and_import_capabilities.sql'],
    ['public.get_operational_records_page(uuid,uuid,integer)', '037_platform_tenant_operation.sql'],
    ['public.get_operational_financials_page(uuid,uuid,integer)', '037_platform_tenant_operation.sql']
].map(([signature, file]) => {
    const sql = read('sql/' + file), name = signature.split('(')[0];
    const start = sql.indexOf('CREATE OR REPLACE FUNCTION ' + name + '(');
    if (start < 0) throw Error(name);
    const definition = sql.slice(start, sql.indexOf('$$;', sql.indexOf('AS $$', start)) + 3);
    const body = definition.split('AS $$')[1].split('$$;')[0].trim();
    let next = definition;
    if (name.includes('update_')) next = next.replace('  IF FOUND THEN',
        "  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Classification target unavailable in the active organization' USING ERRCODE='42501';\n  END IF;\n  IF FOUND THEN");
    else if (name.includes('records_page')) next = next.replace("'categoria', r.categoria, 'confirmada', r.confirmada,",
        "'category_id', r.category_id, 'activity_id', r.activity_id,\n    'updated_at', r.updated_at, 'updated_by', r.updated_by,\n    'confirmada', (r.category_id IS NOT NULL),");
    else next = next.replace("'fecha', f.fecha, 'periodo', f.periodo,",
        "'fecha', f.fecha, 'periodo', f.periodo,\n    'category_id', f.category_id, 'activity_id', f.activity_id,\n    'updated_at', f.updated_at, 'updated_by', f.updated_by,\n    'confirmada', (f.category_id IS NOT NULL),");
    if (next === definition) throw Error('No replacement: ' + name);
    return { signature, next, hash: createHash('md5').update(body).digest('hex') };
});
const values = specs.map(s => `(${quote(s.signature)},${quote(s.hash)})`).join(',\n');
output('sql/039e_classification_consistency.sql', `-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; human execution after LIVE preflight.
BEGIN;
DO $preflight$
DECLARE v_spec RECORD;
BEGIN
  IF to_regclass('private.migration_039d_retry') IS NULL THEN RAISE EXCEPTION '039d required'; END IF;
  IF to_regclass('private.migration_039e_functions') IS NOT NULL THEN RAISE EXCEPTION '039e already present'; END IF;
  FOR v_spec IN SELECT * FROM (VALUES ${values}) x(signature,hash) LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_spec.signature)
      AND pg_get_userbyid(proowner)='postgres' AND prosecdef AND proconfig=ARRAY['search_path=""']::TEXT[]
      AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v_spec.hash) THEN
      RAISE EXCEPTION '039e LIVE definition differs: %',v_spec.signature;
    END IF;
  END LOOP;
END; $preflight$;
CREATE TABLE private.migration_039e_functions(signature TEXT PRIMARY KEY, definition TEXT NOT NULL,
  installed_definition TEXT, owner_oid OID NOT NULL, acl ACLITEM[]);
ALTER TABLE private.migration_039e_functions ENABLE ROW LEVEL SECURITY;
DO $backup$
DECLARE v_grantee RECORD; v_who TEXT;
BEGIN
  FOR v_grantee IN SELECT DISTINCT a.grantee FROM pg_class c,
    LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE c.oid='private.migration_039e_functions'::regclass AND a.grantee<>c.relowner LOOP
    v_who:=CASE WHEN v_grantee.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(v_grantee.grantee)) END;
    EXECUTE format('REVOKE ALL ON TABLE private.migration_039e_functions FROM %s',v_who);
  END LOOP;
END; $backup$;
INSERT INTO private.migration_039e_functions(signature,definition,owner_oid,acl)
SELECT x.signature,pg_get_functiondef(p.oid),p.proowner,p.proacl
FROM (VALUES ${values}) x(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(x.signature);

${specs.map(s => s.next).join('\n\n')}

DO $verify$
DECLARE v_saved RECORD;
BEGIN
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
      AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e owner/ACL changed: %',v_saved.signature;
    END IF;
  END LOOP;
  UPDATE private.migration_039e_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
END; $verify$;
COMMIT;
`);
output('sql/039e_classification_consistency_down.sql', `-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Preserve all classification data.
BEGIN;
DO $restore$
DECLARE v_saved RECORD;
BEGIN
  IF to_regclass('private.migration_039e_functions') IS NULL THEN RAISE EXCEPTION '039e not installed'; END IF;
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    IF pg_get_functiondef(to_regprocedure(v_saved.signature)) IS DISTINCT FROM v_saved.installed_definition
      OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
        AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e later definition/owner/ACL drift: %',v_saved.signature;
    END IF;
  END LOOP;
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    EXECUTE v_saved.definition;
    IF pg_get_functiondef(to_regprocedure(v_saved.signature)) IS DISTINCT FROM v_saved.definition
      OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
        AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e restoration differs: %',v_saved.signature;
    END IF;
  END LOOP;
END; $restore$;
DROP TABLE private.migration_039e_functions;
COMMIT;
`);
output('sql/039e_preflight_readonly.sql', `-- MICA ourzapkjykzlwsjunzmd. PREPARED, NOT EXECUTED. SELECT only.
SELECT current_database(),current_user,to_regclass('private.migration_039d_retry') AS requires_039d,
  to_regclass('private.migration_039e_functions') AS must_be_absent;
SELECT x.signature,x.hash AS expected_body_md5,p.oid::regprocedure AS actual_signature,
  pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,p.proacl,
  md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS actual_body_md5,
  pg_get_functiondef(p.oid) AS definition
FROM (VALUES ${values}) x(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature);
SELECT table_name,column_name,data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('eco_normalized_records','eco_financial_movements')
  AND column_name IN ('id','organization_id','category_id','activity_id','updated_at','updated_by','deleted_at')
ORDER BY table_name,column_name;
`);
console.log(check ? '039e artifacts match (no SQL executed).' : '039e artifacts generated (no SQL executed).');
