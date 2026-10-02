-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY: human execution AFTER 039e.
-- Isolated fixtures, real RPC writes and paginated readback; all changes rolled back.
BEGIN;
DO $test$
DECLARE
  v_root UUID; v_auth UUID; v_org UUID; v_other_org UUID;
  v_category UUID:=gen_random_uuid(); v_activity UUID:=gen_random_uuid();
  v_envelope JSONB; v_result JSONB; v_read JSONB; v_record UUID; v_movement UUID;
  v_marker TEXT:=gen_random_uuid()::TEXT; v_cuit TEXT:='20222222224'; v_count INT;
BEGIN
  IF to_regclass('private.migration_039e_functions') IS NULL THEN RAISE EXCEPTION 'Apply 039e first'; END IF;
  SELECT user_profile_id,auth_user_id INTO STRICT v_root,v_auth FROM private.eco_platform_owner;
  PERFORM set_config('request.jwt.claim.sub',v_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_auth,'role','authenticated')::TEXT,TRUE);
  SET LOCAL ROLE authenticated;
  v_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039e fixture '||v_marker));
  v_other_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039e other '||v_marker));
  PERFORM public.switch_superadmin_org_context(v_org);
  v_envelope:=public.create_import('ARCA_RECIBIDOS','COMPRA');
  v_result:=public.persist_import_batch((v_envelope->>'import_id')::UUID,
    jsonb_build_object('original_name','039e.csv','storage_path',(v_envelope->>'storage_prefix')||'/039e.csv',
      'mime_type','text/csv','size_bytes',1,'sha256_hash',md5(v_marker)||md5(v_marker)),
    '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","cuit":"20222222224","tipo_cbte":"001","pdv":"00001","nroDesde":"123","moneda":"PES","total":121,"netoGravado":100,"totalIva":21}}]');
  IF (v_result->>'accepted_rows')::INT IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Fiscal fixture failed'; END IF;
  v_envelope:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
  v_result:=public.persist_financial_movements_batch((v_envelope->>'import_id')::UUID,
    jsonb_build_object('original_name','039e-bank.csv','storage_path',(v_envelope->>'storage_prefix')||'/039e-bank.csv',
      'mime_type','text/csv','size_bytes',1,'sha256_hash',md5(v_marker||'bank')||md5(v_marker||'bank')),
    '[{"sourceRowNumber":1,"rawRow":[],"errors":[],"warnings":[],"normalizedData":{"fecha":"2026-09-01","monto":25,"tipo":"CREDITO","referencia":"039e","descripcion":"fixture"}}]');
  IF (v_result->>'accepted_rows')::INT IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'Bank fixture failed'; END IF;
  RESET ROLE;
  SELECT id INTO STRICT v_record FROM public.eco_normalized_records WHERE organization_id=v_org;
  SELECT id INTO STRICT v_movement FROM public.eco_financial_movements WHERE organization_id=v_org;
  INSERT INTO public.eco_tax_categories(id,name,category_type) VALUES(v_category,'039e '||v_marker,'EXPENSE');
  INSERT INTO public.eco_economic_activities(id,name) VALUES(v_activity,'039e '||v_marker);
  INSERT INTO public.eco_org_tax_categories(organization_id,category_id,is_assigned,is_active) VALUES(v_org,v_category,TRUE,TRUE);
  INSERT INTO public.eco_org_economic_activities(organization_id,activity_id,is_assigned,is_active) VALUES(v_org,v_activity,TRUE,TRUE);
  -- Deliberately stale payload/legacy state must not win over typed columns.
  UPDATE public.eco_normalized_records SET confirmada=FALSE,
    normalized_payload=normalized_payload||jsonb_build_object('category_id',v_activity,'cuitEmisor',v_cuit) WHERE id=v_record;
  UPDATE public.eco_financial_movements SET normalized_payload=normalized_payload||jsonb_build_object('category_id',v_activity,'confirmada',FALSE) WHERE id=v_movement;
  SET LOCAL ROLE authenticated;
  PERFORM public.update_record_classification(v_record,v_category,NULL);
  PERFORM public.update_record_classification(v_record,v_category,v_activity);
  PERFORM public.update_movement_classification(v_movement,v_category,NULL);
  PERFORM public.update_movement_classification(v_movement,v_category,v_activity);
  SELECT x INTO STRICT v_read FROM public.get_operational_records_page(v_org) x WHERE x->>'id'=v_record::TEXT;
  IF v_read->>'category_id' IS DISTINCT FROM v_category::TEXT OR v_read->>'activity_id' IS DISTINCT FROM v_activity::TEXT
    OR (v_read->>'confirmada')::BOOLEAN IS DISTINCT FROM TRUE OR v_read->>'updated_by' IS DISTINCT FROM v_root::TEXT
    OR v_read->>'updated_at' IS NULL THEN RAISE EXCEPTION 'Record readback differs'; END IF;
  SELECT x INTO STRICT v_read FROM public.get_operational_financials_page(v_org) x WHERE x->>'id'=v_movement::TEXT;
  IF v_read->>'category_id' IS DISTINCT FROM v_category::TEXT OR v_read->>'activity_id' IS DISTINCT FROM v_activity::TEXT
    OR (v_read->>'confirmada')::BOOLEAN IS DISTINCT FROM TRUE OR v_read->>'updated_by' IS DISTINCT FROM v_root::TEXT
    OR v_read->>'updated_at' IS NULL THEN RAISE EXCEPTION 'Movement readback differs'; END IF;
  -- Existing CUIT/date bulk RPC still persists the same columns; no new bulk API.
  v_count:=public.bulk_update_record_classification(v_cuit,'2026-09-01','2026-09-01',NULL,NULL);
  IF v_count<>1 THEN RAISE EXCEPTION 'Bulk fixture not updated'; END IF;
  SELECT x INTO STRICT v_read FROM public.get_operational_records_page(v_org) x WHERE x->>'id'=v_record::TEXT;
  IF v_read->>'category_id' IS NOT NULL OR (v_read->>'confirmada')::BOOLEAN IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION 'Bulk clear not reflected'; END IF;
  PERFORM public.bulk_update_record_classification(v_cuit,'2026-09-01','2026-09-01',v_category,v_activity);
  PERFORM public.switch_superadmin_org_context(v_other_org);
  BEGIN PERFORM public.update_record_classification(v_record,NULL,NULL); RAISE EXCEPTION 'Cross-tenant record fake success';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.update_movement_classification(v_movement,NULL,NULL); RAISE EXCEPTION 'Cross-tenant movement fake success';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_operational_records_page(v_org); RAISE EXCEPTION 'Cross-tenant read allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.switch_superadmin_org_context(v_org);
  RESET ROLE;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT v_root,v_org,id,'DENY' FROM public.eco_capabilities WHERE code='RECORD_CLASSIFY';
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.update_record_classification(v_record,NULL,NULL); RAISE EXCEPTION 'Record DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.update_movement_classification(v_movement,NULL,NULL); RAISE EXCEPTION 'Movement DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.bulk_update_record_classification(v_cuit,'2026-09-01','2026-09-01',NULL,NULL); RAISE EXCEPTION 'Bulk DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Fresh reads after context changes retain classification; Reportes consumes these readers.
  SELECT x INTO STRICT v_read FROM public.get_operational_records_page(v_org) x WHERE x->>'id'=v_record::TEXT;
  IF v_read->>'category_id' IS DISTINCT FROM v_category::TEXT OR v_read->>'activity_id' IS DISTINCT FROM v_activity::TEXT THEN RAISE EXCEPTION 'Record refresh lost classification'; END IF;
  SELECT x INTO STRICT v_read FROM public.get_operational_financials_page(v_org) x WHERE x->>'id'=v_movement::TEXT;
  IF v_read->>'category_id' IS DISTINCT FROM v_category::TEXT OR v_read->>'activity_id' IS DISTINCT FROM v_activity::TEXT THEN RAISE EXCEPTION 'Movement refresh lost classification'; END IF;
  RESET ROLE;
  IF NOT EXISTS(SELECT 1 FROM public.eco_normalized_records WHERE id=v_record AND category_id=v_category AND activity_id=v_activity AND updated_by=v_root AND updated_at IS NOT NULL)
    OR NOT EXISTS(SELECT 1 FROM public.eco_financial_movements WHERE id=v_movement AND category_id=v_category AND activity_id=v_activity AND updated_by=v_root AND updated_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Canonical columns not persisted'; END IF;
END; $test$;
ROLLBACK;
