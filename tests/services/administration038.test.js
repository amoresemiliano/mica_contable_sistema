import { jest } from '@jest/globals';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createAdministrationService, editableCapabilities, permissionPreview } from '../../src/js/core/services/administrationService.js';
import { createAdministrationView } from '../../src/js/components/administration.js';
const read = f => readFileSync(f, 'utf8');
const up = read('sql/038_mica_administration.sql');
const down = read('sql/038_mica_administration_down.sql');
const db = read('tests/db/038_mica_administration.sql');

test('all preexisting SQL migrations retain their SHA-256', () => {
    const baseline = JSON.parse(read('tests/fixtures/038_preexisting_migrations.sha256.json'));
    for (const [file, hash] of Object.entries(baseline))
        expect(createHash('sha256').update(readFileSync(file)).digest('hex')).toBe(hash);
});
test('only legacy registration is replaced; authority helpers and triggers are not rewritten', () => {
    expect(up.match(/CREATE OR REPLACE FUNCTION [^(]+/g)).toEqual(['CREATE OR REPLACE FUNCTION public.handle_new_user']);
    expect(up).not.toMatch(/(?:CREATE|DROP|ALTER) TRIGGER/);
    for (const fn of up.split('CREATE FUNCTION ').slice(1)) expect(fn.split('AS $$')[0]).toContain("SECURITY DEFINER SET search_path=''");
    expect(up).toContain('REVOKE ALL ON FUNCTION');
    expect(up).toContain('GRANT EXECUTE ON FUNCTION public.mica_admin_read(UUID,TEXT),public.mica_admin_apply(TEXT,JSONB) TO authenticated');
});
test('registration creates only an inactive pending profile, no hardcoded organization or grants', () => {
    const body = up.split('CREATE OR REPLACE FUNCTION public.handle_new_user()')[1].split('$$;')[0];
    expect(body).toContain("VALUES(NEW.id,NULL,'USER',FALSE)");
    expect(body).toContain('private.eco_mica_pending_profiles');
    expect(body).not.toMatch(/INSERT INTO (?:public\.eco_organization_members|public\.eco_user_platform_role)/);
    expect(body).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-/);
    expect(body).not.toMatch(/eco_auth_bootstrap_allowlist|raw_user_meta_data|NEW\.email|consumed_at/);
    expect(up).toContain('unexpected auth INSERT trigger');
    expect(up).toContain('unsupported required columns');
});

test('038 preflight matches confirmed legacy attributes and clears every non-owner trigger grant', () => {
    const preflight = up.split('$preflight$;')[0];
    expect(preflight).toContain("pg_get_userbyid(proowner)='postgres' AND prosecdef AND provolatile='v' AND proconfig IS NULL");
    expect(preflight).toContain("tgname='on_auth_user_created'");
    expect(preflight).toContain("tgtype=5 AND tgenabled='O'");
    const acl = up.split('FOR r IN SELECT oid,proowner,proacl FROM pg_proc WHERE oid IN')[1].split('$acl$;')[0];
    expect(acl).toContain("'public.handle_new_user()'::regprocedure");
    expect(acl).toContain('WHERE grantee<>r.proowner');
    expect(acl).toContain('REVOKE ALL ON FUNCTION %s FROM %s');
    expect(up).not.toMatch(/(?:UPDATE|DELETE FROM|INSERT INTO) public\.eco_auth_bootstrap_allowlist/);
});
test('tenant administration checks context and concrete action; target and preset root protection are structural', () => {
    expect(up).toContain('organization_id=p_org');
    expect(up).toContain('private.can_operate_mica_org(p_org,p_tenant)');
    expect(up).not.toContain("can_platform('ACCESS_ANY_ORG')");
    expect(up).not.toMatch(/SUPERADMIN|role\s*=\s*'ADMIN'|@gmail/);
    expect(up).toContain('user_profile_id=p_profile');
    expect(up).toContain('Root preset protected');
    expect(up).toContain('Cannot delegate an action you do not possess');
    expect(up).toContain('Self administration is not allowed');
});
test('presets are registered MICA-only, immutable scope and explicit recipient confirmation', () => {
    expect(up).toContain("delegation_class<>'OWNER_RESERVED'");
    expect(up).toContain('private.mica_capability_allowed(code,scope)');
    expect(up).toContain('Preset scope is immutable');
    expect(up).toContain('expected_recipients');
    expect(up).toContain('Preset has recipients outside organization');
    expect(up).toContain('Platform user requires explicit scopes, not artificial membership');
});
test('down checks drift, restores auth definition and ACL then removes only 038 objects', () => {
    expect(down).toContain('pg_get_functiondef(to_regprocedure(b.signature))<>b.installed_definition');
    expect(down).toContain('EXECUTE b.definition');
    expect(down).toContain('WITH GRANT OPTION');
    expect(down).not.toMatch(/CASCADE|DELETE FROM|DROP TRIGGER/);
    expect(down.indexOf('EXECUTE b.definition')).toBeLessThan(down.indexOf('DROP TABLE private.eco_mica_pending_profiles'));
    expect(down.indexOf('DROP FUNCTION public.mica_admin_apply')).toBeLessThan(down.indexOf('DROP FUNCTION private.admin_038_actor'));
});
test('DB harness covers actual registration, deny/allow, delegated staff, tenant isolation and root protection', () => {
    for (const text of ['INSERT INTO auth.users', 'Pending user obtained administration', 'Reserved delegation accepted',
        'Wrong scope accepted', 'Root disabled', 'Root role changed indirectly', 'DENY ignored', 'ALLOW failed',
        'Staff escaped explicit scope', 'Tenant manager escaped organization', 'Artificial membership']) expect(db).toContain(text);
    expect(db.trim()).toMatch(/^--[\s\S]*BEGIN;[\s\S]*ROLLBACK;$/);
    expect(db).not.toMatch(/(?<!:):(?:'[A-Za-z_]\w*'|[A-Za-z_]\w*)|^\s*\\/m);
});
test('editor rejects reserved and foreign capabilities while preserving OCR', () => {
    const rows = ['ACCESS_ANY_ORG', 'GLOBAL_USER_MANAGE', 'GLOBAL_CATALOG_VIEW'].map(code => ({ code, scope: 'PLATFORM' }));
    expect(editableCapabilities(rows, 'PLATFORM').map(c => c.code)).toEqual(['GLOBAL_CATALOG_VIEW']);
    expect(editableCapabilities(['DOCUMENTS_UPLOAD', 'DOCUMENTS_OCR_PROCESS', 'DOCUMENTS_OCR_VERIFY', 'RECIPES_VIEW', 'INVENTORY_VIEW']
        .map(code => ({ code, scope: 'ORGANIZATION' })), 'ORGANIZATION').map(c => c.code))
        .toEqual(['DOCUMENTS_UPLOAD', 'DOCUMENTS_OCR_PROCESS', 'DOCUMENTS_OCR_VERIFY']);
});
test.each([
    [{ inherited: true, overrides: ['ALLOW', 'DENY'] }, false, 'DENY'],
    [{ inherited: false, overrides: ['ALLOW'] }, true, 'ALLOW'],
    [{ inherited: true }, true, 'INHERITED'],
    [{ inherited: false }, false, 'INHERITED'],
    [{ inherited: true, active: false, overrides: ['ALLOW'] }, false, 'ALLOW']
])('permission preview uses DENY > ALLOW > inherited with active gating %j', (input, effective, effect) => {
    expect(permissionPreview(input)).toMatchObject({ effective, effect });
});
test('service forwards only RPC payload and propagates server errors', async () => {
    const client = { rpc: jest.fn().mockResolvedValueOnce({ data: { rights: {} } }).mockResolvedValueOnce({ error: { message: 'Denied' } }) };
    const service = createAdministrationService(client);
    await service.read('org', 'email');
    expect(client.rpc).toHaveBeenCalledWith('mica_admin_read', { p_org: 'org', p_search: 'email' });
    await expect(service.apply('user', { user_profile_id: 'target' })).rejects.toThrow('Denied');
});
test('view discards old tenant response and clears data on logout', async () => {
    const previous = global.document;
    global.document = { createElement: () => ({ textContent: '', children: [], append(...nodes) { this.children.push(...nodes); } }) };
    const root = { children: [], replaceChildren(...nodes) { this.children = nodes; } };
    const store = { sessionUserId: 'actor', contextGeneration: 1, contextState: 'TENANT_READY', activeOrganizationId: 'NORTE', subscribe(fn) { this.listener = fn; } };
    const pending = [];
    const service = { read: jest.fn(() => new Promise(resolve => pending.push(resolve))) };
    try {
        const view = createAdministrationView(root, store, service);
        const norte = view.load();
        store.activeOrganizationId = 'SUR'; ++store.contextGeneration;
        const sur = view.load();
        pending[1]({ rights: {}, tenant: 'SUR' }); await sur;
        pending[0]({ rights: {}, tenant: 'NORTE' }); await norte;
        expect(view.snapshot.tenant).toBe('SUR');
        store.contextState = 'SIGNED_OUT'; store.sessionUserId = null; store.listener();
        expect(view.snapshot).toBeNull();
    } finally { global.document = previous; }
});
test('mock configuration is replaced; imported operational controls are untouched by the new component', () => {
    const html = read('index.html').split('<section id="tab-configuracion"')[1].split('</section>')[0];
    expect(html).toContain('mica-administration');
    expect(html).not.toMatch(/emiliano_admin|micaela_contable|VARONE/);
    const ui = read('src/js/components/administration.js');
    expect(ui).not.toMatch(/innerHTML|import-box|SUPERADMIN/);
    expect(ui).toContain('++store.pendingOperations');
    expect(ui).toContain('token !== epoch');
});

test('approving a pending tenant establishes initial context and client refreshes operational targets', () => {
    expect(up).toContain('Initial context requires an active membership and organization');
    expect(up).toContain('INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(target,org)');
    expect(db).toContain('Approval failed to establish initial tenant context');
    expect(read('src/js/components/administration.js')).toContain('await store.reloadOperationalContext()');
});
test('organization form sends real values server-first and reloads confirmed state after success', async () => {
    const previousDocument = global.document, previousFormData = global.FormData;
    function node(tag) {
        return { tag, children: [], events: {}, textContent: '', append(...items) { this.children.push(...items); },
            replaceChildren(...items) { this.children = items; }, addEventListener(name, fn) { this.events[name] = fn; } };
    }
    function all(n) { return [n, ...(n.children || []).filter(x => typeof x === 'object').flatMap(all)]; }
    global.document = { createElement: node };
    global.FormData = class { constructor(f) { this.values = new Map(all(f).filter(x => x.name).map(x => [x.name, x.value])); }
        has(k) { return this.values.has(k); } get(k) { return this.values.get(k); } };
    try {
        const root = node('root');
        const store = { sessionUserId: 'actor', contextGeneration: 1, contextState: 'PLATFORM_READY', activeOrganizationId: null,
            pendingOperations: 0, subscribe() {}, reloadOperationalContext: jest.fn().mockResolvedValue() };
        let resolveSave;
        const service = {
            read: jest.fn().mockResolvedValue({ rights: { organizations: true, create_organization: true },
                organizations: [], users: [], presets: [], capabilities: [] }),
            apply: jest.fn(() => new Promise(resolve => { resolveSave = resolve; }))
        };
        await createAdministrationView(root, store, service).load();
        all(root).find(n => n.textContent === 'Nueva organización').onclick();
        const form = all(root).find(n => n.tag === 'form');
        all(form).find(n => n.name === 'name').value = '<NORTE>';
        const save = form.events.submit({ preventDefault() {} });
        expect(service.apply).toHaveBeenCalledWith('organization', { name: '<NORTE>', legal_name: '', trade_name: '', tax_id: '' });
        expect(store.reloadOperationalContext).not.toHaveBeenCalled();
        expect(store.pendingOperations).toBe(1);
        resolveSave('new-org'); await save;
        expect(store.reloadOperationalContext).toHaveBeenCalledTimes(1);
        expect(store.pendingOperations).toBe(0);
    } finally { global.document = previousDocument; global.FormData = previousFormData; }
});
