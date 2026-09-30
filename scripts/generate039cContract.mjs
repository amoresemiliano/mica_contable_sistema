// Generates local review artifacts. Never connects to a database.
import fs from 'node:fs';
import { MICA_PERMISSION_CATALOG, MICA_PRESET_DEFINITIONS, MICA_IMPORT_CONTRACT } from '../src/js/core/micaPermissionContract.js';
const check=process.argv.includes('--check');
function output(path,text) {
    if(check) { if(fs.readFileSync(path,'utf8').replaceAll('\r','')!==text.replaceAll('\r','')) throw Error('Out of date: '+path); }
    else fs.writeFileSync(path,text);
}
const cap=MICA_PERMISSION_CATALOG.find(c=>c.code==='FISCAL_DOCUMENT_IMPORT');
const tenants=cap.defaultPresets.filter(p=>MICA_PRESET_DEFINITIONS[p].scope==='ORGANIZATION');
const seed=`-- BEGIN GENERATED 039C FISCAL SEED
DO $seed$
DECLARE cap UUID; r RECORD;
BEGIN
 INSERT INTO public.eco_capabilities(code,description,scope,is_active,delegation_class)
 VALUES('${cap.code}','${cap.label}','${cap.scope}',TRUE,'${cap.delegationClass}') RETURNING id INTO cap;
 FOR r IN INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
  SELECT id,cap FROM public.eco_role_templates WHERE code IN (${tenants.map(p=>"'"+p+"'").join(',')})
  RETURNING * LOOP
  INSERT INTO private.migration_039c_grants VALUES('public.eco_role_template_capabilities',to_jsonb(r));
 END LOOP;
 FOR r IN INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
  SELECT t.id,cap FROM public.eco_role_templates t WHERE t.code='ACCOUNTING_SUPERADMIN' OR t.id IN (
   SELECT a.role_template_id FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id)
  RETURNING * LOOP
  INSERT INTO private.migration_039c_grants VALUES('public.eco_platform_role_org_capabilities',to_jsonb(r));
 END LOOP;
END; $seed$;
-- END GENERATED 039C FISCAL SEED`;
const path='sql/039c_functional_stabilization.sql';
output(path,fs.readFileSync(path,'utf8').replace(/-- BEGIN GENERATED 039C FISCAL SEED[\s\S]*?-- END GENERATED 039C FISCAL SEED/,seed));
let doc='# 039c — Contrato preparado, no aplicado\n\n| Importador | Requisitos | Habilitado |\n|---|---|---|\n';
for(const [type,rule] of Object.entries(MICA_IMPORT_CONTRACT)) doc+=`| ${type} | ${rule.all.join(' + ')} | ${rule.enabled?'Sí':'No'} |\n`;
doc+='\n| Capability | Runtime preparado | Presets |\n|---|---|---|\n';
for(const c of MICA_PERMISSION_CATALOG.filter(c=>c.code===cap.code||c.code.startsWith('MANUAL_MOVEMENT_'))) doc+=`| ${c.code} | ${c.runtimeStatus} | ${c.defaultPresets.map(p=>MICA_PRESET_DEFINITIONS[p].label).join(', ')} |\n`;
output('docs/039c_CONTRACT.md',doc);
console.log(check?'039c artifacts match.':'039c artifacts generated; no SQL executed.');
