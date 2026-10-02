import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read = p => readFileSync(p,'utf8');
const up=read('sql/039e_classification_consistency.sql'), down=read('sql/039e_classification_consistency_down.sql');
test('039e preserves every prior tracked SQL file byte-for-byte',()=>{
    for(const [path,hash] of Object.entries(JSON.parse(read('tests/fixtures/039e_preexisting_migrations.sha256.json'))))
        expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(hash);
});
test('039e replaces exactly two writes and two readers; no grants or business-data migration',()=>{
    expect(up.match(/CREATE OR REPLACE FUNCTION [^(]+/g)).toEqual([
        'CREATE OR REPLACE FUNCTION public.update_record_classification',
        'CREATE OR REPLACE FUNCTION public.update_movement_classification',
        'CREATE OR REPLACE FUNCTION public.get_operational_records_page',
        'CREATE OR REPLACE FUNCTION public.get_operational_financials_page']);
    expect(up).not.toMatch(/GRANT |CREATE POLICY|ALTER POLICY|UPDATE public\.eco_(?:role|capabilit)/);
    expect(up.match(/PERFORM private.require_039_action\('RECORD_CLASSIFY'\)/g)).toHaveLength(2);
    expect(up.match(/Classification target unavailable/g)).toHaveLength(2);
    expect(up).toContain("'category_id', r.category_id, 'activity_id', r.activity_id");
    expect(up).toContain("'category_id', f.category_id, 'activity_id', f.activity_id");
    expect(up.match(/p_org_id IS DISTINCT FROM private.active_org_id\(\)/g)).toHaveLength(2);
});
test('preflight checks body and security metadata, rollback restores exact definitions without deleting records',()=>{
    expect(up).toContain('md5(btrim(replace(prosrc');expect(up).toContain("pg_get_userbyid(proowner)='postgres'");
    expect(up).toContain('proacl IS NOT DISTINCT FROM v_saved.acl');
    expect(down).toContain('IS DISTINCT FROM v_saved.installed_definition');expect(down).toContain('EXECUTE v_saved.definition');
    expect(down).not.toMatch(/DELETE FROM|CASCADE|DROP FUNCTION/);
});
test('prepared rollback harness exercises real persisted readback, DENY, bulk and cross-tenant no-op rejection',()=>{
    const sql=read('tests/db/039e_classification_consistency.sql');
    for(const text of ['SET LOCAL ROLE authenticated','Record readback differs','Movement readback differs','Bulk clear not reflected',
        'Cross-tenant record fake success','Cross-tenant movement fake success','Record DENY ignored','Movement DENY ignored',
        'Bulk DENY ignored','Record refresh lost classification','Canonical columns not persisted']) expect(sql).toContain(text);
    expect(sql.trim().endsWith('ROLLBACK;')).toBe(true);
});
