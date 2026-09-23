import { readFileSync } from 'node:fs';

const sql = readFileSync('sql/030_separate_assignment_and_activation.sql', 'utf8');
const down = readFileSync('sql/030_separate_assignment_and_activation_down.sql', 'utf8');

test('capability RPC is caller-only, read-only, hardened and included in rollback snapshot', () => {
    const body = definition('public.get_my_catalog_capabilities');
    expect(body).toContain('get_my_catalog_capabilities()');
    expect(body).toContain("auth.uid() IS NULL");
    expect(body).toContain("STABLE SECURITY DEFINER SET search_path = ''");
    for (const capability of ['GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG', 'ACCESS_ANY_ORG']) {
        expect(body).toContain(`private.can_platform('${capability}')`);
    }
    expect(body).not.toMatch(/\b(?:INSERT|UPDATE|DELETE)\b/);
    expect(sql.split('ALTER TABLE public.eco_org_economic_activities')[0]).toContain("'public.get_my_catalog_capabilities()'");
});

test('historical global catalog policies remain unchanged; assignment policies enforce use scope', () => {
    expect(sql).not.toMatch(/(?:DROP|CREATE) POLICY[^\n]*Global (?:activities|categories)/);
    expect(sql).toContain('AND is_assigned = TRUE');
});

test('every public RPC explicitly denies PUBLIC and anon and grants authenticated', () => {
    const signatures = [...sql.matchAll(/^REVOKE EXECUTE ON FUNCTION (public\.[^;]+) FROM PUBLIC, anon;/gm)].map(m => m[1]);
    const functions = [...sql.matchAll(/^CREATE OR REPLACE FUNCTION public\./gm)];
    expect(signatures).toHaveLength(functions.length);
    expect(signatures).toHaveLength(18);
    for (const signature of signatures) {
        expect(sql).toContain(`GRANT EXECUTE ON FUNCTION ${signature} TO authenticated;`);
    }
});

test('rollback captures actual metadata and preserves two-flag history before legacy projection', () => {
    expect(sql.indexOf('CREATE TABLE private.migration_030_backup')).toBeLessThan(sql.indexOf('ALTER TABLE public.eco_org_economic_activities'));
    expect(sql).toContain('pg_get_functiondef(p.oid)');
    expect(sql).toContain('aclexplode');
    expect(down).not.toMatch(/DROP (?:COLUMN|TABLE)/);
    expect(down.indexOf('CREATE TABLE private.migration_030_assignment_state')).toBeLessThan(down.indexOf('UPDATE public.eco_org_economic_activities'));
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('WITH GRANT OPTION');
});
const definition = name => {
    const start = sql.indexOf(`CREATE OR REPLACE FUNCTION ${name}(`);
    expect(start).toBeGreaterThanOrEqual(0);
    return sql.slice(start, sql.indexOf('$$;', start) + 3);
};

test.each(['update_record_classification', 'update_movement_classification',
    'bulk_update_record_classification', 'create_org_activity_iibb_rate'])(
    '%s rejects withdrawn assignments even when activation was preserved', name => {
        const body = definition(`public.${name}`);
        expect(body).toContain('is_assigned = TRUE AND is_active = TRUE');
        expect(body).not.toMatch(/(?:category_id = p_category_id|activity_id = p_activity_id) AND is_active = TRUE/);
    }
);

test('030 backfills assignment through the column default without updating activation', () => {
    expect(sql.match(/ADD COLUMN is_assigned BOOLEAN NOT NULL DEFAULT TRUE/g)).toHaveLength(2);
    const beforeFunctions = sql.split('CREATE OR REPLACE FUNCTION')[0];
    expect(beforeFunctions).not.toMatch(/UPDATE\s+public\./);
    expect(sql).toContain('FROM PUBLIC, anon, authenticated');
});

test('assignment requires SUPERADMIN, capability and authorized destination; activation requires own ADMIN context', () => {
    const assignment = definition('private.catalog_assignment_target');
    expect(assignment).toContain("private.func_role() IS DISTINCT FROM 'SUPERADMIN'");
    expect(assignment).toContain("private.can_platform('CATALOG_ASSIGN_ANY_ORG')");
    expect(assignment).toContain("private.can_platform('ACCESS_ANY_ORG')");
    expect(assignment).toContain("private.can_org(v_org_id, 'ORG_VIEW')");
    const activation = definition('private.catalog_activation_org');
    expect(activation).toContain("private.func_role() IS DISTINCT FROM 'ADMIN'");
    expect(activation).toContain('v_org_id UUID := private.org_id()');
    expect(activation).toContain("private.can_org(v_org_id, 'ORG_VIEW')");
});

test('global maintenance RPCs enforce SUPERADMIN and catalog capability, including import without tenant context', () => {
    const guard = definition('private.require_global_catalog_manager');
    expect(guard).toContain("private.func_role() IS DISTINCT FROM 'SUPERADMIN'");
    expect(guard).toContain("private.can_platform('GLOBAL_CATALOG_MANAGE')");
    for (const name of ['create_global_tax_category', 'update_global_tax_category',
        'create_global_economic_activity', 'update_global_economic_activity', 'upsert_arca_activity_catalog']) {
        expect(definition(`public.${name}`)).toContain('PERFORM private.require_global_catalog_manager();');
    }
    const importer = definition('public.upsert_arca_activity_catalog');
    expect(importer).not.toContain('IF v_org_id IS NULL');
    expect(importer).toContain('RETURNS INTEGER');
});

describe.each([
    ['economic_activity', 'activity', 'eco_org_economic_activities'],
    ['tax_category', 'category', 'eco_org_tax_categories']
])('%s SQL contract', (kind, key, table) => {
    test('new assignment is active; reassignment preserves historical activation', () => {
        const body = definition(`public.assign_${kind}_to_org`);
        expect(body).toContain('private.catalog_assignment_target(p_target_org_id)');
        expect(body).toContain('is_assigned, is_active)');
        expect(body).toContain('TRUE, TRUE)');
        const conflict = body.split('DO UPDATE')[1];
        expect(conflict).toContain('is_assigned = TRUE');
        expect(conflict).not.toMatch(/is_active\s*=/);
    });
    test('unassignment changes assignment only', () => {
        const body = definition(`public.unassign_${kind}_from_org`);
        expect(body).toContain('private.catalog_assignment_target(p_target_org_id)');
        expect(body).toContain('SET is_assigned = FALSE');
        expect(body).not.toMatch(/is_active\s*=/);
    });
    test.each(['activate', 'deactivate'])('%s updates only activation of an assigned row in the server context', action => {
        const body = definition(`public.${action}_${kind}`);
        expect(body).toContain('private.catalog_activation_org()');
        expect(body).not.toContain('p_target_org_id');
        expect(body).toContain(`UPDATE public.${table}`);
        expect(body).toContain(`SET is_active = ${action === 'activate' ? 'TRUE' : 'FALSE'}`);
        expect(body).toContain(`WHERE organization_id = v_org_id AND ${key}_id = p_${key}_id`);
        expect(body).toContain('AND is_assigned = TRUE');
        expect(body).toContain('IF NOT FOUND THEN');
        expect(body).not.toMatch(/SET\s+is_assigned/);
        expect(sql).toContain(`REVOKE EXECUTE ON FUNCTION public.${action}_${kind}(UUID) FROM PUBLIC, anon`);
    });
    test('RLS hides unassigned rows without filtering inactive assignments', () => {
        const start = sql.indexOf(`CREATE POLICY "Org ${key === 'activity' ? 'activities' : 'categories'} viewable by org"`);
        const policy = sql.slice(start, sql.indexOf(';', start));
        expect(policy).toContain('organization_id = private.org_id() AND is_assigned = TRUE');
        expect(policy).not.toContain('is_active');
    });
});
