// Static release contracts only; these tests never execute SQL.
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(path,'utf8').replaceAll('\r','');
const up=read('sql/039h_operational_administration.sql');

test.each([
 ['eco_role_template_capabilities','ORGANIZATION'],
 ['eco_platform_role_org_capabilities','PLATFORM']
])('compatibility propagation to %s requires matching template scope %s', (table,scope)=>{
 const statement=up.match(new RegExp(`INSERT INTO public\\.${table}\\(role_template_id,capability_id\\)\\s+SELECT g\\.role_template_id,cap[^;]+;`))?.[0];
 expect(statement).toBeDefined();
 expect(statement).toContain(`FROM public.${table} g`);
 expect(statement).toContain('JOIN public.eco_role_templates source_template ON source_template.id=g.role_template_id');
 expect(statement).toContain(`source_template.scope='${scope}'`);
 expect(statement).toContain("c.code='ORG_MEMBER_PERMISSION_MANAGE' AND c.scope='ORGANIZATION'");
 expect(statement).not.toMatch(/OR\s+source_template\.scope\s+IS\s+NULL/i);
});

test('preflight classifies legacy sources and rejects non-null scope/table mismatches',()=>{
 const preflight=up.split('END; $preflight$;')[0];
 expect(preflight.match(/source_template.scope IS NOT NULL/g)).toHaveLength(2);
 for(const scope of ['ORGANIZATION','PLATFORM']) expect(preflight).toContain(`source_template.scope<>'${scope}'`);
 expect(preflight).toContain('Unexpected non-legacy propagation scope/table');
 const readonly=read('sql/039h_preflight_readonly.sql');
 for(const classification of ['IGNORE_LEGACY_NULL','ABORT_SCOPE_MISMATCH','PRESERVE_HISTORY_DEPRECATE','PROPAGATE']) expect(readonly).toContain(classification);
});

test('legacy snapshots and grant guards protect UP, harness and rollback',()=>{
 expect(up).toContain('legacy_before=jsonb_build_object(');
 expect(up).toContain('Legacy templates or grants changed');
 expect(up.match(/036 grant guards must remain active/g)).toHaveLength(2);
 expect(up).not.toMatch(/DISABLE TRIGGER|session_replication_role/);
 const down=read('sql/039h_operational_administration_down.sql');
 expect(down).toContain('Propagation scope drift; do not alter historical grants');
 expect(down).toContain('IS DISTINCT FROM b.compat_grants');
 const harness=read('tests/db/039h_operational_administration.sql');
 for(const text of ['MICA_ORG_ADMIN assignment grant missing','Root/operational assignment bridge missing',
  'OWNER or other NULL-scope legacy received assignment capability','Grant guards are not active','Legacy templates/grants snapshot differs']) expect(harness).toContain(text);
 expect(read('tests/db/039h_membership_roundtrip.sql')).toContain('Roundtrip changed legacy templates or grants');
});
