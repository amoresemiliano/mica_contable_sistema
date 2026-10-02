// Static verification only: no PostgreSQL connection or SQL execution.
import fs from 'node:fs';
import crypto from 'node:crypto';
const read=path=>fs.readFileSync(path,'utf8');
const up=read('sql/039d_retry_source_file_flag.sql');
const down=read('sql/039d_retry_source_file_flag_down.sql');
const oldFlag="'source_file_reused', v_orig_file IS NOT NULL";
const newFlag="'source_file_reused', v_orig_file.id IS NOT NULL";
const body=read('sql/039c_functional_stabilization.sql')
    .match(/CREATE OR REPLACE FUNCTION public\.request_failed_import_retry\([\s\S]*?\$\$;/)[0].split('$$')[1];

test('applied 039c UP and DOWN remain byte-for-byte intact',()=>{
    const hashes={
        'sql/039c_functional_stabilization.sql':'28b4c70ef294d2d9c8214f8b13f5ef8ce5dc8a1216f1364f6c12d697d63d2e3e',
        'sql/039c_functional_stabilization_down.sql':'047036337190273050529fc2c0c7272e5953990effc0319528a4c2bf300a4cdd'
    };
    for(const [path,hash] of Object.entries(hashes))
        expect(crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex')).toBe(hash);
});

test('039d preflight pins exact defective body and installed definition; mutation is only the flag',()=>{
    expect(up.split('$expected039c$')[1]).toBe(body);
    expect(up).toContain("pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'");
    expect(up).toContain('NOT p.prosecdef');
    expect(up).toContain('p.proconfig IS DISTINCT FROM ARRAY[\'search_path=""\']::TEXT[]');
    expect(up).toContain("to_regclass('private.migration_039c_functions') IS NULL");
    expect(up).toContain('installed_definition=pg_get_functiondef(p.oid)');
    expect(up.split('$old$')[1]).toBe(oldFlag);
    expect(up.split('$new$')[1]).toBe(newFlag);
    expect(body.split(oldFlag)).toHaveLength(2);
    expect(up).toContain('replacement:=replace(r.definition,');
    expect(up).toContain('EXECUTE replacement;');
    expect(up).not.toMatch(/ALTER FUNCTION|GRANT .*FUNCTION|REVOKE .*FUNCTION/);
    expect(up).toContain('proacl IS DISTINCT FROM r.acl');
    expect(up).toContain('proowner IS DISTINCT FROM r.owner_oid');
});

test('rollback requires exact corrected body and snapshot, restores backup preserving ACL',()=>{
    expect(down.split('$expected039d$')[1]).toBe(body.replace(oldFlag,newFlag));
    expect(down).toContain('pg_get_functiondef(p.oid) IS DISTINCT FROM r.installed_definition');
    expect(down).toContain('p.proacl IS DISTINCT FROM r.acl');
    expect(down).toContain('EXECUTE r.definition;');
    expect(down).toContain('pg_get_functiondef(p.oid) IS DISTINCT FROM r.definition');
    expect(down).not.toMatch(/CASCADE|DROP FUNCTION|UPDATE public\.|DELETE FROM/);
    expect(down.match(/DROP TABLE/g)).toHaveLength(1);
});

test('harness retains nullable metadata and verifies identities and independent business-row rejection',()=>{
    const h=read('tests/db/039d_retry_source_file_flag.sql');
    expect(h.trim().endsWith('ROLLBACK;')).toBe(true);
    expect(h).toContain("original_path,NULL,1,hash");
    expect(h).toContain("(retry->>'source_file_reused')::BOOLEAN IS NOT TRUE");
    expect(h).toContain('private.reuse_039c_file(retry_id,hash) IS DISTINCT FROM source_id');
    expect(h).toContain("(result->>'file_id')::UUID IS DISTINCT FROM source_id");
    for(const text of ['Wrong retry parent reused file','Cross-organization retry accepted',
        'Business rows allowed reuse','Business rows allowed retry','Source metadata/hash/path changed or duplicated']) expect(h).toContain(text);
    expect(h.indexOf('SET accepted_rows=0')).toBeLessThan(h.indexOf('Business rows allowed reuse'));
    const legacy=read('tests/db/039c_functional_stabilization.sql');
    expect(legacy).toContain("(retry->>'source_file_reused')::BOOLEAN IS NOT TRUE");
    expect(legacy).toContain("(result->>'file_id')::UUID IS DISTINCT FROM file_id");
    expect(legacy).toContain('eco_source_files(import_id,organization_id,original_name,storage_path,size_bytes,sha256_hash,source_type)');
});
