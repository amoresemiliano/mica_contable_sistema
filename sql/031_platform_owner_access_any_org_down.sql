-- Coordinated rollback; preserve grants that predated this migration.
BEGIN;
DO $$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_031_preset_backup') IS NULL THEN RETURN; END IF;
  FOR b IN SELECT * FROM private.migration_031_preset_backup LOOP
    PERFORM 1 FROM public.eco_role_templates WHERE id = b.template_id FOR UPDATE;
    DELETE FROM public.eco_role_template_capabilities g
    USING public.eco_capabilities c
    WHERE g.role_template_id = b.template_id AND c.id = g.capability_id
      AND c.code IN ('ACCESS_ANY_ORG')
      AND b.existed_before = FALSE
      AND NOT (g.capability_id = ANY(b.existing_grants));
    IF b.previous_template_scope IS NULL THEN
      UPDATE public.eco_role_templates SET scope = b.previous_template_scope WHERE id = b.template_id;
    END IF;
  END LOOP;
  DELETE FROM private.migration_031_preset_backup;
END;
$$;
COMMIT;
