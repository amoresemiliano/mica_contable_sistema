-- Coordinated rollback: retain all preexisting grants and activation state.
BEGIN;
DO $$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_034_consultant_backup') IS NULL THEN RETURN; END IF;
  FOR b IN SELECT * FROM private.migration_034_consultant_backup LOOP
    PERFORM 1 FROM public.eco_role_templates WHERE id = b.template_id FOR UPDATE;
    DELETE FROM public.eco_role_template_capabilities g
    USING public.eco_capabilities c
    WHERE g.role_template_id = b.template_id AND c.id = g.capability_id
      AND (
        (c.code = 'CATALOG_ACTIVITY_MANAGE' AND b.existed_activity_grant = FALSE)
        OR (c.code = 'CATALOG_CATEGORY_MANAGE' AND b.existed_category_grant = FALSE)
      );
    IF b.previous_scope IS NULL THEN
      UPDATE public.eco_role_templates SET scope = b.previous_scope WHERE id = b.template_id;
    END IF;
  END LOOP;
  DELETE FROM private.migration_034_consultant_backup;
END;
$$;
COMMIT;
