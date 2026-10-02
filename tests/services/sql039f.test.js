// Static regression checks only. No database connection or SQL execution.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read=p=>readFileSync(p,'utf8').replaceAll('\r','');
const up=read('sql/039f_fix_bulk_classification_audit.sql');
const down=read('sql/039f_fix_bulk_classification_audit_down.sql');
const baseline=read('sql/039_module_and_import_capabilities.sql')
    .match(/CREATE OR REPLACE FUNCTION public\.bulk_update_record_classification\([\s\S]*?AS \$\$([\s\S]*?)\$\$;/)[1];
const old=up.match(/\$old\$([\s\S]*?)\$old\$/)[1];
const replacement=up.match(/\$new\$([\s\S]*?)\$new\$/)[1];
test('039f changes only the defective audit insert in the exact inherited bulk body',()=>{
    expect(up.match(/\$expected039e\$([\s\S]*?)\$expected039e\$/)[1]).toBe(baseline);
    expect(old).toBe(baseline.match(/INSERT INTO public\.eco_audit_events[\s\S]*?;/)[0]);
    expect(replacement).toBe("INSERT INTO public.eco_audit_events (organization_id, event_type)\n    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION');");
    expect(down.match(/\$expected039f\$([\s\S]*?)\$expected039f\$/)[1]).toBe(baseline.replace(old,replacement));
    expect(up).toContain('EXECUTE replacement;');
    expect(up.match(/EXECUTE replacement;/g)).toHaveLength(1);
    expect(up).not.toMatch(/GRANT |CREATE POLICY|ALTER POLICY/);
});
test('039f requires 039e, exact inherited installed definition and postgres security metadata',()=>{
    for(const text of ["to_regclass('private.migration_039e_functions')",'FROM private.migration_039_functions',
        'installed_definition=pg_get_functiondef(p.oid)',"pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'",
        'NOT p.prosecdef',`p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[]`,
        'proowner IS DISTINCT FROM r.owner_oid OR proacl IS DISTINCT FROM r.acl',
        'ALTER TABLE private.migration_039f_bulk_audit ENABLE ROW LEVEL SECURITY',
        'aclexplode', 'REVOKE ALL ON TABLE private.migration_039f_bulk_audit']) expect(up).toContain(text);
});
test('039f DOWN refuses drift and restores the exact saved definition and ACL without cascade',()=>{
    for(const text of ['IS DISTINCT FROM r.installed_definition','p.proowner IS DISTINCT FROM r.owner_oid',
        'p.proacl IS DISTINCT FROM r.acl','EXECUTE r.definition;',
        'pg_get_functiondef(p.oid) IS DISTINCT FROM r.definition']) expect(down).toContain(text);
    expect(down).not.toMatch(/CASCADE|DELETE FROM|DROP FUNCTION/);
});
test('039e UP and DOWN remain byte-for-byte intact',()=>{
    for(const [file,hash] of [
        ['sql/039e_classification_consistency.sql','0b89ece41e32c372e23227800bee1ad1ced3d60bab20641db2f1d86d79e131fb'],
        ['sql/039e_classification_consistency_down.sql','84873fa6ada23c4539a8b6edf4accdf433253d3c14500378026aba1b8fcb1ca9']])
        expect(createHash('sha256').update(readFileSync(file)).digest('hex')).toBe(hash);
});
test('all audit references in 039e UP use actual schema columns; DOWN adds none',()=>{
    const schema=read('sql/004_audit.sql').match(/CREATE TABLE public\.eco_audit_events \(([\s\S]*?)\n\);/)[1];
    const columns=[...schema.matchAll(/^\s*(\w+)\s+(?:UUID|TEXT|TIMESTAMPTZ)/gm)].map(m=>m[1]);
    expect(columns).toEqual(['id','organization_id','event_type','created_at']);
    const e=read('sql/039e_classification_consistency.sql');
    const inserts=[...e.matchAll(/INSERT INTO public\.eco_audit_events \(([^)]+)\)/g)];
    expect(inserts).toHaveLength(2);
    expect(e.match(/eco_audit_events/g)).toHaveLength(2);
    for(const [,list] of inserts) for(const col of list.split(',').map(c=>c.trim())) expect(columns).toContain(col);
    expect(read('sql/039e_classification_consistency_down.sql')).not.toContain('eco_audit_events');
});
test('039f prepared harness covers persistence, count, audit, tenant isolation, DENY and zero matches',()=>{
    const harness=read('tests/db/039f_fix_bulk_classification_audit.sql');
    for(const text of ['SET LOCAL ROLE authenticated','Incorrect rows_affected','Classification not persisted',
        'Valid audit event missing','Other organization changed','Bulk DENY ignored',
        'Zero matches must return zero','Zero matches or DENY mutated rows',
        'Zero matches, DENY or cross-tenant audit contract violated']) expect(harness).toContain(text);
    expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
});
