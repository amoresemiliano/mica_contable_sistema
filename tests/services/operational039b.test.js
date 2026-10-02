import { MICA_PERMISSION_CATALOG_039B as historical } from '../../src/js/core/micaPermissionContract.js';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { MICA_TENANT_PRESETS, MICA_ACCOUNTING_PLATFORM } from '../../src/js/core/micaPresets.js';
import { isMicaCapability, MICA_ORGANIZATION_CAPABILITIES, MICA_PLATFORM_CAPABILITIES } from '../../src/js/core/micaCapabilities.js';
const read = path => readFileSync(path,'utf8');
const up=read('sql/039b_operational_access_and_ux.sql'), down=read('sql/039b_operational_access_and_ux_down.sql');
const body = name => up.split('CREATE OR REPLACE FUNCTION '+name+'(')[1].split('$$;')[0];

test('039b changes none of the previous migrations', () => {
    for (const [path, hash] of Object.entries(JSON.parse(read('tests/fixtures/039b_preexisting_migrations.sha256.json'))))
        expect(createHash('sha256').update(readFileSync(path)).digest('hex')).toBe(hash);
});
test('SQL seed and JS proposal contain identical exact MICA capability lists', () => {
    for (const [code, caps] of Object.entries(MICA_TENANT_PRESETS)) {
        const historicalCaps=historical.filter(c=>c.scope==='ORGANIZATION'&&c.defaultPresets.includes(code)).map(c=>c.code);
        expect(up).toContain(`('${code}',ARRAY[${historicalCaps.map(c=>`'${c}'`).join(',')}]::TEXT[],`);
        expect(new Set(caps).size).toBe(caps.length);
        for (const c of caps) expect(isMicaCapability(c,'ORGANIZATION')).toBe(true);
    }
    expect(MICA_TENANT_PRESETS.MICA_ORG_ADMIN).not.toContain('RECORD_RESTORE');
    const historicalAccounting = historical.filter(c=>c.scope==='PLATFORM' && c.defaultPresets.includes('ACCOUNTING_SUPERADMIN')).map(c=>c.code);
    expect(up).toContain(`ARRAY[${historicalAccounting.map(c=>`'${c}'`).join(',')}]::TEXT[]`);
    expect(MICA_ACCOUNTING_PLATFORM).not.toEqual(expect.arrayContaining(['ACCESS_ANY_ORG']));
    expect(MICA_ACCOUNTING_PLATFORM).not.toContain('PLATFORM_MANAGE');
    expect(up).toContain('unnest(ARRAY[root_template,accounting])');
    expect(up).toContain('Accounting bridge has non-MICA grants; do not reuse');
});
test('read and writes both recognize delegable administration without rewriting the permission evaluator', () => {
    const pairs=[...body('private.mica_capability_allowed').matchAll(/\('([A-Z_]+)','(PLATFORM|ORGANIZATION)'\)/g)].map(m=>[m[1],m[2]]);
    expect(pairs).toEqual([...historical.filter(c=>c.scope==='PLATFORM'&&c.status!=='PROPOSED').map(c=>[c.code,c.scope]),...historical.filter(c=>c.scope==='ORGANIZATION'&&c.status!=='PROPOSED').map(c=>[c.code,c.scope])]);
    expect(body('public.mica_admin_read')).toContain('global_users BOOLEAN:=COALESCE(private.admin_039b_users(),FALSE)');
    expect(body('public.mica_admin_read')).toContain('private.admin_039b_presets()');
    expect(body('public.mica_admin_read')).toContain("'contexts',COALESCE");
    expect(body('public.mica_admin_apply')).toContain('Cannot assign all-organization preset beyond own scope');
    expect(body('private.admin_038_cap')).toContain('Cannot delegate beyond own effective authority');
    expect(up).not.toMatch(/CREATE (?:OR REPLACE )?FUNCTION (?:private|public)\.(?:can_org|can_platform|can_operate_mica_org)\(/);
    expect(up).not.toMatch(/private\.func_role\(|role\s*=\s*'(ADMIN|SUPERADMIN|CONSULTANT)'/);
    expect(up).not.toMatch(/UPDATE public\.eco_user_profiles SET role/);
});
test('preflight fingerprints match repository source bodies and replaced functions remain SECURITY DEFINER with empty path', () => {
    const originals=[['037_platform_tenant_operation','private.mica_capability_allowed'],
        ...['admin_038_authorize','admin_038_target','admin_038_cap'].map(n=>['038_mica_administration','private.'+n]),
        ['038_mica_administration','public.mica_admin_apply'],['038_mica_administration','public.mica_admin_read'],
        ['039_module_and_import_capabilities','private.require_039_import'],
        ...['restore_normalized_record','restore_financial_movement'].map(n=>['039_module_and_import_capabilities','public.'+n])];
    for (const [file,name] of originals) {
        const source=read('sql/'+file+'.sql').match(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\([\\s\\S]*?\\$\\$;'))[0];
        const hash=createHash('md5').update(source.split('$$')[1].replace(/\r/g,'').trim()).digest('hex');
        expect(up.split('$preflight$;')[0]).toContain(hash);
        expect(body(name)).toMatch(/SECURITY DEFINER SET search_path\s*=\s*''/);
    }
});
test('scope provisioning is explicit, preserves revocations and covers future organizations/role assignments', () => {
    expect(up).toContain('ON CONFLICT(user_profile_id,organization_id) DO NOTHING');
    expect(up).toContain('AFTER INSERT OR UPDATE OF is_active ON public.eco_organizations');
    expect(up).toContain('AFTER INSERT OR UPDATE OF role_template_id,is_active ON public.eco_user_platform_role');
    expect(up).toContain('Existing inactive scopes stay revoked');
    expect(body('private.require_039_import')).toContain("require_039_action('IMPORT_VIEW')");
    expect(up).toContain('REVOKE ALL ON FUNCTION');
    expect(up).toContain('REVOKE ALL ON TABLE');
    expect(down).toContain('Seeded row changed; preserve administrative decision');
    expect(down).toContain('Later function drift');
    expect(down).not.toContain('CASCADE');
});

test('both restore endpoints require platform authority, scope and effective contextual grants before any update', () => {
    for(const name of ['restore_normalized_record','restore_financial_movement']) {
        const source=body('public.'+name), update=source.indexOf('UPDATE public.');
        expect(source).toContain('AS $$');
        expect(source).not.toContain('CREATE FUNCTION');
        expect(source).not.toContain('CREATE OR REPLACE FUNCTION');
        for(const required of ["private.can_platform('DATA_RESTORE_ANY_ORG')",'private.platform_org_in_scope(private.active_org_id())',
            "private.require_039_action('RECORD_VIEW')","private.require_039_action('RECORD_RESTORE')"])
            expect(source.indexOf(required)).toBeGreaterThanOrEqual(0);
        expect(source.indexOf("private.require_039_action('RECORD_RESTORE')")).toBeLessThan(update);
        expect(source).toContain('organization_id = v_org_id AND deleted_at IS NOT NULL');
        expect(source).not.toContain('ACCESS_ANY_ORG');
        expect(source).not.toContain('private.org_id()');
        expect(source).toContain("USING ERRCODE='42501'");
    }
    const evaluator=read('sql/037_platform_tenant_operation.sql').split('CREATE FUNCTION private.can_operate_mica_org')[1].split('$$;')[0];
    for(const required of ['eco_user_active_context','eco_organizations',"effect='DENY'"])
        expect(evaluator).toContain(required);
    expect(body('public.mica_admin_apply')).toContain("private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;");
    expect(body('public.mica_admin_apply')).toContain('Restore platform delegation requires a MICA platform recipient, never a tenant');
});

test('adoption is exact, defaults to expecting absence and never copies historical product grants', () => {
    const manifest=JSON.parse(read('sql/039b_live_adoption_manifest.json'));
    expect(Object.keys(manifest)).toHaveLength(13);
    const preflight=up.split('$preflight$;')[0];
    for(const code of Object.keys(manifest)) expect(preflight).toContain("'"+code+"'");
    expect(preflight).toContain('to_jsonb(c)=r.expected');
    expect(preflight).toContain('c.delegation_class=r.delegation_class AND c.is_active');
    expect(preflight).toContain('039b collision: review LIVE and fill adoption manifest');
    const seed=up.split('-- BEGIN GENERATED CAPABILITY SEED')[1].split('-- END GENERATED CAPABILITY SEED')[0];
    expect(seed).toContain('WHERE NOT EXISTS(SELECT 1 FROM public.eco_capabilities c WHERE c.code=x.code) RETURNING *');
    expect(seed).not.toMatch(/\b(?:UPDATE|DELETE|ON CONFLICT)\b/);
    const queries=read('sql/039b_preflight_live_readonly.sql').replace(/--[^\n]*/g,'');
    expect(queries).not.toMatch(/\b(INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|DO|CALL)\b/i);
    for(const value of ['RECORD_RESTORE','DATA_RESTORE_ANY_ORG','restore_normalized_record','restore_financial_movement',
        'ACCOUNTING_SUPERADMIN','eco_platform_owner','eco_membership_capability_overrides']) expect(queries).toContain(value);
    expect(down).toContain('ORDER BY seq DESC');
});
