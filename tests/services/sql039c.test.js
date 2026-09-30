// Static contracts only. The prepared DB harness is never executed by Jest.
import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8');
const sql=read('sql/039c_functional_stabilization.sql');
test('all prior migrations including applied 039b retain exact SHA-256',()=>{
    for(const [path,hash] of Object.entries(JSON.parse(read('tests/fixtures/039c_preexisting_migrations.sha256.json'))))
        expect(crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex')).toBe(hash);
});
test('039c preflight fingerprints match the exact seven previous function bodies',()=>{
    const pairs=[...sql.split('$preflight$;')[0].matchAll(/\('([^']+\([^']*\))','([a-f0-9]{32})'\)/g)];
    expect(pairs).toHaveLength(7);
    for(const [,signature,hash] of pairs){
        const name=signature.split('(')[0];
        const path=name.startsWith('private.')?'sql/039b_operational_access_and_ux.sql':'sql/039_module_and_import_capabilities.sql';
        const body=read(path).match(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?\\$\\$;'))[0].split('$$')[1].replaceAll('\r','').trim();
        expect(crypto.createHash('md5').update(body).digest('hex')).toBe(hash);
    }
});
test('manual writes derive provenance server-side, validate context and keep independent permissions',()=>{
    const body=sql.split('CREATE FUNCTION public.mica_manual_records')[1].split('END; $$;')[0];
    for(const cap of ['VIEW','CREATE','EDIT','SOFT_DELETE']) expect(body).toContain("require_039_action('MANUAL_MOVEMENT_"+cap+"')");
    expect(body).toContain('private.active_org_id()');expect(body).toContain('private.current_profile_id()');
    expect(body).toContain('org IS DISTINCT FROM p_expected_org');
    expect(body).toContain('organization_id=org AND deleted_at IS NULL');expect(body).toContain('MICA_MANUAL_');
});
test('invitation never writes auth users or activates by email and revalidates assignment server-side',()=>{
    const body=sql.split('CREATE FUNCTION public.mica_invitation')[1].split('END; $$;')[0];
    expect(body).not.toMatch(/INSERT INTO auth\.users|UPDATE public\.eco_user_profiles/);
    expect(body).toContain('u.email_confirmed_at IS NOT NULL AND NOT p.is_active');
    expect(body).toContain('private.admin_038_target(target)');expect(body).toContain('private.admin_038_cap(code,sc,p_org)');
    expect(body).toContain('public.mica_admin_apply');expect(body).toContain("'activated',FALSE");
    expect(body).toContain('Incompatible or protected preset');expect(body).toContain('Invitation outside scope');
});
test('retry preserves guards and blocks existing business rows including deleted rows',()=>{
    const helper=sql.split('CREATE FUNCTION private.reuse_039c_file')[1].split('END; $$;')[0];
    expect(helper).toContain('pg_advisory_xact_lock');expect(helper).toContain('parent IS DISTINCT FROM f.import_id');
    expect(helper).toContain('eco_normalized_records');expect(helper).toContain('eco_financial_movements');
    expect(helper).not.toContain('deleted_at IS NULL');
    for(const name of ['persist_import_batch','persist_perceptions_batch','persist_financial_movements_batch']) {
        const body=sql.split('CREATE OR REPLACE FUNCTION public.'+name)[1].split('$$;')[0];
        expect(body).toContain('private.require_039_batch');expect(body).toContain('private.reuse_039c_file(p_import_id,v_hash)');
    }
});
test('prepared harness rolls back and rollback refuses to delete business or invitation data',()=>{
    const harness=read('tests/db/039c_functional_stabilization.sql'),down=read('sql/039c_functional_stabilization_down.sql');
    expect(harness).toContain('BEGIN;');expect(harness.trim().endsWith('ROLLBACK;')).toBe(true);
    for(const token of ['Stale context accepted','Manual bypassed DENY','Fiscal DENY ignored','Root edited','Duplicate email accepted','Artificial platform membership','Salary lineage not visible']) expect(harness).toContain(token);
    expect(down).toContain('preserve and review explicitly');expect(down).toContain('later grants/overrides');expect(down).not.toContain('CASCADE');
});
