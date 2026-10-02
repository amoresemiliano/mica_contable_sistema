// Offline artifact generator. Never connects to a database or executes SQL.
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {MICA_PERMISSION_CATALOG} from '../src/js/core/micaPermissionContract.js';
const read=p=>fs.readFileSync(p,'utf8').replaceAll('\r','');
const q=s=>"'"+s.replaceAll("'","''")+"'";
const manifest=JSON.parse(read('sql/039h_live_target_manifest.json'));
const reviewedMemberships=JSON.parse(read('sql/039h_reviewed_memberships.json'));
const json=x=>x===null?'NULL::JSONB':q(JSON.stringify(x))+'::JSONB';
const specs=[['039b_operational_access_and_ux.sql','public.mica_admin_apply','text,jsonb'],
 ['039b_operational_access_and_ux.sql','public.mica_admin_read','uuid,text'],
 ['039c_functional_stabilization.sql','public.mica_invitation','text,uuid,jsonb'],
 ['039c_functional_stabilization.sql','private.mica_capability_allowed','text,text']];
const functions=specs.map(([file,name,args])=>{
 const source=read('sql/'+file), start=source.search(new RegExp('CREATE (?:OR REPLACE )?FUNCTION '+name.replaceAll('.','\\.')+'\\('));
 const definition=source.slice(start).match(/^[\s\S]*?AS \$\$[\s\S]*?\$\$;/)[0].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION');
 return {name,signature:name+'('+args+')',definition,hash:createHash('md5').update(definition.match(/AS \$\$([\s\S]*?)\$\$/)[1].trim()).digest('hex')};
});
const replace=(text,a,b)=>{if(text.split(a).length!==2)throw Error('Nonunique replacement: '+a);return text.replace(a,b);};
for(const f of functions) {
 let d=f.definition;
 if(f.name==='private.mica_capability_allowed') d=replace(d,"('FISCAL_DOCUMENT_IMPORT','ORGANIZATION'),","('ORG_MEMBER_PRESET_ASSIGN','ORGANIZATION'),\n    ('FISCAL_DOCUMENT_IMPORT','ORGANIZATION'),");
 if(f.name==='public.mica_admin_apply') {
  d=replace(d,'PERFORM pg_advisory_xact_lock(380038);',`PERFORM pg_advisory_xact_lock(380038);
  IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN'
    AND ((p_action='preset' AND id=result) OR (p_action IN ('platform_role','membership') AND id=tpl))) THEN
    RAISE EXCEPTION 'Deprecated preset is historical only' USING ERRCODE='42501'; END IF;`);
  d=replace(d,"PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');\n      IF EXISTS", "PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PRESET_ASSIGN');\n      IF EXISTS");
  // A fixed existing preset can be assigned without permission-editor authority. Still cannot exceed own grants.
  d=replace(d,"ELSE RAISE EXCEPTION 'Unknown administration action';",`ELSIF p_action='tenant_activate' THEN
    PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_MANAGE');
    PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PRESET_ASSIGN');
    PERFORM private.admin_038_target(target);
    IF org IS NULL OR NOT EXISTS(SELECT 1 FROM public.eco_organization_members
      WHERE user_profile_id=target AND organization_id=org AND is_active)
      OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target)
      OR NOT EXISTS(SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=target AND approved_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM private.eco_mica_invitations WHERE assigned_to=target AND organization_id=org AND assigned_at IS NOT NULL)
      OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND organization_id<>org)
      OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
        WHERE p.id=target AND NOT p.is_active AND u.email_confirmed_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Only an invited confirmed pending tenant may be initially activated' USING ERRCODE='42501'; END IF;
    UPDATE public.eco_user_profiles SET is_active=TRUE,organization_id=org WHERE id=target;
    INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(target,org)
      ON CONFLICT(user_profile_id) DO UPDATE SET organization_id=EXCLUDED.organization_id,updated_at=now();
    UPDATE private.eco_mica_pending_profiles SET approved_at=now() WHERE user_profile_id=target;
    result:=target;
  ELSE RAISE EXCEPTION 'Unknown administration action';`);
 }
 if(f.name==='public.mica_invitation') d=replace(d,"PERFORM private.admin_038_authorize(p_org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');","PERFORM private.admin_038_authorize(p_org,NULL,'ORG_MEMBER_PRESET_ASSIGN');");
 if(f.name==='public.mica_admin_read') {
  d=replace(d,"'memberships',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)","'memberships',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PRESET_ASSIGN'),FALSE)");
  d=replace(d,"RETURN result || jsonb_build_object(","result := result || jsonb_build_object(");
  const pos=d.lastIndexOf('END; $$;');
  d=d.slice(0,pos)+`-- Presentation rights derive from effective authority, never a preset name or email.
  IF NOT global_users AND NOT COALESCE(private.admin_039b_presets(),FALSE)
    AND NOT COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE) THEN
    result:=result||jsonb_build_object('capabilities','[]'::JSONB,'overrides','[]'::JSONB,
      'presets',COALESCE((SELECT jsonb_agg(p-'capabilities'-'bridge'-'recipients') FROM jsonb_array_elements(result->'presets') p
        WHERE p->>'scope'='ORGANIZATION' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(p->'capabilities') c(code)
          WHERE NOT COALESCE(private.can_operate_mica_org(p_org,c.code),FALSE))),'[]'::JSONB),
      'rights',(result->'rights')||jsonb_build_object('operational_admin',TRUE,'presets',FALSE,'assignments',FALSE));
  END IF;
  RETURN result;
`+d.slice(pos);
 }
 f.installed=d;
}
const platform=['ORGANIZATION_CREATE','ORGANIZATION_UPDATE','GLOBAL_CATALOG_VIEW','GLOBAL_CATALOG_MANAGE','CATALOG_ASSIGN_ANY_ORG','RATE_MANAGE_ANY_ORG','DATA_RESTORE_ANY_ORG','REPORT_COMPARE_SCOPED_ORGS','REPORT_CONSOLIDATED_SCOPED_ORGS'];
const bridge=MICA_PERMISSION_CATALOG.filter(c=>c.scope==='ORGANIZATION'&&c.status!=='PROPOSED'&&c.code!=='ORG_MEMBER_PERMISSION_MANAGE').map(c=>c.code);
if(!bridge.includes('ORG_MEMBER_PRESET_ASSIGN'))bridge.push('ORG_MEMBER_PRESET_ASSIGN');
const array=xs=>'ARRAY['+xs.map(q).join(',')+']::TEXT[]';
const dependencies=[['039b_operational_access_and_ux.sql','private.provision_039b_scopes',''],
 ['039b_operational_access_and_ux.sql','private.trigger_039b_scopes',''],
 ['039b_operational_access_and_ux.sql','private.admin_038_authorize','uuid,text,text'],
 ['037_platform_tenant_operation.sql','private.can_operate_mica_org','uuid,text']].map(([file,name,args])=>{
 const body=read('sql/'+file).slice(read('sql/'+file).indexOf('FUNCTION '+name+'(')).match(/AS \$\$([\s\S]*?)\$\$/)[1].trim();
 return {signature:name+'('+args+')',hash:createHash('md5').update(body).digest('hex')};
});
const guards=[...functions,...dependencies].map(f=>'('+q(f.signature)+','+q(f.hash)+')').join(',\n');
// Read-only baseline of legacy/null-scope templates and all their grant rows.
const legacySnapshot=`jsonb_build_object(
 'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
 'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
 'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL))`;
const grantGuards=`NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_role_template_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()'))
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_platform_role_org_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()'))`;
const up=`-- MICA ourzapkjykzlwsjunzmd. 039g revision part 2: operational administration.
-- PREPARED ONLY. First review readonly preflight and fill exact UUID snapshots in the manifest.
-- Apply 039g then 039h as one reviewed release. Never deploy only the first part for Marianela.
BEGIN;
LOCK TABLE public.eco_user_platform_role,public.eco_user_profiles,public.eco_role_templates,
 public.eco_role_template_capabilities,public.eco_platform_role_org_capabilities,
 public.eco_user_platform_capability_overrides,private.eco_platform_org_overrides,
 private.eco_platform_org_scopes,public.eco_capabilities,public.eco_organization_members,
 public.eco_membership_capability_overrides,public.eco_member_capability_overrides IN ACCESS EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
DECLARE v_row RECORD; target UUID:=${manifest.user_profile_id?q(manifest.user_profile_id)+'::UUID':'NULL::UUID'};
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.migration_039g_create') IS NULL THEN RAISE EXCEPTION '039g required, postgres only'; END IF;
 IF to_regclass('private.migration_039h_state') IS NOT NULL THEN RAISE EXCEPTION '039h already installed'; END IF;
 -- NULL scope is legacy and deliberately ignored. Other mismatches require explicit review.
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities source_grant
   JOIN public.eco_role_templates source_template ON source_template.id=source_grant.role_template_id
   JOIN public.eco_capabilities source_capability ON source_capability.id=source_grant.capability_id
   WHERE source_capability.code='ORG_MEMBER_PERMISSION_MANAGE' AND source_template.scope IS NOT NULL
    AND (source_template.scope<>'ORGANIZATION' OR source_capability.scope<>'ORGANIZATION'))
  OR EXISTS(SELECT 1 FROM public.eco_platform_role_org_capabilities source_grant
   JOIN public.eco_role_templates source_template ON source_template.id=source_grant.role_template_id
   JOIN public.eco_capabilities source_capability ON source_capability.id=source_grant.capability_id
   WHERE source_capability.code='ORG_MEMBER_PERMISSION_MANAGE' AND source_template.scope IS NOT NULL
    AND (source_template.scope<>'PLATFORM' OR source_capability.scope<>'ORGANIZATION')) THEN
  RAISE EXCEPTION 'Unexpected non-legacy propagation scope/table'; END IF;
 IF ${grantGuards} THEN RAISE EXCEPTION '036 grant guards must remain active'; END IF;
 IF target IS NULL OR ${json(manifest.platform_assignment)} IS NULL OR ${json(manifest.profile)} IS NULL THEN
  RAISE EXCEPTION 'Review readonly preflight; fill exact target manifest and regenerate before UP'; END IF;
 IF (SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=target) IS DISTINCT FROM ${json(manifest.platform_assignment)}
  OR (SELECT to_jsonb(p) FROM public.eco_user_profiles p WHERE id=target) IS DISTINCT FROM ${json(manifest.profile)} THEN
  RAISE EXCEPTION 'Target identity/assignment drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
    JOIN public.eco_user_profiles p ON p.id=a.user_profile_id WHERE p.id=target AND p.is_active AND a.is_active AND t.is_active AND t.code='ACCOUNTING_SUPERADMIN')
  OR EXISTS(SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=target)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=target)
  OR EXISTS(SELECT 1 FROM private.eco_platform_org_overrides WHERE user_profile_id=target) THEN
  RAISE EXCEPTION 'Target incompatible or has overrides requiring explicit review'; END IF;
 -- Reviewed identities/state, not a blanket acceptance of arbitrary tenant memberships.
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=target)<>3
  OR EXISTS(SELECT 1 FROM jsonb_to_recordset(${json(reviewedMemberships)})
     AS expected_member(id UUID,organization_id UUID,preset_code TEXT,is_active BOOLEAN)
    WHERE NOT EXISTS(SELECT 1 FROM public.eco_organization_members member_row
      JOIN public.eco_role_templates tenant_preset ON tenant_preset.id=member_row.role_template_id
      WHERE member_row.id=expected_member.id AND member_row.user_profile_id=target
       AND member_row.organization_id=expected_member.organization_id AND member_row.is_active=expected_member.is_active
       AND tenant_preset.code=expected_member.preset_code AND tenant_preset.scope='ORGANIZATION' AND tenant_preset.is_active)) THEN
  RAISE EXCEPTION 'Reviewed membership identity/organization/preset/state drift'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides override_row JOIN public.eco_organization_members member_row
    ON member_row.id=override_row.membership_id WHERE member_row.user_profile_id=target)
  OR EXISTS(SELECT 1 FROM public.eco_member_capability_overrides legacy_override,
    LATERAL jsonb_each_text(to_jsonb(legacy_override)) legacy_field
    WHERE legacy_field.value=target::TEXT OR legacy_field.value IN(SELECT id::TEXT FROM public.eco_organization_members WHERE user_profile_id=target)) THEN
  RAISE EXCEPTION 'Unreviewed membership overrides'; END IF;
 IF (SELECT count(*) FROM private.eco_platform_org_scopes WHERE user_profile_id=target)<>7
  OR (SELECT count(*) FROM private.eco_platform_org_scopes WHERE user_profile_id=target AND is_active)<>7 THEN
  RAISE EXCEPTION 'Expected seven active explicit scopes'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_organizations o WHERE o.is_active AND NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes s
   WHERE s.user_profile_id=target AND s.organization_id=o.id AND s.is_active)) THEN RAISE EXCEPTION 'Target missing active explicit scopes'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORG_MEMBER_PRESET_ASSIGN')
  OR EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code='ADMINISTRACION_OPERATIVA_MICA') THEN RAISE EXCEPTION '039h seed collision'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
   WHERE t.code='ACCOUNTING_SUPERADMIN' AND a.is_active AND a.user_profile_id<>target)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members m JOIN public.eco_role_templates t ON t.id=m.role_template_id
   WHERE t.code='ACCOUNTING_SUPERADMIN' AND m.is_active) THEN RAISE EXCEPTION 'Accounting has other active recipients'; END IF;
 FOR v_row IN SELECT * FROM (VALUES ${guards}) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_row.signature) AND prosecdef AND pg_get_userbyid(proowner)='postgres'
   AND proconfig=ARRAY['search_path=""']::TEXT[] AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v_row.hash) THEN
   RAISE EXCEPTION '039h function drift: %',v_row.signature; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id
   JOIN public.eco_role_templates t ON t.id=a.role_template_id WHERE t.code='VEGEN_PLATFORM_ADMIN' AND a.is_active AND t.is_active) THEN
  RAISE EXCEPTION 'Root must retain VEGEN_PLATFORM_ADMIN'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgname IN('provision_039b_org','provision_039b_role','provision_039b_template')
    AND tgenabled='O' AND tgfoid=to_regprocedure('private.trigger_039b_scopes()'))<>3 THEN RAISE EXCEPTION 'Explicit scope triggers missing'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039h_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed TEXT,owner_name TEXT,acl JSONB);
CREATE TABLE private.migration_039h_state(id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id), target UUID NOT NULL,
 assignment JSONB NOT NULL,installed_assignment JSONB,scopes JSONB NOT NULL,root_state JSONB NOT NULL,
 preset UUID,capability UUID,installed_preset JSONB,installed_capability JSONB,grants JSONB,bridge JSONB,compat_grants JSONB,
 historical_preset JSONB,historical_installed JSONB,historical_grants JSONB,historical_bridge JSONB,
 memberships_before JSONB,memberships_installed JSONB,legacy_before JSONB);
ALTER TABLE private.migration_039h_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.migration_039h_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039h_functions,private.migration_039h_state FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039h_functions SELECT signature,pg_get_functiondef(p.oid),NULL,pg_get_userbyid(p.proowner),to_jsonb(p.proacl)
 FROM (VALUES ${guards}) x(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(signature);
INSERT INTO private.migration_039h_state(target,assignment,scopes,root_state)
 SELECT a.user_profile_id,to_jsonb(a),COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY organization_id) FROM private.eco_platform_org_scopes s WHERE s.user_profile_id=a.user_profile_id),'[]'),
 (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(r)) FROM private.eco_platform_owner o
  JOIN public.eco_user_profiles p ON p.id=o.user_profile_id JOIN public.eco_user_platform_role r ON r.user_profile_id=o.user_profile_id)
 FROM public.eco_user_platform_role a WHERE a.user_profile_id=${manifest.user_profile_id?q(manifest.user_profile_id)+'::UUID':'NULL::UUID'};
UPDATE private.migration_039h_state b SET
 legacy_before=${legacySnapshot},
 memberships_before=(SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY id),'[]') FROM public.eco_organization_members member_row WHERE user_profile_id=b.target),
 historical_preset=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.assignment->>'role_template_id')::UUID),
 historical_grants=(SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID),
 historical_bridge=(SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID);
${functions.map(f=>f.installed).join('\n\n')}
DO $seed$
DECLARE cap UUID; tpl UUID; b RECORD;
BEGIN
 SELECT * INTO STRICT b FROM private.migration_039h_state;
 INSERT INTO public.eco_capabilities(code,description,scope,delegation_class,is_active)
 VALUES('ORG_MEMBER_PRESET_ASSIGN','Asignar un preset tenant existente, sin editar permisos','ORGANIZATION','ORGANIZATION_DELEGABLE',TRUE) RETURNING id INTO cap;
 INSERT INTO public.eco_role_templates(code,name,scope,is_system,is_active)
 VALUES('ADMINISTRACION_OPERATIVA_MICA','Administración operativa MICA','PLATFORM',FALSE,TRUE) RETURNING id INTO tpl;
 INSERT INTO private.eco_mica_presets VALUES(tpl,NULL);
 INSERT INTO private.eco_mica_all_org_presets VALUES(tpl);
 INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
 SELECT tpl,id FROM public.eco_capabilities WHERE code=ANY(${array(platform)}) AND is_active AND scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE';
 IF (SELECT count(*) FROM public.eco_role_template_capabilities WHERE role_template_id=tpl)<>${platform.length} THEN RAISE EXCEPTION 'Platform seed incomplete'; END IF;
 INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
 SELECT tpl,id FROM public.eco_capabilities WHERE code=ANY(${array(bridge)}) AND is_active AND scope='ORGANIZATION';
 IF (SELECT count(*) FROM public.eco_platform_role_org_capabilities WHERE role_template_id=tpl)<>${bridge.length} THEN RAISE EXCEPTION 'Bridge seed incomplete'; END IF;
 -- Preserve existing tenant managers and root after separating assignment from permission editing.
 INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
 SELECT g.role_template_id,cap FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
 JOIN public.eco_role_templates source_template ON source_template.id=g.role_template_id
 WHERE c.code='ORG_MEMBER_PERMISSION_MANAGE' AND c.scope='ORGANIZATION' AND source_template.scope='ORGANIZATION'
  AND g.role_template_id<>(b.assignment->>'role_template_id')::UUID;
 INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
 SELECT g.role_template_id,cap FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
 JOIN public.eco_role_templates source_template ON source_template.id=g.role_template_id
 WHERE c.code='ORG_MEMBER_PERMISSION_MANAGE' AND c.scope='ORGANIZATION' AND source_template.scope='PLATFORM'
  AND g.role_template_id<>(b.assignment->>'role_template_id')::UUID;
 -- Preserve historical rows and presets; normalize only the three reviewed active flags.
 UPDATE public.eco_organization_members SET is_active=FALSE WHERE user_profile_id=b.target
  AND id IN(SELECT (saved_member->>'id')::UUID FROM jsonb_array_elements(b.memberships_before) saved_member);
 UPDATE public.eco_user_platform_role SET role_template_id=tpl WHERE user_profile_id=b.target;
 -- Deprecate only after reassignment; preserve the historical preset and every grant row.
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=(b.assignment->>'role_template_id')::UUID AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=(b.assignment->>'role_template_id')::UUID AND is_active) THEN
  RAISE EXCEPTION 'Cannot deprecate accounting with active recipients'; END IF;
 UPDATE public.eco_role_templates SET is_active=FALSE WHERE id=(b.assignment->>'role_template_id')::UUID;
 UPDATE private.migration_039h_state SET preset=tpl,capability=cap,
 memberships_installed=(SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=b.target),
 historical_installed=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.assignment->>'role_template_id')::UUID),
 installed_assignment=(SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=b.target),
 installed_preset=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=tpl),
 installed_capability=(SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE id=cap),
 grants=(SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_role_template_capabilities g WHERE role_template_id=tpl),
 bridge=(SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=tpl),
 compat_grants=(SELECT jsonb_build_object('tenant',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_role_template_capabilities g WHERE capability_id=cap),'[]'),
 'platform',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_platform_role_org_capabilities g WHERE capability_id=cap),'[]')));
 IF b.scopes IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY organization_id),'[]') FROM private.eco_platform_org_scopes s WHERE user_profile_id=b.target) THEN RAISE EXCEPTION 'Existing scopes changed'; END IF;
 IF b.legacy_before IS DISTINCT FROM ${legacySnapshot} THEN RAISE EXCEPTION 'Legacy templates or grants changed'; END IF;
 IF ${grantGuards} THEN RAISE EXCEPTION '036 grant guards must remain active'; END IF;
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=b.target)<>3
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=b.target AND is_active)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(b.memberships_before) saved_member WHERE NOT EXISTS(
    SELECT 1 FROM public.eco_organization_members member_row WHERE member_row.id=(saved_member->>'id')::UUID
     AND member_row.user_profile_id=b.target AND member_row.organization_id=(saved_member->>'organization_id')::UUID
     AND member_row.role_template_id=(saved_member->>'role_template_id')::UUID)) THEN
  RAISE EXCEPTION 'Membership normalization changed identity or left active tenants'; END IF;
 IF b.historical_grants IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID)
  OR b.historical_bridge IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID) THEN
  RAISE EXCEPTION 'Historical accounting grants changed'; END IF;
 IF b.root_state IS DISTINCT FROM (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(r)) FROM private.eco_platform_owner o
 JOIN public.eco_user_profiles p ON p.id=o.user_profile_id JOIN public.eco_user_platform_role r ON r.user_profile_id=o.user_profile_id) THEN RAISE EXCEPTION 'Root changed'; END IF;
END; $seed$;
UPDATE private.migration_039h_functions SET installed=pg_get_functiondef(to_regprocedure(signature));
COMMIT;
`;
const atomic=`-- MICA ourzapkjykzlwsjunzmd. Prepared revision 039g + 039h, ONE transaction.
-- Generated offline. Review both readonly preflights and complete the target manifest first.
BEGIN;
${read('sql/039g_delegate_organization_create.sql').replace(/^BEGIN;\n/m,'').replace(/COMMIT;\s*$/,'')}
${up.replace(/^BEGIN;\n/m,'').replace(/COMMIT;\s*$/,'')}
COMMIT;
`;
const inner=sql=>sql.replace(/^BEGIN;\n/m,'').replace(/(?:COMMIT|ROLLBACK);\s*$/,'');
const roundtrip=`-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY, NEVER EXECUTED BY THE AGENT.
-- Run manually BEFORE release: the reviewed mixed platform + three active tenant assignments
-- are the BEFORE fixture. Execute the actual generated UP, operational harness, and both DOWNs.
-- All effects, including those of the fixture operations, are rolled back.
BEGIN;
CREATE TEMP TABLE test_039h_before ON COMMIT DROP AS
SELECT profile_row.id AS target,
 ${legacySnapshot} AS legacy_before,
 (SELECT to_jsonb(assignment_row) FROM public.eco_user_platform_role assignment_row WHERE user_profile_id=profile_row.id) AS assignment,
 (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=profile_row.id) AS memberships,
 (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=profile_row.id) AS scopes,
 (SELECT to_jsonb(preset_row) FROM public.eco_role_templates preset_row WHERE code='ACCOUNTING_SUPERADMIN') AS historical_preset,
 (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_role_template_capabilities grant_row
   JOIN public.eco_role_templates preset_row ON preset_row.id=grant_row.role_template_id WHERE preset_row.code='ACCOUNTING_SUPERADMIN') AS grants,
 (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities grant_row
   JOIN public.eco_role_templates preset_row ON preset_row.id=grant_row.role_template_id WHERE preset_row.code='ACCOUNTING_SUPERADMIN') AS bridge,
 (SELECT jsonb_object_agg(signature,pg_get_functiondef(to_regprocedure(signature))) FROM (VALUES ${guards}) checked_function(signature,hash)) AS definitions
FROM public.eco_user_profiles profile_row WHERE id=${q(manifest.user_profile_id)}::UUID;
DO $before_fixture$
BEGIN
 IF (SELECT count(*) FROM test_039h_before)<>1 OR EXISTS(SELECT 1 FROM test_039h_before
   WHERE jsonb_array_length(memberships) IS DISTINCT FROM 3 OR jsonb_array_length(scopes) IS DISTINCT FROM 7
    OR NOT (assignment->>'is_active')::BOOLEAN
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(memberships) reviewed_member WHERE NOT (reviewed_member->>'is_active')::BOOLEAN)) THEN
  RAISE EXCEPTION 'Expected mixed platform and active historical tenant BEFORE fixture'; END IF;
END; $before_fixture$;
${inner(atomic)}
SAVEPOINT operational_checks;
${inner(read('tests/db/039h_operational_administration.sql'))}
ROLLBACK TO SAVEPOINT operational_checks;
${inner(read('sql/039h_operational_administration_down.sql'))}
${inner(read('sql/039g_delegate_organization_create_down.sql'))}
DO $after_down$
DECLARE v_before RECORD;
BEGIN
 SELECT * INTO STRICT v_before FROM test_039h_before;
 IF v_before.legacy_before IS DISTINCT FROM ${legacySnapshot} THEN RAISE EXCEPTION 'Roundtrip changed legacy templates or grants'; END IF;
 IF v_before.memberships IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=v_before.target)
  OR v_before.scopes IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=v_before.target)
  OR v_before.assignment IS DISTINCT FROM (SELECT to_jsonb(assignment_row) FROM public.eco_user_platform_role assignment_row WHERE user_profile_id=v_before.target)
  OR v_before.historical_preset IS DISTINCT FROM (SELECT to_jsonb(preset_row) FROM public.eco_role_templates preset_row WHERE code='ACCOUNTING_SUPERADMIN')
  OR v_before.grants IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_role_template_capabilities grant_row WHERE role_template_id=(v_before.historical_preset->>'id')::UUID)
  OR v_before.bridge IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities grant_row WHERE role_template_id=(v_before.historical_preset->>'id')::UUID)
  OR EXISTS(SELECT 1 FROM jsonb_each_text(v_before.definitions) checked_definition WHERE pg_get_functiondef(to_regprocedure(checked_definition.key)) IS DISTINCT FROM checked_definition.value) THEN
  RAISE EXCEPTION 'Roundtrip did not restore exact memberships/scopes/assignment/preset/grants/functions'; END IF;
END; $after_down$;
ROLLBACK;
`;
for(const [path,value] of [['sql/039h_operational_administration.sql',up],['sql/039g_revised_release.sql',atomic],
 ['tests/db/039h_membership_roundtrip.sql',roundtrip]]) {
 if(process.argv.includes('--check')) {
  if(read(path)!==value) throw Error('Generated SQL is stale: '+path);
 } else fs.writeFileSync(path,value);
}
console.log('039h UP '+(process.argv.includes('--check')?'matches':'prepared offline')+'. Target manifest '+(manifest.user_profile_id?'populated':'requires readonly preflight'));
