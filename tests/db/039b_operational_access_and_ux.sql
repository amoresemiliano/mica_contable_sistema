-- PREPARED ONLY. Run manually AFTER 039b on ourzapkjykzlwsjunzmd.
-- Creates isolated fixtures and rolls everything back. Never executed by the agent.
BEGIN;
DO $test$
DECLARE root_id UUID; root_auth UUID; staff_auth UUID:=gen_random_uuid(); tenant_auth UUID:=gen_random_uuid();
  staff UUID; tenant UUID; org UUID; orgs UUID[]:=ARRAY[]::UUID[]; org_name TEXT; cap TEXT;
  restore_created JSONB;
  restore_import UUID; restore_file UUID; restore_row UUID; restore_record UUID; restore_movement UUID;
  restore_actor UUID; restore_auth UUID; restore_case TEXT; restore_rpc TEXT;
  accounting UUID; admin_preset UUID; readonly_preset UUID; member UUID; payload JSONB; target UUID;
BEGIN
  IF to_regclass('private.migration_039b_functions') IS NULL THEN RAISE EXCEPTION 'Apply 039b first'; END IF;
  SELECT user_profile_id,auth_user_id INTO STRICT root_id,root_auth FROM private.eco_platform_owner;
  SELECT id INTO STRICT accounting FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN';
  SELECT id INTO STRICT admin_preset FROM public.eco_role_templates WHERE code='MICA_ORG_ADMIN';
  SELECT id INTO STRICT readonly_preset FROM public.eco_role_templates WHERE code='MICA_READ_ONLY';
  PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
  -- Exercise root operational grants in four independent organizations, not LIVE data.
  FOREACH org_name IN ARRAY ARRAY['NORTE','OESTE','SUR','MICA'] LOOP
    SET LOCAL ROLE authenticated;
    org:=public.mica_admin_apply('organization',jsonb_build_object('name','039b '||org_name||' '||staff_auth));
    PERFORM public.switch_superadmin_org_context(org);
    RESET ROLE;
    orgs:=array_append(orgs,org);
    FOR cap IN SELECT code FROM public.eco_capabilities WHERE scope='ORGANIZATION' AND is_active
      AND private.mica_capability_allowed(code,scope) LOOP
      SET LOCAL ROLE authenticated;
      IF NOT public.can_operate_mica_org(org,cap) THEN RAISE EXCEPTION 'Root missing action % in %',cap,org_name; END IF;
      RESET ROLE;
    END LOOP;
    SET LOCAL ROLE authenticated;
    PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
    BEGIN
      PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
      RAISE EXCEPTION 'Fiscal import unexpectedly enabled';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;
  END LOOP;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT root_id,org,id,'DENY' FROM public.eco_capabilities WHERE code='BANK_IMPORT';
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Root bypassed DENY';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=root_id AND organization_id=org;
  INSERT INTO auth.users(id,email) VALUES(staff_auth,'039b-'||staff_auth||'@example.invalid'),
    (tenant_auth,'039b-'||tenant_auth||'@example.invalid');
  SELECT id INTO STRICT staff FROM public.eco_user_profiles WHERE auth_user_id=staff_auth;
  SELECT id INTO STRICT tenant FROM public.eco_user_profiles WHERE auth_user_id=tenant_auth;
  SET LOCAL ROLE authenticated;
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',staff,'role_template_id',accounting));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',staff,'is_active',TRUE));
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=staff) THEN RAISE EXCEPTION 'Artificial membership'; END IF;
  IF EXISTS(SELECT 1 FROM public.eco_organizations o WHERE o.is_active AND NOT EXISTS
    (SELECT 1 FROM private.eco_platform_org_scopes s WHERE s.user_profile_id=staff AND s.organization_id=o.id AND s.is_active)) THEN
    RAISE EXCEPTION 'Accounting missing provisioned scopes'; END IF;
  -- Newly created organizations receive explicit scopes without another login or membership.
  SET LOCAL ROLE authenticated;
  org:=public.mica_admin_apply('organization',jsonb_build_object('name','039b future '||staff_auth));
  RESET ROLE;
  IF NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=staff AND organization_id=org AND is_active) THEN
    RAISE EXCEPTION 'Future organization missing scope'; END IF;
  orgs:=array_append(orgs,org);
  -- Inactive explicit scopes are deliberate revocations, never silently reactivated.
  UPDATE private.eco_platform_org_scopes SET is_active=FALSE WHERE user_profile_id=staff AND organization_id=org;
  UPDATE public.eco_organizations SET is_active=TRUE WHERE id=org;
  IF EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=staff AND organization_id=org AND is_active) THEN
    RAISE EXCEPTION 'Scope revocation overwritten'; END IF;
  UPDATE private.eco_platform_org_scopes SET is_active=TRUE WHERE user_profile_id=staff AND organization_id=org;
  PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
  IF private.can_platform('ACCESS_ANY_ORG') OR private.can_platform('PLATFORM_MANAGE') OR
    private.can_platform('GLOBAL_USER_MANAGE') THEN RAISE EXCEPTION 'Accounting acquired reserved capability'; END IF;
  FOREACH org IN ARRAY orgs LOOP
    SET LOCAL ROLE authenticated;
    PERFORM public.switch_superadmin_org_context(org);
    payload:=public.mica_admin_read(org,'');
    IF NOT (payload->'rights'->>'global_users')::BOOLEAN OR NOT (payload->'rights'->>'global_presets')::BOOLEAN THEN
      RAISE EXCEPTION 'Delegable administration missing from reader'; END IF;
    PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
    RESET ROLE;
    FOR cap IN SELECT code FROM public.eco_capabilities WHERE scope='ORGANIZATION' AND is_active AND private.mica_capability_allowed(code,scope) LOOP
      SET LOCAL ROLE authenticated;
      IF NOT public.can_operate_mica_org(org,cap) THEN RAISE EXCEPTION 'Accounting missing %',cap; END IF;
      RESET ROLE;
    END LOOP;
  END LOOP;
  -- Administration from the accounting session: assign and approve tenant, edit a reusable preset.
  SET LOCAL ROLE authenticated;
  PERFORM public.mica_admin_apply('membership',jsonb_build_object('user_profile_id',tenant,'organization_id',org,'role_template_id',admin_preset));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',tenant,'organization_id',org,'is_active',TRUE));
  target:=public.mica_admin_apply('preset',jsonb_build_object('name','039b review fixture','scope','ORGANIZATION',
    'capabilities',jsonb_build_array('ORG_VIEW','RECORD_VIEW'),'bridge','[]'::JSONB));
  BEGIN
    PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',tenant,'kind','platform','capability','ACCESS_ANY_ORG','effect','ALLOW'));
    RAISE EXCEPTION 'Reserved delegation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',tenant,'kind','platform','capability','DATA_RESTORE_ANY_ORG','effect','ALLOW'));
    RAISE EXCEPTION 'Restore platform capability delegated to tenant';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',root_id,'is_active',FALSE));
    RAISE EXCEPTION 'Root changed by accounting';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  -- DENY defeats seeded bridge grants. IMPORT_VIEW is required at the actual endpoint.
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT staff,org,id,'DENY' FROM public.eco_capabilities WHERE code='IMPORT_VIEW';
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Import ignored IMPORT_VIEW DENY';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
    SELECT staff,org,id,'DENY' FROM public.eco_capabilities WHERE code='RECORD_VIEW';
  SET LOCAL ROLE authenticated;
  IF public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'VIEW DENY ignored'; END IF;
  IF EXISTS(SELECT 1 FROM public.get_operational_records_page(org)) THEN RAISE EXCEPTION 'Reader ignored VIEW DENY'; END IF;
  RESET ROLE;
  -- Ordinary tenant gets importers from a real reusable preset, not role text.
  PERFORM set_config('request.jwt.claim.sub',tenant_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',tenant_auth,'role','authenticated')::TEXT,TRUE);
  SET LOCAL ROLE authenticated;
  PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
  IF public.can_operate_mica_org(org,'RECORD_RESTORE') THEN RAISE EXCEPTION 'New tenant admin received restore'; END IF;
  RESET ROLE;
  SELECT id INTO STRICT member FROM public.eco_organization_members WHERE user_profile_id=tenant AND organization_id=org;
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect)
    SELECT member,id,'DENY' FROM public.eco_capabilities WHERE code='BANK_IMPORT';
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Tenant DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  UPDATE public.eco_organization_members SET role_template_id=readonly_preset WHERE id=member;
  SET LOCAL ROLE authenticated;
  IF NOT public.can_operate_mica_org(org,'RECORD_VIEW') THEN RAISE EXCEPTION 'Readonly cannot view'; END IF;
  BEGIN
    PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
    RAISE EXCEPTION 'Readonly imported';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  -- Preset is a base, not a ceiling: explicit delegable ALLOW expands readonly.
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect)
    SELECT member,id,'ALLOW' FROM public.eco_capabilities WHERE code IN ('IMPORT_CREATE','PERCEPTION_IMPORT');
  SET LOCAL ROLE authenticated;
  PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
  RESET ROLE;
  UPDATE public.eco_membership_capability_overrides SET effect='DENY'
    WHERE membership_id=member AND capability_id=(SELECT id FROM public.eco_capabilities WHERE code='PERCEPTION_IMPORT');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
    RAISE EXCEPTION 'DENY failed after additional ALLOW';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  -- Restore contract: real isolated rows, both actual RPCs, privileged fixture setup only.
  -- Undo earlier deliberate fixture DENYs before testing the independent restore gate.
  DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=staff AND organization_id=org;
  PERFORM set_config('request.jwt.claim.sub',staff_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',staff_auth,'role','authenticated')::TEXT,TRUE);
  SET LOCAL ROLE authenticated;
  -- 039 returns a JSONB envelope; only import_id is a UUID.
  restore_created:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
  restore_import:=(restore_created->>'import_id')::UUID;
  IF restore_import IS NULL THEN
    RAISE EXCEPTION 'create_import returned no import_id for restore fixture'; END IF;
  RESET ROLE;
  INSERT INTO public.eco_source_files(import_id,organization_id,original_name,storage_path,size_bytes,sha256_hash,source_type)
    VALUES(restore_import,org,'039b restore fixture','039b/'||staff_auth,0,staff_auth::TEXT,'BANK_STATEMENT_BBVA') RETURNING id INTO restore_file;
  INSERT INTO public.eco_import_rows(file_id,organization_id,source_row_number,raw_payload,parse_status)
    VALUES(restore_file,org,1,'{}','ACCEPTED') RETURNING id INTO restore_row;
  INSERT INTO public.eco_normalized_records(row_id,organization_id,identity_key,fiscal_fingerprint,normalized_payload,tipo_operacion,status,deleted_at)
    VALUES(restore_row,org,staff_auth::TEXT,staff_auth::TEXT,'{}','COMPRA','ACCEPTED',now()) RETURNING id INTO restore_record;
  INSERT INTO public.eco_financial_movements(organization_id,import_id,row_id,source_type,operation_type,identity_key,financial_fingerprint,normalized_payload,deleted_at)
    VALUES(org,restore_import,restore_row,'BANK_STATEMENT_BBVA','BANCO',staff_auth::TEXT,staff_auth::TEXT,'{}',now()) RETURNING id INTO restore_movement;
  FOREACH restore_actor IN ARRAY ARRAY[root_id,staff] LOOP
    restore_auth:=CASE WHEN restore_actor=root_id THEN root_auth ELSE staff_auth END;
    PERFORM set_config('request.jwt.claim.sub',restore_auth::TEXT,TRUE);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',restore_auth,'role','authenticated')::TEXT,TRUE);
    SET LOCAL ROLE authenticated;
    PERFORM public.switch_superadmin_org_context(org);
    PERFORM public.restore_normalized_record(restore_record);
    PERFORM public.restore_financial_movement(restore_movement);
    RESET ROLE;
    IF NOT EXISTS(SELECT 1 FROM public.eco_normalized_records WHERE id=restore_record AND deleted_at IS NULL AND updated_by=restore_actor)
      OR NOT EXISTS(SELECT 1 FROM public.eco_financial_movements WHERE id=restore_movement AND deleted_at IS NULL AND updated_by=restore_actor) THEN
      RAISE EXCEPTION 'Restore did not update both fixture rows for %',restore_actor; END IF;
    UPDATE public.eco_normalized_records SET deleted_at=now() WHERE id=restore_record;
    UPDATE public.eco_financial_movements SET deleted_at=now() WHERE id=restore_movement;
    FOREACH restore_case IN ARRAY ARRAY['platform_deny','contextual_deny','null_context','inactive_org','outside_scope'] LOOP
      IF restore_case='outside_scope' AND restore_actor=root_id THEN CONTINUE; END IF;
      IF restore_case='platform_deny' THEN
        INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
          SELECT restore_actor,id,'DENY' FROM public.eco_capabilities WHERE code='DATA_RESTORE_ANY_ORG';
      ELSIF restore_case='contextual_deny' THEN
        INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
          SELECT restore_actor,org,id,'DENY' FROM public.eco_capabilities WHERE code='RECORD_RESTORE';
      ELSIF restore_case='null_context' THEN
        UPDATE public.eco_user_active_context SET organization_id=NULL WHERE user_profile_id=restore_actor;
      ELSIF restore_case='inactive_org' THEN
        UPDATE public.eco_organizations SET is_active=FALSE WHERE id=org;
      ELSE UPDATE private.eco_platform_org_scopes SET is_active=FALSE WHERE user_profile_id=restore_actor AND organization_id=org;
      END IF;
      FOREACH restore_rpc IN ARRAY ARRAY['restore_normalized_record','restore_financial_movement'] LOOP
        SET LOCAL ROLE authenticated;
        BEGIN
          EXECUTE format('SELECT public.%I($1)',restore_rpc)
            USING CASE WHEN restore_rpc='restore_normalized_record' THEN restore_record ELSE restore_movement END;
          RAISE EXCEPTION 'Restore bypassed %: %',restore_case,restore_rpc;
        EXCEPTION WHEN insufficient_privilege THEN NULL; END;
        RESET ROLE;
      END LOOP;
      DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=restore_actor
        AND capability_id=(SELECT id FROM public.eco_capabilities WHERE code='DATA_RESTORE_ANY_ORG');
      DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=restore_actor AND organization_id=org
        AND capability_id=(SELECT id FROM public.eco_capabilities WHERE code='RECORD_RESTORE');
      UPDATE public.eco_organizations SET is_active=TRUE WHERE id=org;
      UPDATE private.eco_platform_org_scopes SET is_active=TRUE WHERE user_profile_id=restore_actor AND organization_id=org;
      UPDATE public.eco_user_active_context SET organization_id=org WHERE user_profile_id=restore_actor;
    END LOOP;
    -- A row from another org remains untouched even with full authority in the selected org.
    SET LOCAL ROLE authenticated;
    PERFORM public.switch_superadmin_org_context(orgs[1]);
    PERFORM public.restore_normalized_record(restore_record);
    PERFORM public.restore_financial_movement(restore_movement);
    RESET ROLE;
    IF EXISTS(SELECT 1 FROM public.eco_normalized_records WHERE id=restore_record AND deleted_at IS NULL)
      OR EXISTS(SELECT 1 FROM public.eco_financial_movements WHERE id=restore_movement AND deleted_at IS NULL) THEN
      RAISE EXCEPTION 'Restore crossed tenant context'; END IF;
  END LOOP;
  -- Simulate an existing historic tenant grant without granting any PLATFORM action.
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect)
    SELECT member,id,'ALLOW' FROM public.eco_capabilities WHERE code='RECORD_RESTORE';
  PERFORM set_config('request.jwt.claim.sub',tenant_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',tenant_auth,'role','authenticated')::TEXT,TRUE);
  SET LOCAL ROLE authenticated;
  IF NOT public.can_operate_mica_org(org,'RECORD_RESTORE') THEN RAISE EXCEPTION 'Historic restore fixture has no contextual grant'; END IF;
  RESET ROLE;
  FOREACH restore_rpc IN ARRAY ARRAY['restore_normalized_record','restore_financial_movement'] LOOP
    SET LOCAL ROLE authenticated;
    BEGIN
      EXECUTE format('SELECT public.%I($1)',restore_rpc)
        USING CASE WHEN restore_rpc='restore_normalized_record' THEN restore_record ELSE restore_movement END;
      RAISE EXCEPTION 'Historic tenant restore bypass: %',restore_rpc;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.eco_normalized_records WHERE id=restore_record AND deleted_at IS NULL)
    OR EXISTS(SELECT 1 FROM public.eco_financial_movements WHERE id=restore_movement AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'Denied restore changed fixture rows'; END IF;
END; $test$;
ROLLBACK;
