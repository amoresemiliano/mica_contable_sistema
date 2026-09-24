-- Normalize CONSULTANT only. Keep can_org, memberships and overrides unchanged.
BEGIN;
CREATE TABLE IF NOT EXISTS private.migration_034_consultant_backup (
  template_id UUID PRIMARY KEY,
  previous_scope TEXT,
  was_active BOOLEAN NOT NULL,
  existed_activity_grant BOOLEAN NOT NULL,
  existed_category_grant BOOLEAN NOT NULL,
  -- Read-only baseline to verify that TENANT_ADMIN was not changed.
  tenant_admin_state JSONB NOT NULL
);
REVOKE ALL ON TABLE private.migration_034_consultant_backup FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_template public.eco_role_templates%ROWTYPE;
  v_activity UUID;
  v_category UUID;
BEGIN
  -- STRICT rejects both a missing template and multiple matching templates.
  SELECT * INTO STRICT v_template FROM public.eco_role_templates
  WHERE code = 'CONSULTANT' FOR UPDATE;
  IF v_template.is_active IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'CONSULTANT must be active';
  END IF;
  IF v_template.scope IS NOT NULL AND v_template.scope <> 'ORGANIZATION' THEN
    RAISE EXCEPTION 'CONSULTANT scope must be NULL or ORGANIZATION';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id = v_template.id) THEN
    RAISE EXCEPTION 'CONSULTANT is used as a platform role';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.eco_role_template_capabilities g
    LEFT JOIN public.eco_capabilities c ON c.id = g.capability_id
    WHERE g.role_template_id = v_template.id AND c.scope IS DISTINCT FROM 'ORGANIZATION'
  ) THEN
    RAISE EXCEPTION 'CONSULTANT has non-ORGANIZATION grants';
  END IF;
  SELECT id INTO STRICT v_activity FROM public.eco_capabilities
  WHERE code = 'CATALOG_ACTIVITY_MANAGE' AND scope = 'ORGANIZATION' AND is_active IS TRUE;
  SELECT id INTO STRICT v_category FROM public.eco_capabilities
  WHERE code = 'CATALOG_CATEGORY_MANAGE' AND scope = 'ORGANIZATION' AND is_active IS TRUE;

  INSERT INTO private.migration_034_consultant_backup (
    template_id, previous_scope, was_active, existed_activity_grant, existed_category_grant, tenant_admin_state
  )
  SELECT v_template.id, v_template.scope, v_template.is_active,
    EXISTS (SELECT 1 FROM public.eco_role_template_capabilities
      WHERE role_template_id = v_template.id AND capability_id = v_activity),
    EXISTS (SELECT 1 FROM public.eco_role_template_capabilities
      WHERE role_template_id = v_template.id AND capability_id = v_category),
    (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::JSONB)
      FROM public.eco_role_templates t WHERE t.code = 'TENANT_ADMIN')
  ON CONFLICT (template_id) DO NOTHING;

  IF v_template.scope IS NULL THEN
    UPDATE public.eco_role_templates SET scope = 'ORGANIZATION' WHERE id = v_template.id;
  END IF;
  INSERT INTO public.eco_role_template_capabilities(role_template_id, capability_id)
  VALUES (v_template.id, v_activity), (v_template.id, v_category)
  ON CONFLICT DO NOTHING;
END;
$$;
COMMIT;
