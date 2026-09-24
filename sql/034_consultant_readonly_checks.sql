-- Read-only post-check after 034. No impersonation or state changes.
SELECT t.id, t.code, t.scope, t.is_active, b.previous_scope, b.was_active,
       b.existed_activity_grant, b.existed_category_grant,
       b.tenant_admin_state = (SELECT COALESCE(jsonb_agg(to_jsonb(a) ORDER BY a.id), '[]'::JSONB)
         FROM public.eco_role_templates a WHERE a.code = 'TENANT_ADMIN') AS tenant_admin_unchanged
FROM public.eco_role_templates t
LEFT JOIN private.migration_034_consultant_backup b ON b.template_id = t.id
WHERE t.code = 'CONSULTANT';

SELECT p.id AS profile_id, p.auth_user_id, o.name, p.is_active AS profile_active,
       m.is_active AS membership_active, t.code AS template, t.scope,
       t.is_active AS template_active, c.code AS capability, c.is_active AS capability_active,
       g.capability_id IS NOT NULL AS template_grant, ov.effect AS membership_override
FROM public.eco_user_profiles p
JOIN public.eco_organization_members m ON m.user_profile_id = p.id AND m.organization_id = p.organization_id
JOIN public.eco_organizations o ON o.id = m.organization_id
JOIN public.eco_role_templates t ON t.id = m.role_template_id
CROSS JOIN public.eco_capabilities c
LEFT JOIN public.eco_role_template_capabilities g ON g.role_template_id = t.id AND g.capability_id = c.id
LEFT JOIN public.eco_membership_capability_overrides ov ON ov.membership_id = m.id AND ov.capability_id = c.id
WHERE p.id IN ('6562ac9c-87b3-4886-a535-2d2e812a44b3', '20f07e8e-4713-4884-bdbc-0a56e8da372e', '06d75e90-28b3-4a10-ad5b-a6c5a1f4c16d')
  AND c.code IN ('ORG_VIEW', 'CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE')
ORDER BY o.name, c.code;

-- Both result sets below must be empty.
SELECT r.* FROM public.eco_user_platform_role r
JOIN public.eco_role_templates t ON t.id = r.role_template_id
WHERE t.code = 'CONSULTANT';
SELECT c.code, c.scope FROM public.eco_role_template_capabilities g
JOIN public.eco_role_templates t ON t.id = g.role_template_id
JOIN public.eco_capabilities c ON c.id = g.capability_id
WHERE t.code = 'CONSULTANT' AND c.scope IS DISTINCT FROM 'ORGANIZATION';

-- Run the following SELECTs in EACH actual authenticated user's session.
-- SQL Editor as postgres without a JWT does not represent those callers.
-- SELECT private.org_id() AS organization_id, private.can_org(private.org_id(), 'ORG_VIEW') AS org_view,
--   private.can_org(private.org_id(), 'CATALOG_ACTIVITY_MANAGE') AS activity_manage,
--   private.can_org(private.org_id(), 'CATALOG_CATEGORY_MANAGE') AS category_manage;
-- SELECT * FROM public.get_my_effective_capabilities(private.org_id());
