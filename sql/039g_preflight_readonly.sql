-- MICA ourzapkjykzlwsjunzmd. READ ONLY; prepared, NOT executed.
-- Emails identify the requested review subjects only; they never authorize operations.
SELECT current_database(),current_user,
 to_regclass('private.migration_039e_functions') AS phase_039e,
 to_regclass('private.migration_039f_bulk_audit') AS phase_039f,
 to_regclass('private.migration_039g_create') AS phase_039g;
SELECT to_jsonb(c) AS capability,to_jsonb(r) AS structural_registration
FROM public.eco_capabilities c LEFT JOIN private.eco_owner_reserved_capabilities r ON r.capability_id=c.id
WHERE c.scope='PLATFORM' ORDER BY c.code;
SELECT u.email,p.id,p.is_active,a.role_template_id,a.is_active AS assignment_active,t.code,t.is_active AS preset_active,
 EXISTS(SELECT 1 FROM private.eco_platform_owner o WHERE o.user_profile_id=p.id AND o.auth_user_id=u.id) AS structural_owner,
 EXISTS(SELECT 1 FROM private.eco_mica_pending_profiles q WHERE q.user_profile_id=p.id AND q.approved_at IS NULL) AS pending,
 EXISTS(SELECT 1 FROM public.eco_organization_members m WHERE m.user_profile_id=p.id AND m.is_active) AS active_tenant_membership
FROM auth.users u JOIN public.eco_user_profiles p ON p.auth_user_id=u.id
LEFT JOIN public.eco_user_platform_role a ON a.user_profile_id=p.id
LEFT JOIN public.eco_role_templates t ON t.id=a.role_template_id
WHERE lower(u.email) IN('drcmarianela@gmail.com','vegendigital@gmail.com');
-- Must return every active organization with scope_active=true. No missing scope is repaired implicitly.
SELECT o.id,o.name,s.is_active AS scope_active,
 bool_and(COALESCE(s.is_active,FALSE)) OVER() AS all_active_organizations_scoped
FROM public.eco_organizations o
CROSS JOIN (SELECT p.id FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id WHERE lower(u.email)='drcmarianela@gmail.com') actor
LEFT JOIN private.eco_platform_org_scopes s ON s.organization_id=o.id AND s.user_profile_id=actor.id
WHERE o.is_active ORDER BY o.name;
SELECT t.code,c.code AS capability,c.scope,c.delegation_class
FROM public.eco_role_templates t JOIN public.eco_role_template_capabilities g ON g.role_template_id=t.id
JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE t.code='ACCOUNTING_SUPERADMIN'
UNION ALL
SELECT t.code,c.code,c.scope,c.delegation_class FROM public.eco_role_templates t
JOIN public.eco_platform_role_org_capabilities g ON g.role_template_id=t.id
JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE t.code='ACCOUNTING_SUPERADMIN';
SELECT c.code,to_jsonb(v) AS platform_override FROM public.eco_user_platform_capability_overrides v
JOIN public.eco_capabilities c ON c.id=v.capability_id
WHERE v.user_profile_id IN(SELECT p.id FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id WHERE lower(u.email)='drcmarianela@gmail.com');
SELECT c.code,to_jsonb(v) AS organization_override FROM private.eco_platform_org_overrides v
JOIN public.eco_capabilities c ON c.id=v.capability_id
WHERE v.user_profile_id IN(SELECT p.id FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id WHERE lower(u.email)='drcmarianela@gmail.com');
SELECT p.oid::regprocedure AS signature,pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,p.proacl,
 md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS body_md5,pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname='private' AND p.proname IN('guard_036_capability','guard_036_frozen','guard_036_identity','can_platform','admin_038_target','admin_038_cap'))
 OR (n.nspname='public' AND p.proname='mica_admin_apply');
SELECT tgrelid::regclass,tgname,tgenabled,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname LIKE 'guard_036_%';
