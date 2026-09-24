import { readFileSync } from 'node:fs';

const read = name => readFileSync(`sql/${name}.sql`, 'utf8');
const owner = read('031_platform_owner_access_any_org');
const accounting = read('032_accounting_catalog_preset');
const core = read('033_catalog_capability_core');

test('owner normalizes NULL scope only after guarded snapshot, preserving strict evaluator', () => {
    expect(owner).toContain("code = 'VEGEN_PLATFORM_ADMIN'");
    expect(owner).toContain('existed_before BOOLEAN NOT NULL');
    expect(owner).toContain('ON CONFLICT DO NOTHING');
    expect(owner).toContain("scope = 'PLATFORM' AND is_active = TRUE");
    expect(owner).toContain("v_template.scope IS NOT NULL AND v_template.scope <> 'PLATFORM'");
    expect(owner).toContain('FROM public.eco_organization_members WHERE role_template_id = v_template.id');
    expect(owner).toContain("c.scope IS DISTINCT FROM 'PLATFORM'");
    expect(owner).toContain('previous_template_scope TEXT');
    expect(owner).toContain('SELECT * INTO STRICT v_template');
    expect(owner).toContain('v_template.is_active IS DISTINCT FROM TRUE');
    expect(owner.indexOf('INSERT INTO private.migration_031_preset_backup')).toBeLessThan(owner.indexOf("SET scope = 'PLATFORM'"));
    expect(owner.indexOf("SET scope = 'PLATFORM'")).toBeLessThan(owner.indexOf('INSERT INTO public.eco_role_template_capabilities'));
    expect(owner).not.toContain('CREATE OR REPLACE FUNCTION private.can_platform');
    const down = read('031_platform_owner_access_any_org_down');
    expect(down).toContain('IF b.previous_template_scope IS NULL THEN');
    expect(down).toContain('SET scope = b.previous_template_scope');
    expect(owner).not.toContain('ACCOUNTING_SUPERADMIN');
    expect(read('031_platform_owner_access_any_org_down')).toContain('b.existed_before = FALSE');
});

test('accounting adds only catalog grants and rollback restores its prior activation', () => {
    expect(accounting).toContain("ARRAY['GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG']");
    expect(accounting).not.toMatch(/ACCESS_ANY_ORG|SUPPORT_IMPERSONATE|SAAS_ANALYTICS_VIEW|GLOBAL_USER_MANAGE/);
    expect(accounting).toContain('ON CONFLICT DO NOTHING');
    const down = read('032_accounting_catalog_preset_down');
    expect(down).toContain('is_active = b.was_active');
    expect(down).toContain('NOT (g.capability_id = ANY(b.existing_grants))');
});

test('independent core uses existing evaluators without new compatibility-role authority', () => {
    expect(core).not.toContain('private.func_role()');
    expect(core).not.toContain("'ADMIN'");
    expect(core).not.toContain("'SUPERADMIN'");
    expect(core).not.toContain('CREATE OR REPLACE FUNCTION private.can_platform');
    expect(core).not.toContain('CREATE OR REPLACE FUNCTION private.can_org(');
    expect(core).toContain("private.can_org(v_org, p_capability)");
    expect(core).toContain('AND is_assigned = TRUE');
});

test('my permissions RPC accepts only an organization, uses caller identity, and has hardened ACL', () => {
    expect(core).toContain('public.get_my_effective_capabilities(p_org_id UUID DEFAULT NULL)');
    expect(core).toContain('private.current_profile_id()');
    expect(core).not.toContain('p_user_id');
    expect(core).toContain('private.can_platform(c.code)');
    expect(core).toContain('private.can_org(p_org_id, c.code)');
    expect(core).toContain('REVOKE EXECUTE ON FUNCTION public.get_my_effective_capabilities(UUID) FROM PUBLIC, anon;');
    expect(core).toContain('GRANT EXECUTE ON FUNCTION public.get_my_effective_capabilities(UUID) TO authenticated;');
});

test('DB test discovers distinct actors by effective capability rather than preset code', () => {
    const db = readFileSync('tests/db/030_assignment_activation.sql', 'utf8');
    expect(db).not.toContain("t.code = 'PLATFORM_SUPERADMIN'");
    expect(db).toContain('ARRAY[v_owner, v_accounting]');
    expect(db).toContain("private.can_platform('ACCESS_ANY_ORG')");
    expect(db).toContain("private.can_org(v_org, 'CATALOG_ACTIVITY_MANAGE')");
    expect(db).toContain('ROLLBACK;');
});

function definition(name) {
    const start = core.indexOf('CREATE OR REPLACE FUNCTION ' + name + '(');
    if (start < 0) throw new Error('Missing function ' + name);
    return core.slice(start, core.indexOf('\n$$;', start) + 4);
}

test('assignment target needs only effective catalog permission and an explicit active target', () => {
    const sql = definition('private.catalog_assignment_target');
    expect(sql).toContain("private.can_platform('CATALOG_ASSIGN_ANY_ORG')");
    expect(sql).toContain('auth.uid() IS NULL');
    expect(sql).toContain('private.current_profile_id() IS NULL');
    expect(sql).toContain('p_target_org_id IS NULL');
    expect(sql).toContain('o.id = p_target_org_id AND o.is_active IS TRUE');
    expect(sql).not.toMatch(/ACCESS_ANY_ORG|ORG_VIEW|func_role|can_org|eco_organization_members/);
});

test('target and status RPCs expose minimal catalog data with matching capability gates', () => {
    for (const name of ['list_catalog_assignment_targets', 'list_catalog_assignment_state']) {
        const sql = definition('public.' + name);
        expect(sql).toContain("private.can_platform('CATALOG_ASSIGN_ANY_ORG')");
        expect(sql).toContain('o.is_active IS TRUE');
        expect(sql).toContain("STABLE SECURITY DEFINER SET search_path = ''");
        expect(sql).not.toMatch(/tax_id|cuit|eco_financial_movements/);
        const args = name.endsWith('targets') ? '' : 'TEXT';
        expect(core).toContain('REVOKE EXECUTE ON FUNCTION public.' + name + '(' + args + ') FROM PUBLIC, anon;');
        expect(core).toContain('GRANT EXECUTE ON FUNCTION public.' + name + '(' + args + ') TO authenticated;');
    }
});

test('assignment policies are tenant-only while global catalog policies remain untouched', () => {
    expect(core.match(/CREATE POLICY/g)).toHaveLength(3); // two definitions plus snapshot reconstruction
    for (const name of ['Org activities viewable by org', 'Org categories viewable by org']) {
        const policy = core.slice(core.indexOf('CREATE POLICY "' + name + '"')) .split(');')[0];
        expect(policy).toContain('organization_id = private.org_id() AND is_assigned IS TRUE');
        expect(policy).toContain("private.can_org(organization_id, 'ORG_VIEW')");
        expect(policy).not.toMatch(/SUPERADMIN|ACCESS_ANY_ORG/);
    }
    expect(core).not.toMatch(/ON public\.eco_(economic_activities|tax_categories|organizations)\s*FOR SELECT/);
});

test('tenant defaults are restricted to active CONSULTANT and TENANT_ADMIN, with reversible added grants', () => {
    expect(core).toContain("t.code IN ('CONSULTANT', 'TENANT_ADMIN') AND t.scope = 'ORGANIZATION' AND t.is_active IS TRUE");
    for (const cap of ['CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE']) expect(core).toContain(cap);
    expect(core).not.toMatch(/CATALOG_(ACTIVITY|CATEGORY)_ACTIVATE/);
    expect(core).not.toContain('eco_member_capability_overrides');
    const activation = definition('private.catalog_activation_org');
    expect(activation).toContain('m.is_active IS TRUE');
    expect(activation).toContain('o.is_active IS TRUE');
    expect(activation).toContain('private.can_org(v_org, p_capability)');
    const down = read('033_catalog_capability_core_down');
    expect(down).toContain('b.existed_before = FALSE');
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('ALTER FUNCTION %s OWNER TO %I');
    expect(core).toContain('RETURNING id, code');
    expect(core).toContain('SELECT id, code FROM inserted');
    expect(down).toContain('DELETE FROM public.eco_capabilities c');
    expect(down).toContain('WHERE c.id = b.capability_id');
    expect(down).toContain("confrelid = 'public.eco_capabilities'::regclass");
    expect(down).toContain('FOR UPDATE OF c');
    expect(down).toContain('IF v_referenced THEN');
    expect(down).not.toContain('DELETE FROM public.eco_membership_capability_overrides');
});


test('033 snapshots every function signature it defines and restores existing or drops new functions', () => {
    const definitions = [...core.matchAll(/CREATE OR REPLACE FUNCTION ([\w.]+)\(([^)]*)\)/g)];
    expect(definitions).toHaveLength(10);
    const signatures = definitions.map(([, name, params]) => name + '(' +
        (params.trim() ? params.split(',').map(p => p.trim().split(/\s+/)[1]).join(', ') : '') + ')');
    const backup = core.slice(0, core.indexOf('$backup$;', core.indexOf('DO $backup$')));
    for (const signature of signatures) expect(backup).toContain("'" + signature + "'");
    const down = read('033_catalog_capability_core_down');
    expect(down).toContain('IF b.definition IS NULL THEN');
    expect(down).toContain("'DROP FUNCTION IF EXISTS ' || b.object_name");
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('ALTER FUNCTION %s OWNER TO %I');
    expect(down).toContain('jsonb_to_recordset');
});

test('six migration files contain no reported concatenations; both policy names match the snapshots', () => {
    for (const name of ['031_platform_owner_access_any_org', '032_accounting_catalog_preset', '033_catalog_capability_core']) {
        for (const suffix of ['', '_down']) expect(read(name + suffix)).not.toMatch(
            /backupFROM|TRUEWHERE|aJOIN|JOINpublic|is_activeIS|ANDprivate|ORGANIZATION.AND|orPLATFORM|non-PLATFORMgrants|Orgactivities/);
    }
    for (const name of ['Org activities viewable by org', 'Org categories viewable by org']) {
        expect(core).toContain("'" + name + "'");
        expect(core).toContain('CREATE POLICY "' + name + '"');
        expect(core).toContain('DROP POLICY IF EXISTS "' + name + '"');
    }
    const down = read('033_catalog_capability_core_down');
    expect(down).toContain("IF b.kind = 'policy' THEN");
    expect(down).toContain("'DROP POLICY IF EXISTS ' || b.object_name");
    expect(down).toContain('IF b.definition IS NOT NULL THEN EXECUTE b.definition; END IF;');
});
