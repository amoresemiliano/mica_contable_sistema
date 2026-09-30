-- Historical rollback, aborts on edited seeded rows or later function drift.
-- It never deletes user profiles, memberships, imports or operational data.
BEGIN;
DO $preflight$
DECLARE r RECORD; actual JSONB;
BEGIN
  IF to_regclass('private.migration_039b_functions') IS NULL THEN RAISE EXCEPTION '039b not installed'; END IF;
  FOR r IN SELECT * FROM private.migration_039b_functions LOOP
    IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM r.installed_definition THEN RAISE EXCEPTION 'Later function drift: %',r.signature; END IF;
  END LOOP;
  FOR r IN SELECT * FROM private.migration_039b_rows LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE to_jsonb(t) @> $1',r.relation) INTO actual USING r.key;
    IF actual IS DISTINCT FROM r.installed THEN RAISE EXCEPTION 'Seeded row changed; preserve administrative decision: % %',r.relation,r.key; END IF;
    IF r.relation='public.eco_role_templates' AND (EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=(r.key->>'id')::UUID)
      OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=(r.key->>'id')::UUID)) THEN
      RAISE EXCEPTION 'Seeded preset now assigned; reassign explicitly before rollback'; END IF;
  END LOOP;
END; $preflight$;
DROP TRIGGER provision_039b_org ON public.eco_organizations;
DROP TRIGGER provision_039b_role ON public.eco_user_platform_role;
DROP TRIGGER provision_039b_template ON public.eco_role_templates;
DROP TABLE private.eco_mica_all_org_presets;
DO $restore$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT * FROM private.migration_039b_functions LOOP EXECUTE r.definition; END LOOP;
  FOR r IN SELECT * FROM private.migration_039b_rows ORDER BY seq DESC LOOP
    EXECUTE format('DELETE FROM %s t WHERE to_jsonb(t) @> $1',r.relation) USING r.key;
  END LOOP;
END; $restore$;
DROP FUNCTION private.trigger_039b_scopes();
DROP FUNCTION private.provision_039b_scopes();
DROP FUNCTION private.admin_039b_target_visible(UUID);
DROP FUNCTION private.admin_039b_presets();
DROP FUNCTION private.admin_039b_users();
DROP TABLE private.migration_039b_rows;
DROP TABLE private.migration_039b_functions;
COMMIT;
