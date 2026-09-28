// Static SQL contracts, not PostgreSQL execution evidence.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { MICA_PLATFORM_CAPABILITIES, MICA_ORGANIZATION_CAPABILITIES, isMicaCapability } from '../../src/js/core/micaCapabilities.js';
const read = p => readFileSync(p, 'utf8');
const up = read('sql/037_platform_tenant_operation.sql');
const down = read('sql/037_platform_tenant_operation_down.sql');
const body = name => up.split(`FUNCTION ${name}(`)[1].split('$$;')[0];
const baseline = JSON.parse(read('tests/fixtures/037_preexisting_migrations.sha256.json'));

test.each(Object.entries(baseline))('037 preserves historical SQL %s', (file, hash) => {
    expect(createHash('sha256').update(readFileSync(file)).digest('hex')).toBe(hash);
});

test('scope and tenant action have separate authority; context is authoritative, DENY precedes all ALLOW paths', () => {
    const scope = body('private.platform_org_in_scope');
    expect(scope).toContain("private.can_platform('ACCESS_ANY_ORG')");
    expect(scope).toContain('private.eco_platform_org_scopes');
    const action = body('private.can_operate_mica_org');
    expect(action).not.toContain("can_platform('ACCESS_ANY_ORG')");
    expect(action).toContain('public.eco_user_active_context');
    expect(action).toContain('organization_id=p_org_id');
    expect(action).toContain("scope='ORGANIZATION' AND is_active");
    expect(action.indexOf("effect='DENY'")).toBeLessThan(action.indexOf('private.can_org('));
    expect(action.indexOf("v_override='DENY'")).toBeLessThan(action.indexOf('private.can_org('));
    expect(action.indexOf('IF NOT v_platform_scope THEN RETURN FALSE')).toBeLessThan(action.indexOf("v_override='ALLOW'"));
    expect(action).toContain('public.eco_platform_role_org_capabilities');
    expect(up).not.toMatch(/CREATE OR REPLACE FUNCTION private\.(?:can_org|can_platform)\(/);
    expect(up).not.toMatch(/INSERT INTO public\.eco_organization_members|INSERT INTO public\.eco_platform_role_org_capabilities/);
});

test('server and client share a closed product contract, including OCR but excluding REVIEW and foreign codes', () => {
    const allowed = body('private.mica_capability_allowed');
    const pairs = [...allowed.matchAll(/\('([A-Z_]+)','(PLATFORM|ORGANIZATION)'\)/g)].map(m => [m[1], m[2]]);
    expect(pairs).toEqual([
        ...MICA_PLATFORM_CAPABILITIES.map(c => [c, 'PLATFORM']),
        ...MICA_ORGANIZATION_CAPABILITIES.map(c => [c, 'ORGANIZATION'])
    ]);
    for (const code of ['DOCUMENTS_UPLOAD', 'DOCUMENTS_OCR_PROCESS', 'DOCUMENTS_OCR_VERIFY']) expect(isMicaCapability(code, 'ORGANIZATION')).toBe(true);
    for (const code of ['RECIPES_VIEW', 'SUPPLIERS_MANAGE', 'SALES_VIEW', 'UNKNOWN_CAPABILITY']) expect(isMicaCapability(code, 'ORGANIZATION')).toBe(false);
    expect(isMicaCapability('ACCESS_ANY_ORG', 'ORGANIZATION')).toBe(false);
    expect(body('public.get_my_effective_capabilities')).toContain('private.can_operate_mica_org');
    expect(body('public.get_capability_delegation_contract')).toContain('private.mica_capability_allowed');
});

test('existing readers and catalog writes use action permission without scope-only bypass', () => {
    for (const name of ['get_operational_snapshot', 'get_operational_records_page', 'get_operational_financials_page']) {
        expect(body('public.' + name)).toContain('private.can_operate_mica_org');
        expect(body('public.' + name)).not.toContain('ACCESS_ANY_ORG');
    }
    expect(body('private.catalog_activation_org')).toContain('private.can_operate_mica_org');
    expect(body('public.switch_superadmin_org_context')).toContain('private.platform_org_in_scope(p_org_id)');
    expect(body('public.switch_superadmin_org_context')).toContain('FOR UPDATE');
    expect(body('public.switch_superadmin_org_context')).toContain('SUPERADMIN_ORG_CONTEXT_SWITCHED');
});

test('migration captures live definitions/ACL; down refuses drift and preserves post-install data', () => {
    expect(up).toContain('pg_get_functiondef(oid)');
    expect(up).toContain('reviewed function contract differs');
    expect(up).toContain('public RPC ACL differs');
    expect(up).toContain('private helper ACL differs');
    expect(up).toContain("has_function_privilege('anon',v.signature,'EXECUTE')");
    expect(up).toContain('ENABLE ROW LEVEL SECURITY');
    expect(up).toContain('aclexplode');
    expect(up).not.toMatch(/GRANT (?:EXECUTE|USAGE|SELECT).*private\./);
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('proacl IS NOT DISTINCT FROM b.acl');
    expect(down).toContain('provisioned scope/override data exists');
    expect(down).not.toMatch(/\bCASCADE\b/);
    expect(down.indexOf('DROP TRIGGER guard_037_platform_override')).toBeLessThan(down.indexOf('DROP FUNCTION private.guard_037_platform_override'));
});

test('DB harness remains SQL Editor compatible and private checks stay outside restricted role', () => {
    const harness = read('tests/db/037_platform_tenant_operation.sql');
    expect(harness.trim()).toMatch(/ROLLBACK;$/);
    expect(harness).toContain('Conventional tenant behavior differs from can_org');
    expect(harness).toContain('Conventional tenant positive case not exercised');
    expect(harness).toContain("NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role r WHERE r.user_profile_id=p.id AND r.is_active)");
    expect(harness).toContain('037 public RPC ACL mismatch');
    expect(harness).not.toMatch(/(?<!:):(?:'[A-Za-z_]\w*'|[A-Za-z_]\w*)|^\s*\\/m);
    for (const match of harness.matchAll(/EXECUTE 'SET LOCAL ROLE authenticated';([\s\S]*?)EXECUTE 'RESET ROLE';/g)) {
        expect(match[1]).not.toMatch(/private\./);
    }
});
