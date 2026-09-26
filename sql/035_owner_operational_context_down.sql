-- Manual rollback only. Restore frontend together with its previous RPC contract.
-- Requires the private baseline captured by 035; never guesses a LIVE definition/ACL.
BEGIN;
DO $restore$
DECLARE
  b RECORD;
  a RECORD;
  v_role TEXT;
  v_executor TEXT := current_user;
  v_pending JSONB;
  v_next JSONB;
  v_progress BOOLEAN;
BEGIN
  IF to_regclass('private.migration_035_backup') IS NULL THEN
    RAISE EXCEPTION '035 down: LIVE backup missing; refusing reconstructed rollback';
  END IF;
  SELECT * INTO STRICT b FROM private.migration_035_backup
    WHERE signature = 'public.switch_superadmin_org_context(uuid)';
  -- Includes the exact LIVE body, UUID -> VOID, SECURITY DEFINER and empty search_path.
  -- The confirmed baseline uses SUPPORT_IMPERSONATE OR ACCESS_ANY_ORG, existence-only
  -- target validation, legacy profile update, canonical upsert and platform audit.
  EXECUTE b.definition;
  EXECUTE format('ALTER FUNCTION %s OWNER TO %I', b.signature, b.owner_name);
  -- Clear only this function's current grants, including grant-option dependencies.
  FOR a IN SELECT DISTINCT x.grantee FROM pg_proc p,
    LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
    WHERE p.oid = b.signature::regprocedure LOOP
    v_role := CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s CASCADE', b.signature, v_role);
  END LOOP;
  -- Rebuild grant chains with their original grantors and grant options.
  v_pending := b.acl;
  WHILE jsonb_array_length(v_pending) > 0 LOOP
    v_next := '[]'::jsonb;
    v_progress := FALSE;
    FOR a IN SELECT value AS entry FROM jsonb_array_elements(v_pending) LOOP
      IF a.entry->>'grantor' = b.owner_name OR
        has_function_privilege(a.entry->>'grantor', b.signature, 'EXECUTE WITH GRANT OPTION') THEN
        EXECUTE format('SET LOCAL ROLE %I', a.entry->>'grantor');
        v_role := CASE WHEN a.entry->>'role' = 'PUBLIC' THEN 'PUBLIC' ELSE quote_ident(a.entry->>'role') END;
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %s%s', b.signature, v_role,
          CASE WHEN (a.entry->>'grantable')::BOOLEAN THEN ' WITH GRANT OPTION' ELSE '' END);
        EXECUTE format('SET LOCAL ROLE %I', v_executor);
        v_progress := TRUE;
      ELSE
        v_next := v_next || jsonb_build_array(a.entry);
      END IF;
    END LOOP;
    IF NOT v_progress THEN RAISE EXCEPTION '035 down: cannot restore original ACL grant chain'; END IF;
    v_pending := v_next;
  END LOOP;
  -- Verify restored effective ACL, including grantor, before dropping any new RPC.
  IF EXISTS (
    (SELECT value FROM jsonb_array_elements(b.acl)
     EXCEPT
     SELECT jsonb_build_object('role', CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
       'grantor', pg_get_userbyid(x.grantor), 'privilege', x.privilege_type, 'grantable', x.is_grantable)
     FROM pg_proc p, LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
     WHERE p.oid = b.signature::regprocedure)
    UNION ALL
    (SELECT jsonb_build_object('role', CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
       'grantor', pg_get_userbyid(x.grantor), 'privilege', x.privilege_type, 'grantable', x.is_grantable)
     FROM pg_proc p, LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
     WHERE p.oid = b.signature::regprocedure
     EXCEPT SELECT value FROM jsonb_array_elements(b.acl))
  ) THEN RAISE EXCEPTION '035 down: restored ACL differs'; END IF;
END;
$restore$;
-- Preflight 035 guarantees these five RPCs did not exist before application.
-- No CASCADE: later dependencies must block rollback instead of being deleted.
DROP FUNCTION public.get_operational_records_page(UUID, UUID, INTEGER);
DROP FUNCTION public.get_operational_financials_page(UUID, UUID, INTEGER);
DROP FUNCTION public.get_operational_snapshot(UUID);
DROP FUNCTION public.get_my_operational_context();
DROP FUNCTION public.list_operational_org_targets();
DROP TABLE private.migration_035_backup;
COMMIT;
