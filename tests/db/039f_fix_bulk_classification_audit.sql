-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY: human execution AFTER 039f.
-- Fixtures and RPC calls are transactional; nothing survives ROLLBACK.
BEGIN;
DO $test$
DECLARE
  v_root UUID; v_auth UUID; v_org UUID; v_other UUID; v_target UUID;
  v_category UUID:=gen_random_uuid(); v_activity UUID:=gen_random_uuid();
  v_marker TEXT:=gen_random_uuid()::TEXT; v_envelope JSONB; v_result JSONB;
  v_before JSONB; v_after JSONB; v_audits BIGINT; v_count INT;
BEGIN
  IF to_regclass('private.migration_039f_bulk_audit') IS NULL THEN RAISE EXCEPTION 'Apply 039f first'; END IF;
  SELECT user_profile_id,auth_user_id INTO STRICT v_root,v_auth FROM private.eco_platform_owner;
  PERFORM set_config('request.jwt.claim.sub',v_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_auth,'role','authenticated')::TEXT,TRUE);
  SET LOCAL ROLE authenticated;
  v_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039f fixture '||v_marker));
  v_other:=public.mica_admin_apply('organization',jsonb_build_object('name','039f other '||v_marker));
  FOREACH v_target IN ARRAY ARRAY[v_org,v_other] LOOP
    PERFORM public.switch_superadmin_org_context(v_target);
    v_envelope:=public.create_import('ARCA_RECIBIDOS','COMPRA');
    v_result:=public.persist_import_batch((v_envelope->>'import_id')::UUID,
      jsonb_build_object('original_name','039f.csv','storage_path',(v_envelope->>'storage_prefix')||'/039f.csv',
        'mime_type','text/csv','size_bytes',1,'sha256_hash',md5(v_marker||v_target::TEXT)||md5(v_marker||v_target::TEXT)),
      '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","cuit":"20222222224","tipo_cbte":"001","pdv":"00001","nroDesde":"123","moneda":"PES","total":121,"netoGravado":100,"totalIva":21}},
        {"sourceRowNumber":2,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","cuit":"20222222224","tipo_cbte":"001","pdv":"00001","nroDesde":"124","moneda":"PES","total":121,"netoGravado":100,"totalIva":21}}]');
    IF (v_result->>'accepted_rows')::INT IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'Fiscal fixture failed'; END IF;
  END LOOP;
  RESET ROLE;
  INSERT INTO public.eco_tax_categories(id,name,category_type) VALUES(v_category,'039f '||v_marker,'EXPENSE');
  INSERT INTO public.eco_economic_activities(id,name) VALUES(v_activity,'039f '||v_marker);
  INSERT INTO public.eco_org_tax_categories(organization_id,category_id,is_assigned,is_active) VALUES(v_org,v_category,TRUE,TRUE);
  INSERT INTO public.eco_org_economic_activities(organization_id,activity_id,is_assigned,is_active) VALUES(v_org,v_activity,TRUE,TRUE);
  UPDATE public.eco_normalized_records SET normalized_payload=normalized_payload||jsonb_build_object('cuitEmisor','20222222224')
    WHERE organization_id IN(v_org,v_other);
  SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO v_before FROM public.eco_normalized_records r WHERE organization_id=v_other;
  SELECT count(*) INTO v_audits FROM public.eco_audit_events WHERE organization_id=v_org AND event_type='BULK_UPDATE_RECORDS_CLASSIFICATION';
  SET LOCAL ROLE authenticated;
  PERFORM public.switch_superadmin_org_context(v_org);
  v_count:=public.bulk_update_record_classification('20222222224','2026-09-01','2026-09-01',v_category,v_activity);
  IF v_count IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'Incorrect rows_affected'; END IF;
  RESET ROLE;
  IF (SELECT count(*) FROM public.eco_normalized_records WHERE organization_id=v_org AND category_id=v_category
    AND activity_id=v_activity AND updated_by=v_root AND updated_at IS NOT NULL)<>2 THEN RAISE EXCEPTION 'Classification not persisted'; END IF;
  IF (SELECT count(*) FROM public.eco_audit_events WHERE organization_id=v_org AND event_type='BULK_UPDATE_RECORDS_CLASSIFICATION'
    AND id IS NOT NULL AND created_at IS NOT NULL)<>v_audits+1 THEN RAISE EXCEPTION 'Valid audit event missing'; END IF;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO v_after FROM public.eco_normalized_records r WHERE organization_id=v_other;
  IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'Other organization changed'; END IF;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO v_before FROM public.eco_normalized_records r WHERE organization_id IN(v_org,v_other);
  SET LOCAL ROLE authenticated;
  v_count:=public.bulk_update_record_classification('no-match-039f','2026-09-01','2026-09-01',NULL,NULL);
  IF v_count IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'Zero matches must return zero'; END IF;
  RESET ROLE;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT v_root,v_org,id,'DENY' FROM public.eco_capabilities WHERE code='RECORD_CLASSIFY';
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.bulk_update_record_classification('20222222224','2026-09-01','2026-09-01',NULL,NULL);
    RAISE EXCEPTION 'Bulk DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY id) INTO v_after FROM public.eco_normalized_records r WHERE organization_id IN(v_org,v_other);
  IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'Zero matches or DENY mutated rows'; END IF;
  IF (SELECT count(*) FROM public.eco_audit_events WHERE organization_id=v_org AND event_type='BULK_UPDATE_RECORDS_CLASSIFICATION')<>v_audits+1
    OR EXISTS(SELECT 1 FROM public.eco_audit_events WHERE organization_id=v_other AND event_type='BULK_UPDATE_RECORDS_CLASSIFICATION') THEN
    RAISE EXCEPTION 'Zero matches, DENY or cross-tenant audit contract violated'; END IF;
END; $test$;
ROLLBACK;
