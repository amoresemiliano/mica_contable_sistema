-- Coordinated rollback; preserve grants that predated this migration.
BEGIN;
DO $$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_032_preset_backup') IS NULL THEN RETURN; END IF;
  FOR b IN SELECT * FROM private.migration_032_preset_backup LOOP
    PERFORM 1 FROM public.eco_role_templates WHERE id = b.template_id FOR UPDATE;
    DELETE FROM public.eco_role_template_capabilities g
    USING public.eco_capabilities c
    WHERE g.role_template_id = b.template_id AND c.id = g.capability_id
      AND c.code IN ('GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG')
      AND NOT (g.capability_id = ANY(b.existing_grants));
    UPDATE public.eco_role_templates SET is_active = b.was_active WHERE id = b.template_id;
  END LOOP;
  DELETE FROM private.migration_032_preset_backup;
END;
$$;
COMMIT;
