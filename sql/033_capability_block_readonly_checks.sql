-- READ ONLY post-check after 031 -> 032 -> 033. No writes or session impersonation.
-- 1. Expect owner PLATFORM/active, accounting PLATFORM/active and its three catalog grants.
-- No grant to ACCESS_ANY_ORG is introduced for accounting by this block.
SELECT t.code, t.scope, t.is_active, c.code AS capability, c.scope AS capability_scope,
       c.is_active AS capability_active
FROM public.eco_role_templates t
LEFT JOIN public.eco_role_template_capabilities g ON g.role_template_id = t.id
LEFT JOIN public.eco_capabilities c ON c.id = g.capability_id
WHERE t.code IN ('VEGEN_PLATFORM_ADMIN', 'ACCOUNTING_SUPERADMIN', 'CONSULTANT', 'TENANT_ADMIN')
ORDER BY t.code, c.code;

-- Expect zero rows: lost owner grants or omitted eligible tenant defaults.
SELECT 'owner_prior_grant_missing' AS issue, t.code AS template, c.code AS capability
FROM private.migration_031_preset_backup b
JOIN public.eco_role_templates t ON t.id = b.template_id
JOIN public.eco_capabilities c ON c.id = ANY(b.existing_grants)
WHERE NOT EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
  WHERE g.role_template_id = b.template_id AND g.capability_id = c.id)
UNION ALL
SELECT 'tenant_default_missing', t.code, c.code
FROM public.eco_role_templates t CROSS JOIN public.eco_capabilities c
WHERE t.code IN ('CONSULTANT', 'TENANT_ADMIN') AND t.scope = 'ORGANIZATION' AND t.is_active IS TRUE
  AND c.code IN ('CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE')
  AND NOT EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
    WHERE g.role_template_id = t.id AND g.capability_id = c.id);

-- 2. Only the two assignment SELECT policies change. Inspect all policies for drift/bypasses.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies WHERE schemaname = 'public' AND tablename IN
 ('eco_organizations', 'eco_org_economic_activities', 'eco_org_tax_categories',
  'eco_economic_activities', 'eco_tax_categories')
ORDER BY tablename, policyname;

-- 3. Public RPCs: SECURITY DEFINER, empty search_path, anon=false, authenticated=true.
SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
 p.prosecdef, p.provolatile, p.proconfig,
 has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
 has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN
 ('get_my_effective_capabilities', 'get_my_catalog_capabilities', 'list_catalog_assignment_targets',
 'list_catalog_assignment_state', 'activate_economic_activity', 'deactivate_economic_activity',
 'activate_tax_category', 'deactivate_tax_category', 'assign_economic_activity_to_org',
 'unassign_economic_activity_from_org', 'assign_tax_category_to_org', 'unassign_tax_category_from_org')
ORDER BY p.proname;

-- 4. Current helpers: can_platform/can_org unchanged, target has only catalog/active-target gates.
SELECT n.nspname AS schema_name, p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private' AND p.proname IN
 ('can_platform', 'can_org', 'authorized_orgs_for_capability', 'catalog_assignment_target');

-- 5. Tenant membership/template/override diagnosis. No attempt to impersonate these users.
SELECT o.name, m.user_profile_id, p.is_active AS profile_active, m.is_active AS membership_active,
       t.code AS template, t.scope, t.is_active AS template_active, c.code AS capability,
       c.is_active AS capability_active, (g.capability_id IS NOT NULL) AS template_grant, ov.effect
FROM public.eco_organization_members m
JOIN public.eco_organizations o ON o.id = m.organization_id
JOIN public.eco_user_profiles p ON p.id = m.user_profile_id
LEFT JOIN public.eco_role_templates t ON t.id = m.role_template_id
CROSS JOIN public.eco_capabilities c
LEFT JOIN public.eco_role_template_capabilities g ON g.role_template_id = t.id AND g.capability_id = c.id
LEFT JOIN public.eco_membership_capability_overrides ov ON ov.membership_id = m.id AND ov.capability_id = c.id
WHERE c.code IN ('ORG_VIEW', 'CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE')
ORDER BY o.name, m.user_profile_id, c.code;

-- 6. Execute these SELECTs with the actual caller's authenticated session/JWT.
-- SQL Editor as postgres normally has auth.uid() NULL; its error is NOT evidence of user denial.
-- Replace NULL with the caller's active organization UUID to include its ORGANIZATION permissions.
-- SELECT * FROM public.get_my_effective_capabilities(NULL);
-- For a caller with CATALOG_ASSIGN_ANY_ORG only:
-- SELECT * FROM public.list_catalog_assignment_targets();
-- SELECT * FROM public.list_catalog_assignment_state('activity');
-- SELECT * FROM public.list_catalog_assignment_state('category');

-- Legacy/indeterminate table retained. Inspect actual consumers without declaring it obsolete.
SELECT n.nspname, p.proname, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
  AND (p.prosrc ILIKE '%eco_member_capability_overrides%'
    OR p.prosrc ILIKE '%eco_membership_capability_overrides%');
