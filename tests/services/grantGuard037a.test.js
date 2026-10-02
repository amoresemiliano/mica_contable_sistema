// Static contracts only. PostgreSQL regression harnesses must be run separately.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const read = p => readFileSync(p, 'utf8').replace(/\r/g, '');
const up = read('sql/037a_fix_guard_036_grant.sql');
const down = read('sql/037a_fix_guard_036_grant_down.sql');
const db = read('tests/db/037a_fix_guard_036_grant.sql');
const original = read('sql/036_owner_core_and_delegation_guard.sql');
const extract = sql => sql.match(/FUNCTION private\.guard_036_grant\(\)[\s\S]*?AS \$\$([\s\S]*?)\$\$;/)[1];
const oldBody = extract(original);
const body = extract(up);
const baseline = {
  "036_owner_core_and_delegation_guard.sql": "6fba0e969a90152dc5511670f82c63c34a8ff195626f0a244437e6513faf8d3f",
  "036_owner_core_and_delegation_guard_down.sql": "9a28ea8c9b5efecc0b1de14f7664c8250d973157a6b2d7f06ffba83ec4436007",
  "037_platform_tenant_operation.sql": "1e0cb142d4265ead083e2c9ada934aa02c5d8e618b20acf99022aee14bee8273",
  "037_platform_tenant_operation_down.sql": "8dba6697778aeb5eff05e6dcf54f388f9b9c0628aade34133aa93db710852856"
};
test.each(Object.entries(baseline))('037a preserves original migration %s', (file, hash) => {
    expect(createHash('sha256').update(readFileSync('sql/' + file)).digest('hex')).toBe(hash);
});
test('preflight fingerprints the actual defective body before replacing only the guard', () => {
    const hash = createHash('md5').update(oldBody.trim()).digest('hex');
    expect(up).toContain("='" + hash + "'");
    expect(up.indexOf(hash)).toBeLessThan(up.indexOf('CREATE OR REPLACE FUNCTION'));
    expect(up.match(/CREATE OR REPLACE FUNCTION [^(]+/g)).toEqual(['CREATE OR REPLACE FUNCTION private.guard_036_grant']);
    expect(up).toContain("SECURITY DEFINER SET search_path = ''");
    expect(up).toContain("p.proconfig=ARRAY['search_path=\"\"']::TEXT[]");
    expect(up).not.toMatch(/(?:CREATE|DROP|ALTER) TRIGGER/);
});
test('membership branch checks organization scope without accessing template columns', () => {
    const membership = body.split("ELSIF TG_TABLE_NAME='eco_membership_capability_overrides' THEN")[1].split('  ELSE')[0];
    expect(membership).toContain("v_scope<>'ORGANIZATION'");
    expect(membership).not.toContain('role_template_id');
    expect(body).not.toMatch(/TG_TABLE_NAME=.* AND NOT EXISTS/);
    const bridge = body.split("ELSIF TG_TABLE_NAME='eco_platform_role_org_capabilities' THEN")[1].split('  ELSIF')[0];
    expect(bridge).toContain("v_scope<>'ORGANIZATION'");
    expect(bridge).toContain("id=NEW.role_template_id AND scope='PLATFORM'");
});
test('reserved barrier, legacy handling and the two prior typed branches are unchanged', () => {
    const prefix = oldBody.slice(0, oldBody.indexOf('  ELSE\n'));
    expect(body.startsWith(prefix)).toBe(true);
    expect(body.indexOf("v_class='OWNER_RESERVED'")).toBeLessThan(body.indexOf("eco_member_capability_overrides"));
    expect(body).toContain("IF TG_TABLE_NAME='eco_member_capability_overrides' THEN RETURN NEW; END IF;");
    expect(body).not.toMatch(/NEW\.effect|SUPERADMIN|can_org/);
});
test('backup preserves exact definition, owner and ACL; replacement preserves function identity', () => {
    expect(up).toContain('pg_get_functiondef(oid),pg_get_userbyid(proowner),proacl');
    expect(up).toContain('oid=b.function_oid');
    expect(up).toContain('proacl IS NOT DISTINCT FROM b.acl');
    expect(up).toContain('ENABLE ROW LEVEL SECURITY');
    expect(up).toContain('FROM PUBLIC,anon,authenticated');
    expect(up).toContain('aclexplode(');
    expect(up).not.toMatch(/(?:GRANT|REVOKE).*ON FUNCTION/);
});
test('down refuses drift before restoring exact captured body and removing only its backup', () => {
    for (const check of ['oid=b.function_oid', 'pg_get_functiondef(oid)=b.installed_definition',
        'pg_get_userbyid(proowner)=b.owner_name', 'proacl IS NOT DISTINCT FROM b.acl']) {
        expect(down).toContain(check);
        expect(down.indexOf(check)).toBeLessThan(down.indexOf('EXECUTE b.definition'));
    }
    expect(down).toContain('pg_get_functiondef(oid)=b.definition');
    expect(down.match(/DROP [^;]+;/g)).toEqual(['DROP TABLE private.migration_037a_guard_backup;']);
    expect(up + down).not.toMatch(/\bCASCADE\b/);
});
test('SQL harness covers membership INSERT/UPDATE effects and rejects wrong/reserved capabilities', () => {
    for (const effect of ['ALLOW', 'DENY']) {
        expect(db).toContain("VALUES(v_member,v_org_cap,'" + effect + "')");
        expect(db).toContain("SET effect='" + effect + "'");
    }
    expect(db).toContain('ARRAY[v_platform_cap,v_reserved]');
    expect(db).toContain('SET capability_id=$2 WHERE membership_id=$1 AND capability_id=$3');
    expect(db).toContain('EXCEPTION WHEN insufficient_privilege THEN NULL');
    expect(db).not.toMatch(/WHEN (?:OTHERS|undefined_column)/);
    expect(db).toMatch(/BEGIN;[\s\S]*ROLLBACK;\s*$/);
    expect(db).not.toMatch(/TENANT_ADMIN|\\set|:'\w+'/);
});
test('negative template and bridge updates target rows actually inserted by fixtures', () => {
    expect(db).toContain('VALUES(v_platform_template,v_platform_cap),(v_org_template,v_org_cap)');
    expect(db).toContain('VALUES($1,$3)');
    expect(db).toContain('VALUES($2,$4)');
    expect(db).toContain('SET capability_id=$3 WHERE role_template_id=$1 AND capability_id=$4');
    expect(db).toContain('SET role_template_id=$2 WHERE role_template_id=$1 AND capability_id=$3');
    expect(db).toContain('SET capability_id=$3 WHERE user_profile_id=$5 AND capability_id=$6');
});
test('036 harness now reaches valid membership writes that previously escaped coverage', () => {
    const regression = read('tests/db/036_owner_core.sql');
    expect(regression).toContain("VALUES(v_regression_member,v_regression_cap,'ALLOW')");
    expect(regression).toContain("VALUES(v_regression_member,v_regression_cap,'DENY')");
    expect(regression).toContain("SET effect='DENY' WHERE membership_id=v_regression_member");
    expect(regression).toContain("SET effect='ALLOW' WHERE membership_id=v_regression_member");
    expect(regression).toMatch(/BEGIN;[\s\S]*ROLLBACK;\s*$/);
});
