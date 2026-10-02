-- MICA canonical project: ourzapkjykzlwsjunzmd. READ ONLY. Prepared, NOT executed.
-- Existing capability adoption requires copying its complete row into 039b_live_adoption_manifest.json
-- only after reviewing identity, scope, delegation class, active state and all historical grants below.
-- Regenerate artifacts afterward. NULL in that manifest expects ABSENCE; it never silently adopts.
SELECT current_database(),current_user;
SELECT wanted.code,to_jsonb(c) AS exact_adoption_snapshot
FROM unnest(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[]) wanted(code)
LEFT JOIN public.eco_capabilities c ON c.code=wanted.code ORDER BY wanted.code;

SELECT p.oid::regprocedure::TEXT AS signature,pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef,p.proconfig,p.proacl,
  md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS body_md5,
  pg_get_functiondef(p.oid) AS definition
FROM pg_proc p WHERE p.oid IN (SELECT to_regprocedure(x) FROM unnest(ARRAY['private.mica_capability_allowed(text,text)','private.admin_038_authorize(uuid,text,text)','private.admin_038_target(uuid)','private.admin_038_cap(text,text,uuid)','public.mica_admin_apply(text,jsonb)','public.mica_admin_read(uuid,text)','private.require_039_import(text,text)','public.restore_financial_movement(uuid)','public.restore_normalized_record(uuid)']::TEXT[]) x)
ORDER BY signature;

-- Includes every historic restore grant/override and references to promoted capabilities.
SELECT c.code,'template' AS source,to_jsonb(g) AS grant_row,to_jsonb(t) AS preset
FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_role_templates t ON t.id=g.role_template_id WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[])
UNION ALL SELECT c.code,'bridge',to_jsonb(g),to_jsonb(t)
FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_role_templates t ON t.id=g.role_template_id WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[])
UNION ALL SELECT c.code,'membership_override',to_jsonb(g),to_jsonb(m)
FROM public.eco_membership_capability_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id
JOIN public.eco_organization_members m ON m.id=g.membership_id WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[])
UNION ALL SELECT c.code,'platform_override',to_jsonb(g),NULL::JSONB
FROM public.eco_user_platform_capability_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[])
UNION ALL SELECT c.code,'platform_org_override',to_jsonb(g),NULL::JSONB
FROM private.eco_platform_org_overrides g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','RECORD_RESTORE']::TEXT[])
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
