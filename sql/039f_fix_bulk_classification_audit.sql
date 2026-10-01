-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; human application after 039e.
-- Audit schema: sql/004_audit.sql (id, organization_id, event_type, created_at).
-- 039e audit sweep: both single-write inserts use valid columns; readers have no audit writes.
-- Bulk body is inherited unchanged from 039; only its invalid audit insert is corrected.
BEGIN;
DO $preflight$
DECLARE p RECORD;
BEGIN
 IF to_regclass('private.migration_039e_functions') IS NULL THEN RAISE EXCEPTION '039e required'; END IF;
 IF to_regclass('private.migration_039f_bulk_audit') IS NOT NULL THEN RAISE EXCEPTION '039f already installed'; END IF;
 SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure('public.bulk_update_record_classification(text,date,date,uuid,uuid)');
 IF NOT FOUND THEN RAISE EXCEPTION 'Bulk classification function missing'; END IF;
 IF pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres' OR NOT p.prosecdef
  OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[]
  OR p.prosrc IS DISTINCT FROM $expected039e$
DECLARE
  v_org_id UUID;

  v_caller_id UUID;
  v_rows_affected INT := 0;
  v_valid BOOLEAN;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_CLASSIFY');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF p_category_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_tax_categories WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_economic_activities WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  WITH updated AS (
    UPDATE public.eco_normalized_records
    SET category_id = p_category_id,
        activity_id = p_activity_id,
        updated_at = now(),
        updated_by = v_caller_id
    WHERE organization_id = v_org_id
      AND deleted_at IS NULL
      AND (normalized_payload->>'cuitEmisor' = p_cuit OR normalized_payload->>'cuitReceptor' = p_cuit)
      AND fecha >= p_date_from
      AND fecha <= p_date_to
    RETURNING id
  )
  SELECT COUNT(*) INTO v_rows_affected FROM updated;

  IF v_rows_affected > 0 THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type, details)
    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION', jsonb_build_object('cuit', p_cuit, 'date_from', p_date_from, 'date_to', p_date_to, 'rows_affected', v_rows_affected));
  END IF;

  RETURN v_rows_affected;
END;
$expected039e$ THEN
  RAISE EXCEPTION '039f preflight: expected exact 039e body, postgres owner, SECURITY DEFINER and empty search_path'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.migration_039_functions
  WHERE signature='public.bulk_update_record_classification(text,date,date,uuid,uuid)'
   AND installed_definition=pg_get_functiondef(p.oid)) THEN
  RAISE EXCEPTION '039f preflight: definition differs from inherited 039 snapshot'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039f_bulk_audit (
 signature TEXT PRIMARY KEY, definition TEXT NOT NULL, installed_definition TEXT,
 owner_oid OID NOT NULL, acl ACLITEM[]
);
ALTER TABLE private.migration_039f_bulk_audit ENABLE ROW LEVEL SECURITY;
DO $backup_acl$
DECLARE a RECORD;
BEGIN
 FOR a IN SELECT DISTINCT x.grantee FROM pg_class c,
  LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) x
  WHERE c.oid='private.migration_039f_bulk_audit'::regclass AND x.grantee<>c.relowner LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.migration_039f_bulk_audit FROM %s',
   CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END);
 END LOOP;
END; $backup_acl$;
INSERT INTO private.migration_039f_bulk_audit(signature,definition,owner_oid,acl)
 SELECT 'public.bulk_update_record_classification(text,date,date,uuid,uuid)',pg_get_functiondef(oid),proowner,proacl
 FROM pg_proc WHERE oid='public.bulk_update_record_classification(text,date,date,uuid,uuid)'::regprocedure;
DO $patch$
DECLARE r RECORD; replacement TEXT;
BEGIN
 SELECT * INTO STRICT r FROM private.migration_039f_bulk_audit;
 replacement:=replace(r.definition,
  $old$INSERT INTO public.eco_audit_events (organization_id, event_type, details)
    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION', jsonb_build_object('cuit', p_cuit, 'date_from', p_date_from, 'date_to', p_date_to, 'rows_affected', v_rows_affected));$old$,
  $new$INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION');$new$);
 -- CREATE OR REPLACE preserves the existing owner and ACL, including grant options.
 EXECUTE replacement;
 IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM replacement
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature)
   AND (proowner IS DISTINCT FROM r.owner_oid OR proacl IS DISTINCT FROM r.acl)) THEN
  RAISE EXCEPTION '039f postflight: definition/owner/ACL mismatch'; END IF;
 UPDATE private.migration_039f_bulk_audit SET installed_definition=replacement;
END; $patch$;
COMMIT;
