// Static review guards only: these tests do NOT execute SQL or prove LIVE compatibility.
import { readFileSync } from 'node:fs';
const up = readFileSync('sql/035_owner_operational_context.sql', 'utf8');
const down = readFileSync('sql/035_owner_operational_context_down.sql', 'utf8');
const body = name => up.split(`FUNCTION public.${name}(`)[1].split('$$;')[0];

test('035 exposes explicit JSON fields and keeps historical rows out of the small snapshot', () => {
    expect(up).not.toMatch(/to_jsonb\s*\(|row_to_json\s*\(|SELECT\s+[rf]\.\*/i);
    const snapshot = body('get_operational_snapshot');
    expect(snapshot).not.toMatch(/eco_normalized_records|eco_financial_movements/);
    expect(snapshot).toContain("private.can_org(p_org_id, 'ORG_VIEW')");
    expect(snapshot).toContain("private.can_org(p_org_id, 'CATALOG_ORG_VIEW')");
    expect(snapshot).toContain('WHERE v_rates');
    for (const name of ['get_operational_records_page', 'get_operational_financials_page']) {
        const reader = body(name);
        expect(reader).toContain("private.can_org(p_org_id, 'RECORD_VIEW')");
        expect(reader).toContain("private.can_platform('ACCESS_ANY_ORG')");
        expect(reader).toContain('p_org_id IS DISTINCT FROM private.active_org_id()');
        expect(reader).toContain('p_limit > 500');
        expect(reader).toContain('LIMIT p_limit');
        expect(reader).not.toContain('jsonb_agg');
        expect(reader).toContain('jsonb_strip_nulls(jsonb_build_object(');
    }
    expect(up).not.toMatch(/CREATE(?: OR REPLACE)? FUNCTION private\.can_(org|platform)/);
});

test('preflight and LIVE backup precede every RPC replacement', () => {
    const beforeFunctions = up.slice(0, up.indexOf('CREATE OR REPLACE FUNCTION'));
    expect(beforeFunctions).toContain('pg_attribute');
    expect(beforeFunctions).toContain('pg_constraint');
    expect(beforeFunctions).toContain('pg_trigger');
    expect(beforeFunctions).toContain('pg_get_functiondef(p.oid)');
    expect(beforeFunctions).toContain('aclexplode');
    expect(beforeFunctions).toContain('new RPC already exists');
    expect(beforeFunctions).toContain('unsupported required insert column');
});

test('down restores the captured definition and ACL and drops exactly the five new RPCs', () => {
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('b.owner_name');
    expect(down).toContain("a.entry->>'grantor'");
    expect(down).toContain('WITH GRANT OPTION');
    expect(down).toContain('restored ACL differs');
    expect(down).not.toMatch(/DROP FUNCTION.*switch_superadmin_org_context/);
    expect(down).not.toMatch(/DROP (?:FUNCTION|TABLE).*CASCADE/);
    expect([...down.matchAll(/^DROP FUNCTION public\.(\w+)/gm)].map(m => m[1]).sort()).toEqual([
        'get_my_operational_context', 'get_operational_financials_page', 'get_operational_records_page',
        'get_operational_snapshot', 'list_operational_org_targets'
    ]);
});
