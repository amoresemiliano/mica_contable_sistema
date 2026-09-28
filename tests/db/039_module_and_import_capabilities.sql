-- Supabase SQL Editor, canonical MICA DEV, AFTER manual 039 application.
-- Never executed by Jest. All fixtures, imports, audit rows and contexts roll back.
BEGIN;
DO $test$
DECLARE
  v_root UUID; v_auth UUID; v_org UUID; v_cap UUID; v_import JSONB; v_name TEXT;
  v_staff_auth UUID:=gen_random_uuid(); v_tenant_auth UUID:=gen_random_uuid();
  v_staff UUID; v_tenant UUID; v_preset UUID; v_row RECORD;
BEGIN
  SELECT user_profile_id,auth_user_id INTO STRICT v_root,v_auth FROM private.eco_platform_owner;
  PERFORM set_config('request.jwt.claim.sub',v_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_auth,'role','authenticated')::TEXT,TRUE);
  v_org:=public.mica_admin_apply('organization',jsonb_build_object('name','039 fixture '||v_staff_auth));
  PERFORM public.switch_superadmin_org_context(v_org);
  -- DENY starts each root action test independently of the LIVE root preset.
  INSERT INTO private.eco_platform_org_overrides(user_profile_id,organization_id,capability_id,effect)
  SELECT v_root,v_org,c.id,'DENY' FROM public.eco_capabilities c
  WHERE c.code IN ('RECORD_VIEW','IMPORT_CREATE','BANK_IMPORT','PERCEPTION_IMPORT','PAYROLL_IMPORT','IMPORT_VIEW');
  UPDATE private.eco_platform_org_overrides o SET effect='ALLOW'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org
    AND c.code IN ('RECORD_VIEW','IMPORT_CREATE');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Scope/root bypassed missing BANK_IMPORT';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  UPDATE private.eco_platform_org_overrides o SET effect='ALLOW'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org AND c.code='BANK_IMPORT';
  SET LOCAL ROLE authenticated;
  v_import:=public.create_import('BANK_STATEMENT_BBVA','BANCO');
  IF v_import->>'import_id' IS NULL THEN RAISE EXCEPTION 'Missing import contract'; END IF;
  -- Base + all specialized import grants must never substitute fiscal authority.
  BEGIN
    PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
    RAISE EXCEPTION 'Fiscal received import opened without specific capability';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.create_import('ARCA_EMITIDOS','VENTA');
    RAISE EXCEPTION 'Fiscal issued import opened without specific capability';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  v_name:=v_org::TEXT||'/'||(v_import->>'import_id')||'/bank.xlsx';
  IF NOT public.mica_storage_import_allowed(v_name,'write') THEN RAISE EXCEPTION 'Authorized upload denied'; END IF;
  BEGIN
    PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
    RAISE EXCEPTION 'PAYROLL DENY ignored';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  UPDATE private.eco_platform_org_overrides o SET effect='DENY'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org AND c.code='BANK_IMPORT';
  SET LOCAL ROLE authenticated;
  IF public.mica_storage_import_allowed(v_name,'write') THEN RAISE EXCEPTION 'Revoked bank upload still allowed'; END IF;
  BEGIN
    PERFORM public.persist_financial_movements_batch((v_import->>'import_id')::UUID,'{}','[]');
    RAISE EXCEPTION 'Batch ignored revoked bank capability';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  UPDATE private.eco_platform_org_overrides o SET effect='ALLOW'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org AND c.code='BANK_IMPORT';
  SET LOCAL ROLE authenticated;
  PERFORM public.switch_superadmin_org_context(NULL);
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Platform context imported';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  -- Independent new identities: staff scope without membership and ordinary tenant.
  INSERT INTO auth.users(id,email) VALUES(v_staff_auth,'039-'||v_staff_auth||'@example.invalid'),(v_tenant_auth,'039-'||v_tenant_auth||'@example.invalid');
  SELECT id INTO STRICT v_staff FROM public.eco_user_profiles WHERE auth_user_id=v_staff_auth;
  SELECT id INTO STRICT v_tenant FROM public.eco_user_profiles WHERE auth_user_id=v_tenant_auth;
  v_preset:=public.mica_admin_apply('preset',jsonb_build_object('scope','PLATFORM','name','039 staff','capabilities','[]'::JSONB,
    'bridge',jsonb_build_array('RECORD_VIEW','IMPORT_CREATE','PERCEPTION_IMPORT')));
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',v_staff,'role_template_id',v_preset));
  PERFORM public.mica_admin_apply('scope',jsonb_build_object('user_profile_id',v_staff,'organization_id',v_org));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',v_staff,'is_active',TRUE));
  IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=v_staff) THEN RAISE EXCEPTION 'Artificial membership'; END IF;
  v_preset:=public.mica_admin_apply('preset',jsonb_build_object('scope','ORGANIZATION','name','039 tenant','bridge','[]'::JSONB,
    'capabilities',jsonb_build_array('RECORD_VIEW','IMPORT_CREATE','PERCEPTION_IMPORT')));
  PERFORM public.switch_superadmin_org_context(v_org);
  PERFORM public.mica_admin_apply('membership',jsonb_build_object('user_profile_id',v_tenant,'organization_id',v_org,'role_template_id',v_preset));
  PERFORM public.mica_admin_apply('user',jsonb_build_object('user_profile_id',v_tenant,'is_active',TRUE));
  FOR v_row IN SELECT * FROM (VALUES(v_staff_auth,TRUE),(v_tenant_auth,FALSE)) a(auth_id,is_platform) LOOP
    PERFORM set_config('request.jwt.claim.sub',v_row.auth_id::TEXT,TRUE);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_row.auth_id,'role','authenticated')::TEXT,TRUE);
    SET LOCAL ROLE authenticated;
    IF v_row.is_platform THEN PERFORM public.switch_superadmin_org_context(v_org); END IF;
    PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
    BEGIN
      PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
      RAISE EXCEPTION 'Perception authority granted bank import';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    RESET ROLE;
  END LOOP;
  -- Server-side VIEW revocation: action grants cannot bypass it.
  PERFORM set_config('request.jwt.claim.sub',v_auth::TEXT,TRUE);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_auth,'role','authenticated')::TEXT,TRUE);
  UPDATE private.eco_platform_org_overrides o SET effect='DENY'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org AND c.code='RECORD_VIEW';
  SET LOCAL ROLE authenticated;
  IF EXISTS(SELECT 1 FROM public.get_operational_records_page(v_org,NULL,10)) THEN RAISE EXCEPTION 'Reader bypassed VIEW'; END IF;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Import bypassed VIEW';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  UPDATE private.eco_platform_org_overrides o SET effect='ALLOW'
  FROM public.eco_capabilities c WHERE o.capability_id=c.id AND o.user_profile_id=v_root AND o.organization_id=v_org AND c.code='RECORD_VIEW';
  UPDATE public.eco_organizations SET is_active=FALSE WHERE id=v_org;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
    RAISE EXCEPTION 'Inactive organization imported';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
  FOR v_row IN SELECT signature FROM private.migration_039_functions LOOP
    IF has_function_privilege('anon',v_row.signature,'EXECUTE') OR NOT has_function_privilege('authenticated',v_row.signature,'EXECUTE') THEN
      RAISE EXCEPTION 'Incorrect RPC ACL: %',v_row.signature; END IF;
  END LOOP;
END; $test$;
ROLLBACK;
