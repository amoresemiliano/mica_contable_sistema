-- Coordinated rollback: stop clients/writes, run as the migration owner,
-- deploy the pre-030 frontend, then reopen. Do not run concurrently with 030 UI.
-- Keeps business rows and is_assigned. Archives the exact two-flag state.
-- Legacy code only understands is_active: withdrawn rows are projected inactive.
-- Before a future forward migration, reconcile this archive with any legacy
-- writes. Do NOT rerun 030 blindly or discard the archive/retained column.
BEGIN;
LOCK TABLE public.eco_org_economic_activities, public.eco_org_tax_categories
  IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
  IF to_regclass('private.migration_030_backup') IS NULL THEN
    RAISE EXCEPTION 'Missing pre-030 metadata backup: rollback aborted';
  END IF;
END;
$$;

-- CREATE TABLE without IF NOT EXISTS prevents overwriting an earlier archive.
CREATE TABLE private.migration_030_assignment_state AS
SELECT 'activity'::TEXT AS kind, organization_id, activity_id AS item_id,
       is_assigned, is_active, updated_at
FROM public.eco_org_economic_activities
UNION ALL
SELECT 'category', organization_id, category_id, is_assigned, is_active, updated_at
FROM public.eco_org_tax_categories;
REVOKE ALL ON TABLE private.migration_030_assignment_state FROM PUBLIC, anon, authenticated;

UPDATE public.eco_org_economic_activities SET is_active = FALSE WHERE NOT is_assigned;
UPDATE public.eco_org_tax_categories SET is_active = FALSE WHERE NOT is_assigned;

DO $restore$
DECLARE
  b RECORD;
  a RECORD;
  v_role TEXT;
  v_object_type TEXT;
  v_current_acl ACLITEM[];
BEGIN
  FOR b IN SELECT * FROM private.migration_030_backup ORDER BY seq LOOP
    IF b.kind = 'policy' THEN
      EXECUTE 'DROP POLICY IF EXISTS ' || b.object_name;
      IF b.definition IS NOT NULL THEN EXECUTE b.definition; END IF;
      CONTINUE;
    END IF;
    IF b.kind = 'function' THEN
      IF b.definition IS NULL THEN
        EXECUTE 'DROP FUNCTION IF EXISTS ' || b.object_name;
        CONTINUE;
      END IF;
      EXECUTE b.definition;
      EXECUTE format('ALTER FUNCTION %s OWNER TO %I', b.object_name, b.owner_name);
      v_object_type := 'FUNCTION';
      SELECT COALESCE(proacl, acldefault('f', proowner)) INTO v_current_acl
      FROM pg_proc WHERE oid = b.object_name::regprocedure;
    ELSE
      v_object_type := 'TABLE';
      SELECT COALESCE(relacl, acldefault('r', relowner)) INTO v_current_acl
      FROM pg_class WHERE oid = b.object_name::regclass;
    END IF;
    -- Restore effective grants and grant options, including preexisting roles.
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(v_current_acl) LOOP
      v_role := CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON %s %s FROM %s', v_object_type, b.object_name, v_role);
    END LOOP;
    FOR a IN SELECT * FROM jsonb_to_recordset(COALESCE(b.acl, '[]'::JSONB))
      AS x(role TEXT, privilege TEXT, grantable BOOLEAN) LOOP
      v_role := CASE WHEN a.role = 'PUBLIC' THEN 'PUBLIC' ELSE quote_ident(a.role) END;
      EXECUTE format('GRANT %s ON %s %s TO %s%s', a.privilege, v_object_type,
        b.object_name, v_role, CASE WHEN a.grantable THEN ' WITH GRANT OPTION' ELSE '' END);
    END LOOP;
  END LOOP;
END;
$restore$;
COMMIT;
