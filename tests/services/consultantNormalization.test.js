import { readFileSync } from 'node:fs';

const up = readFileSync('sql/034_normalize_consultant_scope_and_catalog_grants.sql', 'utf8');
const down = readFileSync('sql/034_normalize_consultant_scope_and_catalog_grants_down.sql', 'utf8');

test('034 validates unique active organization-compatible CONSULTANT and capabilities before snapshot/mutation', () => {
    const backup = up.indexOf('INSERT INTO private.migration_034_consultant_backup');
    for (const guard of [
        'SELECT * INTO STRICT v_template', "WHERE code = 'CONSULTANT' FOR UPDATE",
        'v_template.is_active IS DISTINCT FROM TRUE',
        "v_template.scope IS NOT NULL AND v_template.scope <> 'ORGANIZATION'",
        'FROM public.eco_user_platform_role WHERE role_template_id = v_template.id',
        "c.scope IS DISTINCT FROM 'ORGANIZATION'",
        "code = 'CATALOG_ACTIVITY_MANAGE' AND scope = 'ORGANIZATION' AND is_active IS TRUE",
        "code = 'CATALOG_CATEGORY_MANAGE' AND scope = 'ORGANIZATION' AND is_active IS TRUE"
    ]) {
        expect(up).toContain(guard);
        expect(up.indexOf(guard)).toBeLessThan(backup);
    }
    expect(backup).toBeLessThan(up.indexOf('UPDATE public.eco_role_templates'));
    expect(up).toContain('ON CONFLICT (template_id) DO NOTHING');
    expect(up).toContain('IF v_template.scope IS NULL THEN');
    expect(up).toContain('VALUES (v_template.id, v_activity), (v_template.id, v_category)');
});

test('034 mutations are limited to CONSULTANT scope and the two grants; helpers and other authorization data unchanged', () => {
    expect(up.match(/UPDATE public\.eco_role_templates[^;]+;/g)).toEqual([
        "UPDATE public.eco_role_templates SET scope = 'ORGANIZATION' WHERE id = v_template.id;"
    ]);
    for (const sql of [up, down]) {
        expect(sql).not.toMatch(/CREATE OR REPLACE FUNCTION|CREATE POLICY|ALTER POLICY/);
        expect(sql).not.toMatch(/(?:INSERT INTO|UPDATE|DELETE FROM) public\.eco_(?:organization_members|user_platform_role|membership_capability_overrides|capabilities)\b/);
        expect(sql.trimEnd().endsWith('COMMIT;')).toBe(true);
        expect(sql).toMatch(/^BEGIN;/m);
        expect(sql).not.toMatch(/backupFROM|TRUEWHERE|aJOIN|JOINpublic|is_activeIS|ANDprivate|ORGANIZATION.AND/);
    }
    expect(up).toContain('tenant_admin_state JSONB NOT NULL');
    expect(up).not.toContain('SET is_active');
});

test('034 down removes only introduced grants and restores scope only when up changed it', () => {
    expect(down).toContain("c.code = 'CATALOG_ACTIVITY_MANAGE' AND b.existed_activity_grant = FALSE");
    expect(down).toContain("c.code = 'CATALOG_CATEGORY_MANAGE' AND b.existed_category_grant = FALSE");
    expect(down).toContain('g.role_template_id = b.template_id');
    expect(down).toContain('IF b.previous_scope IS NULL THEN');
    expect(down).toContain('SET scope = b.previous_scope WHERE id = b.template_id');
    expect(down).toContain('DELETE FROM private.migration_034_consultant_backup');
    expect(down).not.toContain('SET is_active');
});

test('manual DB acceptance covers all three real callers, effective permissions, actual RPC denial and rollback', () => {
    const db = readFileSync('tests/db/034_consultant_activation.sql', 'utf8');
    for (const id of ['f290b025-86a6-4809-8aee-ed184e1b204d', '0182c4e0-7983-474b-acb7-c8b04f1ac7b3', '986a7906-213e-4f35-b7b9-f67da128f4a1']) expect(db).toContain(id);
    expect(db).toContain("ARRAY['ORG_VIEW', 'CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE']");
    expect(db).toContain("ARRAY['DENY', 'ABSENT']");
    expect(db).toContain('WHEN insufficient_privilege');
    expect(db).toContain('public.get_my_effective_capabilities(v_org)');
    expect(db).toContain('b.tenant_admin_state');
    for (const rpc of ['activate_economic_activity', 'deactivate_economic_activity', 'activate_tax_category', 'deactivate_tax_category']) expect(db).toContain('PERFORM public.' + rpc);
    expect(db.trimEnd().endsWith('ROLLBACK;')).toBe(true);
});


test.each(['030_assignment_activation', '034_consultant_activation'])('%s harness does not directly access private under a restricted SQL role', name => {
    const db = readFileSync('tests/db/' + name + '.sql', 'utf8');
    const blocks = [...db.matchAll(/EXECUTE 'SET LOCAL ROLE (?:authenticated|anon)';([\s\S]*?)EXECUTE 'RESET ROLE';/g)];
    expect(blocks.length).toBeGreaterThan(0);
    for (const [, block] of blocks) expect(block.replace(/--[^\n]*/g, '')).not.toMatch(/\bprivate\s*\./i);
    expect(db).toContain("set_config('request.jwt.claim.sub'");
    expect(db).toContain("set_config('request.jwt.claims'");
    expect(db.trimEnd().endsWith('ROLLBACK;')).toBe(true);
    expect(db).not.toMatch(/GRANT\s+(?:USAGE|EXECUTE)/i);
});
