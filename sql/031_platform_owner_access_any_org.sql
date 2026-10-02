-- Normalize the confirmed owner preset only; keep can_platform strict.
BEGIN;
CREATE TABLE IF NOT EXISTS private.migration_031_preset_backup (
  template_id UUID PRIMARY KEY,
  was_active BOOLEAN NOT NULL,
  previous_template_scope TEXT,
  existed_before BOOLEAN NOT NULL,
  existing_grants UUID[] NOT NULL
);
REVOKE ALL ON TABLE private.migration_031_preset_backup FROM PUBLIC, anon, authenticated;
DO $$
DECLARE
  v_template public.eco_role_templates%ROWTYPE;
  v_code TEXT;
  v_cap UUID;
BEGIN
  SELECT * INTO STRICT v_template FROM public.eco_role_templates
  WHERE code = 'VEGEN_PLATFORM_ADMIN' FOR UPDATE;
  IF v_template.is_active IS DISTINCT FROM TRUE THEN RAISE EXCEPTION 'Owner preset is inactive'; END IF;
  IF v_template.scope IS NOT NULL AND v_template.scope <> 'PLATFORM' THEN
    RAISE EXCEPTION 'Owner preset scope must be NULL or PLATFORM';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_organization_members WHERE role_template_id = v_template.id) THEN
    RAISE EXCEPTION 'Owner preset is used by organization memberships';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
    JOIN public.eco_capabilities c ON c.id = g.capability_id
    WHERE g.role_template_id = v_template.id AND c.scope IS DISTINCT FROM 'PLATFORM') THEN
    RAISE EXCEPTION 'Owner preset contains non-PLATFORM grants';
  END IF;
  INSERT INTO private.migration_031_preset_backup(template_id, was_active, previous_template_scope, existed_before, existing_grants)
  SELECT v_template.id, v_template.is_active, v_template.scope,
    EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
      JOIN public.eco_capabilities c ON c.id = g.capability_id
      WHERE g.role_template_id = v_template.id AND c.code = 'ACCESS_ANY_ORG'),
    ARRAY(SELECT capability_id FROM public.eco_role_template_capabilities WHERE role_template_id = v_template.id)
  ON CONFLICT DO NOTHING;

  IF v_template.scope IS NULL THEN
    UPDATE public.eco_role_templates SET scope = 'PLATFORM' WHERE id = v_template.id;
  END IF;
  FOREACH v_code IN ARRAY ARRAY['ACCESS_ANY_ORG'] LOOP
    SELECT id INTO STRICT v_cap FROM public.eco_capabilities
    WHERE code = v_code AND scope = 'PLATFORM' AND is_active = TRUE;
    INSERT INTO public.eco_role_template_capabilities(role_template_id, capability_id)
    VALUES (v_template.id, v_cap) ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;
COMMIT;
