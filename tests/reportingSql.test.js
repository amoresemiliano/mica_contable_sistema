import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8'),up=read('sql/045_management_reporting.sql'),down=read('sql/045_management_reporting_down.sql');
test('additive migration fails closed and never replaces canonical ownership, rate or authorization contracts',()=>{
 expect(up).toContain('045 already installed or partial installation');expect(up).toContain("current_user <> 'postgres'");expect(up).not.toContain('CREATE OR REPLACE');
 expect(up).toContain('FROM public.eco_org_activity_iibb_rates r');expect(up).toContain('r.valid_from<=f.day');expect(up).toContain('r.valid_to>=f.day');expect(up).not.toContain('CREATE TABLE public.');
});
test('every public RPC is SECURITY DEFINER with empty search_path and explicit non-public grants',()=>{
 const functions=[...up.matchAll(/CREATE FUNCTION public\.([\s\S]*?)END; \$\$;/g)];expect(functions).toHaveLength(5);
 for(const [definition] of functions){expect(definition).toContain("SECURITY DEFINER SET search_path=''");expect(definition).toMatch(/require_039_action|reporting_045_context/);}
 expect(up).toContain('FROM PUBLIC,anon,authenticated');expect(up).not.toMatch(/GRANT[^;]+TO (PUBLIC|anon)/);expect(up).toContain('mica_reporting_service(UUID,UUID,TEXT,JSONB) TO service_role');
});
test('tenant filtering applies to aggregates, details, manual inputs, snapshots and history',()=>{
 for(const table of ['eco_report_inputs','eco_report_snapshots','eco_report_events'])expect(up).toContain(`ALTER TABLE private.${table} ENABLE ROW LEVEL SECURITY`);
 expect(up).toContain('org IS DISTINCT FROM p_expected_org');expect(up).toContain('f.organization_id=org');expect(up).toContain('s.id=p_snapshot AND s.organization_id=org');expect(up).toContain("IF auth.role() IS DISTINCT FROM 'service_role'");
 expect(up).toContain("'REPORT_EXPORT'");expect(up).toContain("'MANUAL_MOVEMENT_EDIT'");expect(up).toContain('p_subject::TEXT');
});
test('source acceptance, NC signs, missing values and account ambiguity are explicit',()=>{
 expect(up).toContain("ir.parse_status='ACCEPTED'");expect(up).toContain("n.status='ACCEPTED'");expect(up).toContain("('3','8','13','203','208','213') THEN -1");
 expect(up).toContain('missing_net');expect(up).toContain('missing_vat');expect(up).toContain('x.day=b.last_day)=1');expect(up).toContain("p->>'moneda'");
});
test('history is immutable, close is source-hash guarded and rollback retains accounting history',()=>{
 expect(up.match(/BEFORE UPDATE OR DELETE/g)).toHaveLength(3);expect(up).toContain('input_hash');expect(up).toContain('IS DISTINCT FROM p_data');expect(up).toContain('IN SHARE MODE');expect(up).toContain('source_manifest');expect(up).toContain('Only a closed report can be reopened');
 expect(down).not.toMatch(/\b(DROP TABLE|DELETE FROM|TRUNCATE)\b/i);expect(down).toContain('Append-only tables');
});
