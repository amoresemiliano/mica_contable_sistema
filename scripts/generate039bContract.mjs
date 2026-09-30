// Generates review artifacts only. Never connects to a DB or executes SQL.
import fs from 'node:fs';
import { MICA_PERMISSION_CATALOG_039B as catalog, MICA_PRESET_DEFINITIONS as presets, PERMISSION_GROUPS as groups,
    SCOPE_LABELS, MICA_BUSINESS_FUNCTIONS } from '../src/js/core/micaPermissionContract.js';
const presetCapabilities = (preset, scope) => catalog.filter(c=>c.scope===scope && c.defaultPresets.includes(preset)).map(c=>c.code);
const check = process.argv.includes('--check');
const quote = s => "'" + s.replaceAll("'", "''") + "'";
const array = list => 'ARRAY[' + list.map(quote).join(',') + ']::TEXT[]';
function output(path, text) {
    if (check) {
        if (!fs.existsSync(path) || fs.readFileSync(path,'utf8').replaceAll('\r','') !== text.replaceAll('\r',''))
            throw new Error('Generated contract out of date: '+path);
    } else fs.writeFileSync(path,text);
}
let sql = fs.readFileSync('sql/039b_operational_access_and_ux.sql','utf8');
for (const [code,preset] of Object.entries(presets).filter(([,p])=>p.scope==='ORGANIZATION')) {
    const pattern = new RegExp('\\('+quote(code)+',ARRAY\\[[^\\]]*\\]::TEXT\\[\\](?:,\'[^\']*\')?\\)');
    if (!pattern.test(sql)) throw new Error('Missing seed: '+code);
    sql=sql.replace(pattern,`(${quote(code)},${array(presetCapabilities(code,'ORGANIZATION'))},${quote(preset.label)})`);
}
sql=sql.replace('x(code,caps) LOOP','x(code,caps,label) LOOP').replace("VALUES(spec.code,replace(spec.code,'_',' '),'ORGANIZATION'","VALUES(spec.code,spec.label,'ORGANIZATION'");
// Platform lists are in canonical catalog order. Match only the two accounting seed lists.
sql=sql.replace(/ARRAY\['(?:DATA_RESTORE_ANY_ORG','|)MICA_ADMIN_MANAGE','ORGANIZATION_UPDATE'[^\]]*\]::TEXT\[\]/g,array(presetCapabilities('ACCOUNTING_SUPERADMIN','PLATFORM')));
// Both server allowlist and bridge grants come from the same approved catalog.
sql=sql.replace(/(CREATE OR REPLACE FUNCTION private\.mica_capability_allowed[\s\S]*?FROM \(VALUES\n)[\s\S]*?(\n  \) allowed\(code,scope\))/,(_,start,end)=>start+
    catalog.filter(c=>c.status!=='PROPOSED').map(c=>`    (${quote(c.code)},${quote(c.scope)})`).join(',\n')+end);
sql=sql.replace(/(WHERE c.code=ANY\()ARRAY\['ORG_VIEW'[^\]]*\]::TEXT\[\](\) AND c.scope='ORGANIZATION')/,
    (_,start,end)=>start+array(presetCapabilities('ROOT_TECHNICAL_MICA','ORGANIZATION'))+end);
const additions=catalog.filter(c=>c.status==='PREPARED_039B');
const manifestPath='sql/039b_live_adoption_manifest.json';
const manifest=JSON.parse(fs.readFileSync(manifestPath,'utf8'));
if (Object.keys(manifest).sort().join()!==additions.map(c=>c.code).sort().join()) throw new Error('Adoption manifest codes differ');
const adoptionRows=additions.map(c=>`    (${quote(c.code)},${quote(c.scope)},${quote(c.delegationClass)},${manifest[c.code]===null?'NULL::JSONB':quote(JSON.stringify(manifest[c.code]))+'::JSONB'})`).join(',\n');
const adoption=`-- BEGIN GENERATED ADOPTION PREFLIGHT
  -- NULL means verified expectation of absence. Existing rows require an exact reviewed LIVE snapshot.
  FOR r IN SELECT * FROM (VALUES
${adoptionRows}
  ) x(code,scope,delegation_class,expected) LOOP
    IF r.expected IS NULL THEN
      IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code=r.code) THEN
        RAISE EXCEPTION '039b collision: review LIVE and fill adoption manifest for %',r.code; END IF;
    ELSIF NOT EXISTS(SELECT 1 FROM public.eco_capabilities c WHERE c.code=r.code AND c.scope=r.scope
      AND c.delegation_class=r.delegation_class AND c.is_active AND to_jsonb(c)=r.expected) THEN
      RAISE EXCEPTION '039b exact adoption preflight differs: %',r.code;
    END IF;
  END LOOP;
  -- END GENERATED ADOPTION PREFLIGHT`;
sql=sql.replace(/-- BEGIN GENERATED ADOPTION PREFLIGHT[\s\S]*?-- END GENERATED ADOPTION PREFLIGHT/,adoption);
const seed=`-- BEGIN GENERATED CAPABILITY SEED
  -- Adopted rows keep their UUID, metadata and grants; no grant is copied from another product.
  FOR r IN INSERT INTO public.eco_capabilities(code,description,scope,is_active,delegation_class)
    SELECT x.code,x.description,x.scope,TRUE,x.delegation_class FROM (VALUES
${additions.map(c=>`      (${quote(c.code)},${quote(c.label+' — '+c.description)},${quote(c.scope)},${quote(c.delegationClass)})`).join(',\n')}
    ) x(code,description,scope,delegation_class)
    WHERE NOT EXISTS(SELECT 1 FROM public.eco_capabilities c WHERE c.code=x.code) RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed)
      VALUES('public.eco_capabilities',jsonb_build_object('id',r.id),to_jsonb(r));
  END LOOP;
  -- END GENERATED CAPABILITY SEED`;
sql=sql.replace(/-- BEGIN GENERATED CAPABILITY SEED[\s\S]*?-- END GENERATED CAPABILITY SEED/,seed);
output('sql/039b_operational_access_and_ux.sql',sql);
let doc='# 039b — Contrato de permisos y matriz de presets\n\nGenerado desde `src/js/core/micaPermissionContract.js`. No editar las tablas a mano.\n\n';
doc+='CURRENT = contrato vigente; PREPARED_039B = SQL preparado, no aplicado; PROPOSED = propuesta, no asignable ni visible en el editor. Ninguna etiqueta concede autoridad.\n\n';
doc+='| Preset | Grants PLATFORM | Grants ORGANIZATION |\n|---|---|---|\n';
for(const [code,preset] of Object.entries(presets)) doc+=`| ${preset.label} | ${presetCapabilities(code,'PLATFORM').length} | ${presetCapabilities(code,'ORGANIZATION').length} |\n`;
doc+='\n';
for(const scope of ['PLATFORM','ORGANIZATION']) {
    doc+='## '+SCOPE_LABELS[scope]+'\n\n| Capability | Nombre | Función | Grupo | Estado | Runtime | Asignable | Reservada | Editor | Orden |\n|---|---|---|---|---|---|---|---|---|---|\n';
    for(const c of catalog.filter(c=>c.scope===scope)) doc+=`| \`${c.code}\` | ${c.label} | ${c.description} | ${groups[c.group]} | ${c.status} | ${c.runtimeStatus} | ${c.assignable?'Sí':'No'} | ${c.ownerReserved?'Sí':'No'} | ${c.visibleInEditor?'Sí':'No'} | ${c.order} |\n`;
    doc+='\n### Presets × capability\n\n| Capability | '+Object.values(presets).map(p=>p.label).join(' | ')+' |\n|---|'+Object.keys(presets).map(()=>'---|').join('')+'\n';
    for(const c of catalog.filter(c=>c.scope===scope)) doc+='| `'+c.code+'` | '+Object.keys(presets).map(p=>c.defaultPresets.includes(p)?'✅':'—').join(' | ')+' |\n';
    doc+='\n';
}
doc+='El preset es una base: ALLOW amplía y DENY restringe capacidades delegables dentro del alcance. OWNER_RESERVED nunca puede obtenerse por override. RECORD_RESTORE se administra sólo en bridges/platform scopes MICA, no en presets/memberships tenant nuevos. Los grants históricos se conservan, pero ambos RPC exigen además DATA_RESTORE_ANY_ORG efectiva y alcance de plataforma. Ningún tenant restaura con RECORD_RESTORE solo.\n';
doc+='\n## Funciones que comparten permiso vigente\n\n| Función | Grupo | Capability compartida |\n|---|---|---|\n';
for(const fn of MICA_BUSINESS_FUNCTIONS) doc+=`| ${fn.label} | ${groups[fn.group]} | \`${fn.capability}\` |\n`;
doc+='\nNo se ofrecen checkboxes independientes para estas funciones: revocar RECORD_VIEW afecta a todos sus módulos. Conciliar/confirmar no se infiere de clasificar: RECONCILIATION_VIEW/CONFIRM siguen como propuestas.\n';
output('docs/039b_PERMISSION_MATRIX.md',doc);
// Preflight contains SELECT statements only. It never assumes repository state equals LIVE.
const promotedCodes=[...additions.map(c=>c.code),'RECORD_RESTORE'];
const signatures=[...sql.matchAll(/\('((?:private|public)\.[a-z_0-9]+\([^']*\))','[a-f0-9]{32}'\)/g)].map(m=>m[1]);
const preflight=`-- MICA canonical project: ourzapkjykzlwsjunzmd. READ ONLY. Prepared, NOT executed.
-- Existing capability adoption requires copying its complete row into 039b_live_adoption_manifest.json
-- only after reviewing identity, scope, delegation class, active state and all historical grants below.
-- Regenerate artifacts afterward. NULL in that manifest expects ABSENCE; it never silently adopts.
SELECT current_database(),current_user;
SELECT wanted.code,to_jsonb(c) AS exact_adoption_snapshot
FROM unnest(${array(promotedCodes)}) wanted(code)
LEFT JOIN public.eco_capabilities c ON c.code=wanted.code ORDER BY wanted.code;

SELECT p.oid::regprocedure::TEXT AS signature,pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef,p.proconfig,p.proacl,
  md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS body_md5,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p WHERE p.oid IN (SELECT to_regprocedure(x) FROM unnest(${array([...new Set(signatures)])}) x)
ORDER BY signature;

-- Includes every historic restore grant/override and references to promoted capabilities.
SELECT c.code,'template' AS source,to_jsonb(g) AS grant_row,to_jsonb(t) AS preset
FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_role_templates t ON t.id=g.role_template_id WHERE c.code=ANY(${array(promotedCodes)})
UNION ALL SELECT c.code,'bridge',to_jsonb(g),to_jsonb(t)
FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_role_templates t ON t.id=g.role_template_id WHERE c.code=ANY(${array(promotedCodes)})
UNION ALL SELECT c.code,'membership_override',to_jsonb(g),to_jsonb(m)
FROM public.eco_membership_capability_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_organization_members m ON m.id=g.membership_id WHERE c.code=ANY(${array(promotedCodes)})
UNION ALL SELECT c.code,'platform_override',to_jsonb(g),NULL::JSONB
FROM public.eco_user_platform_capability_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code=ANY(${array(promotedCodes)})
UNION ALL SELECT c.code,'platform_org_override',to_jsonb(g),NULL::JSONB
FROM private.eco_platform_org_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code=ANY(${array(promotedCodes)})
ORDER BY code,source;

WITH target AS (
 SELECT role_template_id AS id FROM public.eco_user_platform_role WHERE user_profile_id IN(SELECT user_profile_id FROM private.eco_platform_owner)
 UNION SELECT id FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN'
)
SELECT to_jsonb(t) AS preset,
 (SELECT jsonb_agg(to_jsonb(a)) FROM public.eco_user_platform_role a WHERE a.role_template_id=t.id) AS recipients,
 (SELECT jsonb_agg(to_jsonb(c)) FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=t.id) AS platform_grants,
 (SELECT jsonb_agg(to_jsonb(c)) FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=t.id) AS bridge_grants
FROM public.eco_role_templates t JOIN target ON target.id=t.id;
SELECT to_jsonb(o) AS structural_owner FROM private.eco_platform_owner o;
SELECT to_jsonb(s) AS scope FROM private.eco_platform_org_scopes s WHERE s.user_profile_id IN (
 SELECT a.user_profile_id FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id WHERE t.code='ACCOUNTING_SUPERADMIN');
`;
output('sql/039b_preflight_live_readonly.sql',preflight);
let runtime='# 039b — Disponibilidad operativa\n\nGenerado desde micaPermissionContract.js. Describe la implementación preparada, no una validación LIVE. ACTIVE no significa grant automático. DISABLED_PENDING_BACKEND permite asignar el permiso aprobado, pero no ejecutar una función inexistente. Las propuestas siguen sin ser asignables.\n\n';
for(const state of ['ACTIVE','DISABLED_PENDING_BACKEND']) {
 runtime+='## '+state+'\n\n| Código | Función | Estado del contrato |\n|---|---|---|\n';
 for(const c of catalog.filter(c=>c.runtimeStatus===state)) runtime+=`| \`${c.code}\` | ${c.label} | ${c.status} |\n`;
 runtime+='\n';
}
runtime+='Los códigos ACTIVE mantienen sus operaciones y controles existentes; no crean módulos nuevos. Restauración se implementa en ambos RPC con doble permiso y alcance. Los códigos nuevos de proveedores/compras/ventas/personal/integraciones y manuales son asignables con backend específico pendiente. Las vistas compartidas actuales siguen usando RECORD_VIEW. OCR, importación fiscal y confirmación de conciliaciones continúan cerrados.\n';
output('docs/039b_RUNTIME_STATUS.md',runtime);
console.log(check?'Contract artifacts match.':'Contract artifacts generated (no SQL executed).');
