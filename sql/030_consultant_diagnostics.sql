-- Read-only diagnostics. Run as an authorized SQL-editor reader.
-- No provisioning, SET ROLE, set_config or mutations.
SELECT t.id, t.code, t.scope, t.is_active, c.code AS capability,
       c.scope AS capability_scope, c.is_active AS capability_active
FROM public.eco_role_templates t
LEFT JOIN public.eco_role_template_capabilities g ON g.role_template_id = t.id
LEFT JOIN public.eco_capabilities c ON c.id = g.capability_id
WHERE t.code = 'CONSULTANT'
ORDER BY c.code;

-- Evidence for ORG_VIEW (required by the activation RPC), plus settings/catalog
-- permissions for diagnosis only: 030 does not require those additional codes.
WITH evidence AS (
  SELECT o.id AS organization_id, o.name AS organization_name,
    p.id AS profile_id, p.auth_user_id, p.role, p.is_active AS profile_active,
    p.organization_id AS profile_organization_id,
    ctx.organization_id AS active_organization_id,
    m.id AS membership_id, m.is_active AS membership_active,
    t.code AS membership_template, t.is_active AS template_active,
    c.code AS capability, c.is_active AS capability_active,
    ov.effect AS override_effect,
    EXISTS (
      SELECT 1 FROM public.eco_role_template_capabilities g
      WHERE g.role_template_id = t.id AND g.capability_id = c.id
        AND t.is_active AND t.scope = 'ORGANIZATION'
    ) AS template_grant,
    EXISTS (
      SELECT 1 FROM public.eco_user_platform_role pr
      JOIN public.eco_role_templates pt ON pt.id = pr.role_template_id
      JOIN public.eco_platform_role_org_capabilities g ON g.role_template_id = pt.id
      WHERE pr.user_profile_id = p.id AND pr.is_active AND pt.is_active
        AND pt.scope = 'PLATFORM' AND g.capability_id = c.id
    ) AS platform_bridge_grant
  FROM public.eco_organizations o
  JOIN public.eco_organization_members m ON m.organization_id = o.id
  JOIN public.eco_user_profiles p ON p.id = m.user_profile_id
  LEFT JOIN public.eco_role_templates t ON t.id = m.role_template_id
  LEFT JOIN public.eco_user_active_context ctx ON ctx.user_profile_id = p.id
  CROSS JOIN public.eco_capabilities c
  LEFT JOIN public.eco_membership_capability_overrides ov
    ON ov.membership_id = m.id AND ov.capability_id = c.id
  WHERE o.id IN ('1f5d071f-a09e-4825-9f12-88533383599e'::UUID,
                 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID)
    AND c.scope = 'ORGANIZATION'
    AND c.code IN ('ORG_VIEW', 'ORG_SETTINGS_MANAGE', 'CATALOG_ORG_VIEW')
)
SELECT *, profile_active AND membership_active AND capability_active
  AND CASE WHEN override_effect = 'DENY' THEN FALSE
           WHEN override_effect = 'ALLOW' THEN TRUE
           ELSE template_grant OR platform_bridge_grant END AS effective_capability
FROM evidence
ORDER BY organization_name, profile_id, capability;

-- This final SELECT evaluates the actual helper only for the authenticated
-- SQL session. A SQL-editor session without auth.uid() normally returns NULL/false.
SELECT auth.uid() AS caller, private.org_id() AS active_org,
       private.can_org(private.org_id(), 'ORG_VIEW') AS caller_org_view;
