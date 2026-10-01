-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restores the defective bulk definition active at 039e.
-- Refuses later definition/owner/ACL drift. Does not run the 039e rollback.
BEGIN;
DO $restore$
DECLARE r RECORD; p RECORD;
BEGIN
 IF to_regclass('private.migration_039f_bulk_audit') IS NULL THEN RAISE EXCEPTION '039f not installed'; END IF;
 SELECT * INTO STRICT r FROM private.migration_039f_bulk_audit
  WHERE signature='public.bulk_update_record_classification(text,date,date,uuid,uuid)';
 SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(r.signature);
 IF NOT FOUND THEN RAISE EXCEPTION 'Bulk classification function missing'; END IF;
 IF pg_get_functiondef(p.oid) IS DISTINCT FROM r.installed_definition
  OR p.prosrc IS DISTINCT FROM $expected039f$
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
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION');
  END IF;

  RETURN v_rows_affected;
END;
$expected039f$
  OR p.proowner IS DISTINCT FROM r.owner_oid OR p.proacl IS DISTINCT FROM r.acl THEN
  RAISE EXCEPTION '039f rollback: later definition/owner/ACL drift'; END IF;
 EXECUTE r.definition;
 IF pg_get_functiondef(p.oid) IS DISTINCT FROM r.definition
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid=p.oid
   AND (proowner IS DISTINCT FROM r.owner_oid OR proacl IS DISTINCT FROM r.acl)) THEN
  RAISE EXCEPTION '039f rollback: exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039f_bulk_audit;
COMMIT;
