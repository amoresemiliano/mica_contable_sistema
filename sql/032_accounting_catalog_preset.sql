-- Preset grants only. Does not change capability evaluation or template scope.
BEGIN;
CREATE TABLE IF NOT EXISTS private.migration_032_preset_backup (
  template_id UUID PRIMARY KEY,
  was_active BOOLEAN NOT NULL,
  existing_grants UUID[] NOT NULL
);
REVOKE ALL ON TABLE private.migration_032_preset_backup FROM PUBLIC, anon, authenticated;
DO $$
DECLARE
  v_template public.eco_role_templates%ROWTYPE;
  v_code TEXT;
  v_cap UUID;
BEGIN
  SELECT * INTO STRICT v_template FROM public.eco_role_templates
  WHERE code = 'ACCOUNTING_SUPERADMIN' FOR UPDATE;

  INSERT INTO private.migration_032_preset_backup(template_id, was_active, existing_grants)
  SELECT v_template.id, v_template.is_active,
    ARRAY(SELECT capability_id FROM public.eco_role_template_capabilities WHERE role_template_id = v_template.id)
  ON CONFLICT DO NOTHING;
  UPDATE public.eco_role_templates SET is_active = TRUE WHERE id = v_template.id;
  FOREACH v_code IN ARRAY ARRAY['GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG'] LOOP
    SELECT id INTO STRICT v_cap FROM public.eco_capabilities
    WHERE code = v_code AND scope = 'PLATFORM' AND is_active = TRUE;
    INSERT INTO public.eco_role_template_capabilities(role_template_id, capability_id)
    VALUES (v_template.id, v_cap) ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;
COMMIT;
