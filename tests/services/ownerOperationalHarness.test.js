// Text-only regression guards: never connect to a DB or execute the SQL harness.
import { readFileSync } from 'node:fs';
const sql = readFileSync('tests/db/035_owner_operational_context.sql', 'utf8').replace(/^\uFEFF/, '');
const code = sql.replace(/--[^\n]*/g, '');

test('035 harness is standalone SQL Editor input without client substitution or commands', () => {
    expect(code).not.toMatch(/(?<!:):(?:'[A-Za-z_]\w*'|"[A-Za-z_]\w*"|[A-Za-z_]\w*)/);
    expect(code).not.toMatch(/^\s*\\/m);
    expect(code.trim()).toMatch(/^BEGIN;/);
    expect(code.trim()).toMatch(/ROLLBACK;$/);
    expect(code).toContain('DO $harness$');
    expect(code).not.toMatch(/\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|GRANT|REVOKE|CREATE\s+(?:TABLE|FUNCTION))\b/i);
});

test('existing actors are discovered by effective capabilities and JWT claims stay paired', () => {
    expect(code).toContain('FROM public.eco_user_profiles');
    expect(code).toContain("private.can_platform('ACCESS_ANY_ORG')");
    expect(code).toContain("ELSIF private.can_platform('CATALOG_ASSIGN_ANY_ORG')");
    expect(code).toContain('IF v_owner IS NULL THEN RAISE EXCEPTION');
    expect(code).toContain('IF v_catalog_only IS NULL THEN RAISE EXCEPTION');
    expect(code.match(/set_config\('request.jwt.claim.sub'/g)).toHaveLength(4);
    expect(code.match(/set_config\('request.jwt.claims'/g)).toHaveLength(4);
});

test('no direct private access occurs under authenticated or anon', () => {
    let restricted = false;
    let switches = 0;
    for (const line of code.split(/\r?\n/)) {
        if (/SET LOCAL ROLE (authenticated|anon)/.test(line)) { restricted = true; switches++; }
        if (/RESET ROLE/.test(line)) restricted = false;
        if (restricted) expect(line).not.toMatch(/\bprivate\s*\./i);
    }
    expect(switches).toBe(3);
    expect(restricted).toBe(false);
});

test('harness retains public boundary, ACL, rollback and bounded reader assertions', () => {
    for (const rpc of ['list_operational_org_targets', 'switch_superadmin_org_context',
        'get_my_operational_context', 'get_operational_snapshot',
        'get_operational_records_page', 'get_operational_financials_page']) {
        expect(code).toContain(`public.${rpc}(`);
    }
    expect(code.match(/PERFORM public.switch_superadmin_org_context\(NULL\)/g)).toHaveLength(3);
    expect(code).toContain("has_function_privilege('anon'");
    expect(code).toContain("has_function_privilege('authenticated'");
    expect(code).toContain('a.grantee = 0');
    expect(code).toContain('v_page_count > 2');
    expect(code).toContain('v_total <> v_expected_count');
    expect(code).toContain('v_previous IS NOT NULL');
    expect(code).toContain("v_snapshot ? 'records' OR v_snapshot ? 'financials'");
    expect(code).toContain('ARRAY[v_missing, v_inactive]');
});
