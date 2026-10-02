// Static contracts only. No SQL execution or simulated proof of PostgreSQL trigger behavior.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read = path => readFileSync(path, 'utf8');
const up = read('sql/036_owner_core_and_delegation_guard.sql');
const down = read('sql/036_owner_core_and_delegation_guard_down.sql');
const harness = read('tests/db/036_owner_core.sql');
const original = read('sql/019_capability_foundation.sql').match(/CREATE OR REPLACE FUNCTION private\.can_platform\([\s\S]*?\$\$;/)[0];
const modified = up.match(/CREATE OR REPLACE FUNCTION private\.can_platform\([\s\S]*?\$\$;/)[0];
const protectedHashes = JSON.parse(read('tests/fixtures/036_preexisting_migrations.sha256.json'));
const reserved = ['PLATFORM_MANAGE','GLOBAL_USER_MANAGE','PLAN_MANAGE','ACCESS_ANY_ORG','SUPPORT_IMPERSONATE',
    'HARD_DELETE_EXCEPTIONAL','ORGANIZATION_CREATE','ORGANIZATION_ARCHIVE','PLATFORM_MIGRATIONS_APPLY',
    'PLATFORM_TENANTS_PROVISION','PLATFORM_SYSTEM_MONITOR'];

test.each(Object.entries(protectedHashes))('036 leaves existing migration %s byte-identical', (path, hash) => {
    expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(hash);
});

test('preflight fails before mutation for identity, helper, schema and unsafe grant drift', () => {
    const preflight = up.split('$preflight$;')[0];
    for (const check of ['structural owner identity mismatch', 'owner role assignment differs',
        'reserved grant/override outside reviewed owner baseline', 'unexpected effective reserved authority',
        'unreviewed capability reference/grant path', 'can_platform differs', 'missing unique constraint']) {
        expect(preflight).toContain(check);
    }
    const body = original.split('AS $$')[1].split('$$;')[0].replace(/\r/g, '').trim();
    expect(preflight).toContain(createHash('md5').update(body).digest('hex'));
    expect(preflight).toContain('IN SHARE ROW EXCLUSIVE MODE');
    expect(preflight).not.toMatch(/\b(?:INSERT INTO|DELETE FROM|ALTER TABLE|CREATE TABLE)\b/);
});

test('structural owner requires both UUIDs, active coherent identity and no legacy role authority', () => {
    const helper = up.split('CREATE FUNCTION private.is_platform_owner()')[1].split('$$;')[0];
    expect(helper).toContain("SECURITY DEFINER SET search_path = ''");
    expect(helper).toContain('auth.uid() IS NOT NULL');
    expect(helper).toContain('p.auth_user_id=o.auth_user_id');
    expect(helper).toContain('p.is_active IS TRUE');
    expect(helper).toContain('private.current_profile_id()');
    expect(helper).not.toMatch(/\brole\b|email|role_template/i);
    expect(up).not.toMatch(/(?:profile|p|caller)\.role\s*=|func_role\(/i);
    expect(up).toContain('CHECK(singleton)');
    expect(up).toContain('9563f41e-cd57-42d9-8626-9b04bd6e5863');
    expect(up).toContain('c1e16acf-a45c-4e51-a3e5-c95208adc3c6');
});

test('can_platform delegable path is unchanged; reserved branch precedes template/override resolution', () => {
    const restored = modified.replace('    v_delegation_class TEXT;\n', '')
        .replace('SELECT id, delegation_class INTO v_cap_id, v_delegation_class', 'SELECT id INTO v_cap_id')
        .replace(/    -- Reserved eligibility[\s\S]*?    -- 3\./, '    -- 3.');
    expect(restored.replace(/\r/g, '')).toBe(original.replace(/\r/g, ''));
    expect(modified.indexOf("v_delegation_class = 'OWNER_RESERVED'")).toBeLessThan(modified.indexOf('FROM public.eco_user_platform_capability_overrides'));
    expect(modified).toContain('private.is_platform_owner() AND EXISTS');
    expect(modified).toContain('private.eco_owner_reserved_capabilities');
});

test('eleven reserved capabilities leave reusable presets; metadata never calls them delegable', () => {
    for (const code of reserved) expect(up).toContain(`'${code}'`);
    expect(up).toContain('ORGANIZATION_UPDATE must remain active PLATFORM_DELEGABLE');
    expect(reserved).not.toContain('ORGANIZATION_UPDATE');
    expect(up).toContain("c.delegation_class='OWNER_RESERVED'");
    expect(up).toContain('DELETE FROM public.eco_role_template_capabilities');
    expect(up).toContain("c.delegation_class<>'OWNER_RESERVED'");
    expect(up).toContain("OR private.is_platform_owner())");
    expect(up).toContain('eco_capabilities_036_delegation_check');
});

test('guards cover updates, every grant FK, classification, owner identity and truncate', () => {
    for (const table of ['eco_role_template_capabilities','eco_user_platform_capability_overrides',
        'eco_platform_role_org_capabilities','eco_membership_capability_overrides','eco_member_capability_overrides']) {
        expect(up).toContain(`'public.${table}'::regclass`);
        expect(down).toContain(`DROP TRIGGER guard_036_grant ON public.${table}`);
    }
    expect(up).toContain('BEFORE INSERT OR UPDATE ON %s');
    expect(up).toContain('NEW.scope IS DISTINCT FROM OLD.scope');
    expect(up).toContain('NEW.delegation_class IS DISTINCT FROM OLD.delegation_class');
    expect(up).toContain('NEW.auth_user_id IS DISTINCT FROM v_auth');
    expect(up).toContain('BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.eco_platform_owner');
    expect(up).not.toMatch(/(?:UPDATE|DELETE FROM|INSERT INTO) public\.eco_member_capability_overrides/);
    expect(up).not.toMatch(/CREATE OR REPLACE FUNCTION private\.can_org|handle_new_user/);
});

test('private ACLs are stripped without granting private access; rollback restores exact captured helper/grants', () => {
    expect(up).toContain('aclexplode');
    expect(up).not.toMatch(/GRANT (?:USAGE|EXECUTE|SELECT).*private\./);
    expect(up).toContain('pg_get_functiondef(p.oid)');
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('proacl IS NOT DISTINCT FROM b.acl');
    expect(down).toContain('jsonb_populate_recordset');
    expect(down).toContain('restoring grants would delegate the core');
    expect(down).not.toMatch(/DROP (?:FUNCTION|TABLE).*CASCADE/);
    expect(down).not.toMatch(/(?:UPDATE|DELETE FROM|INSERT INTO) public\.(?:eco_user_profiles|eco_organization_members|eco_organizations)\b/);
});

test('DB harness is SQL Editor compatible and restricted-role checks use only public RPCs', () => {
    expect(harness).not.toMatch(/(?<!:):(?:'[A-Za-z_]\w*'|[A-Za-z_]\w*)|^\s*\\/m);
    expect(harness.trim()).toMatch(/ROLLBACK;$/);
    for (const block of harness.matchAll(/EXECUTE 'SET LOCAL ROLE authenticated';([\s\S]*?)EXECUTE 'RESET ROLE';/g)) {
        expect(block[1]).not.toMatch(/private\./);
    }
    for (const marker of ['Cloned template escalated','ALLOW regression','DENY regression',
        'Owner protection bypass','Private helper exposed','Owner public capabilities incomplete']) expect(harness).toContain(marker);
});

test('036 down explicitly removes every static trigger before its function and table', () => {
    const staticTriggers = [...up.matchAll(/^CREATE TRIGGER (\w+)[^;]*? ON ([\w.]+)\s+FOR EACH (?:ROW|STATEMENT) EXECUTE FUNCTION ([\w.]+)\(\);/gm)];
    expect(staticTriggers).toHaveLength(10);
    for (const [, trigger, table, fn] of staticTriggers) {
        const drop = `DROP TRIGGER ${trigger} ON ${table};`;
        expect(down).toContain(drop);
        expect(down.indexOf(drop)).toBeLessThan(down.indexOf(`DROP FUNCTION ${fn}();`));
        if (table.startsWith('private.')) {
            expect(down.indexOf(drop)).toBeLessThan(down.indexOf(`DROP TABLE ${table};`));
        }
    }
    expect(down.indexOf('EXECUTE b.definition')).toBeLessThan(down.indexOf('DROP FUNCTION private.is_platform_owner();'));
    expect(down.indexOf('DROP FUNCTION public.get_capability_delegation_contract();')).toBeLessThan(down.indexOf('DROP FUNCTION private.is_platform_owner();'));
    expect(down.replace(/--[^\n]*/g, '')).not.toMatch(/\bCASCADE\b/i);
});

test('036 up remains byte-identical during pre-application closure', () => {
    expect(createHash('sha256').update(readFileSync('sql/036_owner_core_and_delegation_guard.sql')).digest('hex'))
        .toBe('6fba0e969a90152dc5511670f82c63c34a8ff195626f0a244437e6513faf8d3f');
});

test.each(['', '_down'])('035a historical script %s changes only four localization fields', suffix => {
    const sql = read(`sql/035a_normalize_argentina_organization_defaults${suffix}.sql`);
    const forward = suffix === '';
    const before = forward ? ['CIF','ES','EUR','Europe/Madrid'] : ['CUIT','AR','ARS','America/Argentina/Buenos_Aires'];
    const after = forward ? ['CUIT','AR','ARS','America/Argentina/Buenos_Aires'] : ['CIF','ES','EUR','Europe/Madrid'];
    const columns = ['tax_id_type','country_code','currency','timezone'];
    const [, set, where] = sql.match(/UPDATE public\.eco_organizations\s+SET ([\s\S]*?)\s+WHERE ([\s\S]*?);/);
    expect([...set.matchAll(/(\w+)\s*=/g)].map(match => match[1])).toEqual(columns);
    columns.forEach((column, i) => {
        expect(sql).toContain(`ALTER COLUMN ${column} SET DEFAULT '${after[i]}'`);
        expect(set).toContain(`${column}='${after[i]}'`);
        expect(where).toContain(`${column}='${before[i]}'`);
    });
    if (forward) {
        expect(where.match(/\bAND\b/g)).toHaveLength(3);
        expect(sql).toContain('count(*) FROM public.eco_organizations) <> 4');
    } else {
        const historicalIds = [
            '38419581-8163-482c-9813-616fa6214d71',
            '1f5d071f-a09e-4825-9f12-88533383599e',
            'c7af5a5c-1aac-4add-9873-8073044bf979',
            '59436df3-9f15-4f5e-b17e-37c55482521c'
        ];
        const executable = sql.replace(/--[^\n]*/g, '');
        const preflight = executable.match(/IF\s*\(SELECT count\(\*\) FROM public\.eco_organizations\s+WHERE ([\s\S]*?)\)\s*<>\s*4\s+THEN/);
        expect(preflight).not.toBeNull();
        // Both the preflight and UPDATE require exactly these IDs AND all four guards.
        // Compare complete predicates so an OR, extra ID or missing guard cannot pass.
        for (const predicate of [preflight[1], where.replace(/--[^\n]*/g, '')]) {
            const ids = predicate.match(/\bid\s+IN\s*\(([^)]*)\)/);
            expect(ids).not.toBeNull();
            expect(ids[1].split(',').map(value => value.trim()).sort())
                .toEqual(historicalIds.map(id => `'${id}'::UUID`).sort());
            const guards = predicate.replace(ids[0], 'HISTORICAL_IDS_ONLY')
                .split(/\bAND\b/).map(value => value.replace(/\s+/g, '')).sort();
            expect(guards).toEqual([
                'HISTORICAL_IDS_ONLY',
                ...columns.map((column, i) => `${column}='${before[i]}'`)
            ].sort());
        }
        expect(executable).not.toMatch(/count\(\*\)\s+FROM public\.eco_organizations\s*\)/);
        expect(executable).not.toMatch(/\bCASCADE\b/i);
        expect(executable.match(/\bUPDATE public\.eco_organizations\b/g)).toHaveLength(1);
    }
    expect(sql).toContain('DO NOT EXECUTE');
    expect(sql).toContain('IN ACCESS EXCLUSIVE MODE');
    expect(sql).not.toMatch(/\b(?:DELETE FROM|INSERT INTO)\b/);
});
