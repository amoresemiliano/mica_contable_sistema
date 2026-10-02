-- Stop frontend writes first. Restore prior functions/policies/ACL.
-- Remove only defaults and capabilities created by 033; never cascade later configuration.
BEGIN;
DO $restore$
DECLARE
  b RECORD;
  a RECORD;
  v_role TEXT;
  v_object_type TEXT;
  v_current_acl ACLITEM[];
BEGIN
  FOR b IN SELECT * FROM private.migration_033_backup ORDER BY seq LOOP
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
DELETE FROM public.eco_role_template_capabilities g
USING private.migration_033_default_grants b
WHERE g.role_template_id = b.role_template_id AND g.capability_id = b.capability_id
  AND b.existed_before = FALSE;
-- Lock created capabilities before checking references, preventing new FK references
-- from racing the delete. Any later custom grant/override aborts this entire rollback.
DO $capabilities$
DECLARE
  v_fk RECORD;
  v_join TEXT;
  v_referenced BOOLEAN;
BEGIN
  PERFORM c.id FROM public.eco_capabilities c
    JOIN private.migration_033_created_capabilities b ON b.capability_id = c.id
    FOR UPDATE OF c;
  FOR v_fk IN SELECT oid, conname, conrelid, conkey, confkey
    FROM pg_constraint WHERE contype = 'f' AND confrelid = 'public.eco_capabilities'::regclass LOOP
    SELECT string_agg(format('r.%I = c.%I', src.attname, dst.attname), ' AND ' ORDER BY k.i)
      INTO v_join
    FROM generate_subscripts(v_fk.conkey, 1) AS k(i)
    JOIN pg_attribute src ON src.attrelid = v_fk.conrelid AND src.attnum = v_fk.conkey[k.i]
    JOIN pg_attribute dst ON dst.attrelid = 'public.eco_capabilities'::regclass AND dst.attnum = v_fk.confkey[k.i];
    EXECUTE format(
      'SELECT EXISTS (SELECT 1 FROM %s r JOIN public.eco_capabilities c ON %s JOIN private.migration_033_created_capabilities b ON b.capability_id = c.id)',
      v_fk.conrelid::regclass, v_join) INTO v_referenced;
    IF v_referenced THEN
      RAISE EXCEPTION 'Rollback blocked: capability created by 033 has references through % on %',
        v_fk.conname, v_fk.conrelid::regclass;
    END IF;
  END LOOP;
  DELETE FROM public.eco_capabilities c
  USING private.migration_033_created_capabilities b
  WHERE c.id = b.capability_id;
END;
$capabilities$;
DROP TABLE private.migration_033_created_capabilities;
-- Clear consumed snapshots so a later re-application captures a fresh baseline.
DROP TABLE private.migration_033_default_grants;
DROP TABLE private.migration_033_backup;
COMMIT;
