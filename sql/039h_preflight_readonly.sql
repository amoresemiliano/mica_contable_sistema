-- MICA ourzapkjykzlwsjunzmd. READ ONLY. Run together with 039g_preflight_readonly.sql.
-- Historic recipients classified by source table/scope. NULL scope is excluded, never normalized.
SELECT source_rows.source_table,source_template.id,source_template.code,source_template.scope AS template_scope,
 source_capability.scope AS capability_scope,
 CASE WHEN source_template.scope IS NULL THEN 'IGNORE_LEGACY_NULL'
  WHEN source_template.scope<>source_rows.expected_scope OR source_capability.scope<>'ORGANIZATION' THEN 'ABORT_SCOPE_MISMATCH'
  WHEN source_template.code='ACCOUNTING_SUPERADMIN' THEN 'PRESERVE_HISTORY_DEPRECATE'
  ELSE 'PROPAGATE' END AS propagation
FROM (
 SELECT 'eco_role_template_capabilities' AS source_table,'ORGANIZATION' AS expected_scope,role_template_id,capability_id
 FROM public.eco_role_template_capabilities
 UNION ALL SELECT 'eco_platform_role_org_capabilities','PLATFORM',role_template_id,capability_id
 FROM public.eco_platform_role_org_capabilities
) source_rows JOIN public.eco_role_templates source_template ON source_template.id=source_rows.role_template_id
JOIN public.eco_capabilities source_capability ON source_capability.id=source_rows.capability_id
WHERE source_capability.code='ORG_MEMBER_PERMISSION_MANAGE' ORDER BY source_rows.source_table,source_template.code;
-- Copy the exact reviewed row below into 039h_live_target_manifest.json; regenerate UP offline.
-- An absent profile or unexpected assignment/override blocks the release. Never infer authority from email.
-- Membership IDs reported LIVE; organization IDs also match the historical 020/035a contract.
SELECT to_jsonb(member_row) AS exact_membership_snapshot,org_row.name,tenant_preset.code AS preset_code,
 (SELECT COALESCE(jsonb_agg(to_jsonb(override_row)),'[]') FROM public.eco_membership_capability_overrides override_row
   WHERE override_row.membership_id=member_row.id) AS membership_overrides
FROM public.eco_organization_members member_row JOIN public.eco_organizations org_row ON org_row.id=member_row.organization_id
JOIN public.eco_role_templates tenant_preset ON tenant_preset.id=member_row.role_template_id
WHERE member_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02' ORDER BY member_row.id;
SELECT to_jsonb(legacy_override) AS legacy_override FROM public.eco_member_capability_overrides legacy_override
WHERE EXISTS(SELECT 1 FROM jsonb_each_text(to_jsonb(legacy_override)) legacy_field
 WHERE legacy_field.value='f922be9a-449d-417f-8003-2143fcbeef02' OR legacy_field.value IN(
 SELECT id::TEXT FROM public.eco_organization_members WHERE user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'));
SELECT jsonb_build_object('user_profile_id',p.id,'platform_assignment',to_jsonb(a),'profile',to_jsonb(p)) AS target_manifest
FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
LEFT JOIN public.eco_user_platform_role a ON a.user_profile_id=p.id
WHERE lower(u.email)='drcmarianela@gmail.com';
SELECT t.code,t.is_active,c.code AS capability,c.delegation_class
FROM public.eco_role_templates t LEFT JOIN public.eco_role_template_capabilities g ON g.role_template_id=t.id
LEFT JOIN public.eco_capabilities c ON c.id=g.capability_id
WHERE t.code IN('ACCOUNTING_SUPERADMIN','ADMINISTRACION_OPERATIVA_MICA','VEGEN_PLATFORM_ADMIN') ORDER BY t.code,c.code;
SELECT to_jsonb(c) AS capability FROM public.eco_capabilities c WHERE code IN('ORG_MEMBER_PRESET_ASSIGN','ORG_MEMBER_PERMISSION_MANAGE');
-- The historical preset may be deactivated only when the reviewed target is its sole active recipient.
SELECT t.code,to_jsonb(t) AS historical_preset,
 (SELECT COALESCE(jsonb_agg(to_jsonb(a)),'[]') FROM public.eco_user_platform_role a WHERE a.role_template_id=t.id AND a.is_active) AS active_platform_recipients,
 (SELECT COALESCE(jsonb_agg(to_jsonb(m)),'[]') FROM public.eco_organization_members m WHERE m.role_template_id=t.id AND m.is_active) AS active_tenant_recipients,
 (SELECT COALESCE(jsonb_agg(to_jsonb(g)),'[]') FROM public.eco_role_template_capabilities g WHERE g.role_template_id=t.id) AS exact_grants,
 (SELECT COALESCE(jsonb_agg(to_jsonb(g)),'[]') FROM public.eco_platform_role_org_capabilities g WHERE g.role_template_id=t.id) AS exact_bridge
FROM public.eco_role_templates t WHERE t.code='ACCOUNTING_SUPERADMIN';
SELECT p.oid::regprocedure AS signature,pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,p.proacl,
 md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS body_md5,pg_get_functiondef(p.oid) AS definition
FROM pg_proc p WHERE p.oid IN(to_regprocedure('public.mica_admin_apply(text,jsonb)'),to_regprocedure('public.mica_admin_read(uuid,text)'),
 to_regprocedure('public.mica_invitation(text,uuid,jsonb)'),to_regprocedure('private.mica_capability_allowed(text,text)'),
 to_regprocedure('private.provision_039b_scopes()'),to_regprocedure('private.trigger_039b_scopes()'),
 to_regprocedure('private.admin_038_authorize(uuid,text,text)'),to_regprocedure('private.can_operate_mica_org(uuid,text)'));
SELECT tgrelid::regclass,tgname,tgenabled,pg_get_triggerdef(oid) AS definition
FROM pg_trigger WHERE tgname LIKE 'provision_039b_%' OR tgname LIKE 'guard_036_%';
SELECT to_jsonb(o) AS structural_owner,to_jsonb(r) AS root_assignment,t.code
FROM private.eco_platform_owner o JOIN public.eco_user_platform_role r ON r.user_profile_id=o.user_profile_id
JOIN public.eco_role_templates t ON t.id=r.role_template_id;
