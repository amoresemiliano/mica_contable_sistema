import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read = path => readFileSync(path,'utf8');
const up=read('sql/039_module_and_import_capabilities.sql');
const down=read('sql/039_module_and_import_capabilities_down.sql');
const db=read('tests/db/039_module_and_import_capabilities.sql');
test('previous migration bytes remain unchanged, including 036/037/037a/038', () => {
    const hashes=JSON.parse(read('tests/fixtures/039_preexisting_migrations.sha256.json'));
    for(const [path,hash] of Object.entries(hashes))
        expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(hash);
});
test('every replaced function has an exact repo-body preflight and secure search path', () => {
    const entries=[...up.matchAll(/-- Reviewed baseline: (\S+)\r?\n(CREATE OR REPLACE FUNCTION public\.(\w+)\([\s\S]*?\$\$;)/g)];
    expect(entries).toHaveLength(18);
    for(const [,file,definition,name] of entries) {
        const old=read('sql/'+file).match(new RegExp('CREATE OR REPLACE FUNCTION public\\.'+name+'\\([\\s\\S]*?\\$\\$;'))[0];
        const hash=createHash('md5').update(old.split('$$')[1].replace(/\r/g,'').trim()).digest('hex');
        expect(up).toContain(hash);
        expect(definition).toMatch(/SECURITY DEFINER/);
        expect(definition).toMatch(/SET search_path (?:TO |= )?''/);
        expect(definition).toMatch(/private.require_039_(action|import|batch)/);
        expect(definition).not.toMatch(/private.func_role\(|v_(caller_)?role\b/);
        // Preserve every canonical regex, including its closing SQL quote.
        // A corrupted $$; inside a regex prematurely closes the function body.
        const regexLiterals = sql => [...sql.matchAll(/~\*?\s*'(?:''|[^'])*'/g)].map(m => m[0]);
        expect(regexLiterals(definition)).toEqual(regexLiterals(old));
    }
    expect(up.indexOf('$preflight$;')).toBeLessThan(up.indexOf('CREATE TABLE'));
});

test('039 SQL artifacts have no regex anchor corrupted into a dollar-quote terminator', () => {
    for (const sql of [up, down, db, read('sql/039_preflight_readonly.sql')]) {
        expect(sql).not.toMatch(/~\*?\s*'[^'\r\n]*\$\$;/);
    }
    expect(up.match(/AS \$\$/g)).toHaveLength(22);
    expect(up.match(/\$\$/g)).toHaveLength(44);
    expect(up).toContain("IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN");
});
test('import authority has concrete source/action mapping and confirmed context helper', () => {
    expect(up).toContain('private.can_operate_mica_org(v_org,p_code)');
    for(const code of ['RECORD_VIEW','IMPORT_CREATE','BANK_IMPORT','PERCEPTION_IMPORT','PAYROLL_IMPORT'])
        expect(up).toContain("require_039_action('"+code+"')");
    expect(up).not.toContain("can_platform('ACCESS_ANY_ORG')");
    expect(up).not.toMatch(/CREATE OR REPLACE FUNCTION private\.can_org/);
    expect(up).toContain('wrong endpoint');
    const guard=up.split('CREATE FUNCTION private.require_039_import(')[1].split('END; $$;')[0];
    expect(guard).not.toMatch(/ARCA_RECIBIDOS|ARCA_EMITIDOS|'COMPRA'|'VENTA'/);
    expect(db).toContain('Fiscal received import opened without specific capability');
    expect(db).toContain('Fiscal issued import opened without specific capability');
});

test('read-only LIVE checks cover every expected body hash and expose ACL/arguments/results', () => {
    const checks=read('sql/039_preflight_readonly.sql');
    const expected=[...up.matchAll(/\('public\.[^']+','([0-9a-f]{32})'\)/g)];
    expect(expected).toHaveLength(36);
    for(const [,hash] of expected) expect(checks).toContain(hash);
    for(const field of ['pg_get_function_arguments','pg_get_function_result','explicit_acl','anon_execute','authenticated_execute','matches_up_preflight'])
        expect(checks).toContain(field);
    const code=checks.replace(/--[^\n]*/g,'');
    expect(code).not.toMatch(/\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|DO|GRANT|REVOKE|set_config)\b/i);
});

test('036 through 038 do not replace the eighteen guarded RPCs', () => {
    const names=[...up.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\(/g)].map(m=>m[1]);
    for(const file of ['036_owner_core_and_delegation_guard','037_platform_tenant_operation','037a_fix_guard_036_grant','038_mica_administration']) {
        const previous=read('sql/'+file+'.sql');
        for(const name of names) expect(previous).not.toMatch(new RegExp('CREATE OR REPLACE FUNCTION public\\.'+name+'\\('));
    }
});
test('direct table reads and storage cannot bypass capabilities; rollback removes only own policies', () => {
    for(const table of ['eco_normalized_records','eco_financial_movements','eco_source_imports','eco_source_files','eco_import_rows','eco_import_issues']) {
        expect(up).toContain('CREATE POLICY guard_039_read ON public.'+table+' AS RESTRICTIVE');
        expect(down).toContain('DROP POLICY guard_039_read ON public.'+table);
    }
    expect(up).toContain("public.mica_storage_import_allowed(name,'write')");
    expect(up).toContain("IF r.signature LIKE 'public.%'");
    expect(up).toContain('GRANT EXECUTE ON FUNCTION %s TO authenticated');
    expect(down).toContain('pg_get_functiondef(oid)=b.installed_definition');
    expect(down).toContain('EXECUTE b.definition');
    expect(down).not.toMatch(/\bCASCADE\b/i);
});
test('DB harness is transaction-contained and tests real authenticated RPCs without private access under restricted role', () => {
    expect(db).toContain('BEGIN;'); expect(db.trim()).toMatch(/ROLLBACK;$/);
    for(const block of db.split('SET LOCAL ROLE authenticated;').slice(1)) {
        expect(block.split('RESET ROLE;')[0]).not.toMatch(/private\./);
    }
    for(const reason of ['Scope/root bypassed','PAYROLL DENY','Artificial membership','Batch ignored','Inactive organization','Reader bypassed VIEW'])
        expect(db).toContain(reason);
});
test('direct navigation guards before rendering and OCR cannot fabricate records', () => {
    expect(read('src/js/ui.js')).toContain('if (!appStore.canVisitModule(tabId)) return false;');
    const ocr=read('src/js/ocr.js');
    expect(ocr).toContain('canOcrAction(action)');
    expect(ocr).not.toMatch(/Math.random|setTimeout|items.push/);
});
