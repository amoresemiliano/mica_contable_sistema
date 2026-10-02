-- 039b MICA Contable Argentina / ourzapkjykzlwsjunzmd. PREPARED ONLY.
-- No email/legacy-role authority; data grants remain subordinate to 037 DENY/context.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
  IF to_regclass('private.migration_039b_functions') IS NOT NULL THEN RAISE EXCEPTION '039b already present'; END IF;
  IF to_regclass('private.migration_039_functions') IS NULL THEN RAISE EXCEPTION 'Applied 039 required'; END IF;
  FOR r IN SELECT * FROM (VALUES ('private.mica_capability_allowed(text,text)','aae7df3af4b1674a42f22495097030e7'),
('private.admin_038_authorize(uuid,text,text)','97b909ec8fe5ec13fd6710b0fb8e6520'),
('private.admin_038_target(uuid)','80359e81c6a37691e95a3c9400a1278e'),
('private.admin_038_cap(text,text,uuid)','7cdf262ee4799662e5875c69686aa920'),
('public.mica_admin_apply(text,jsonb)','14ea590d5f6c276b1e094da9fcc69021'),
('public.mica_admin_read(uuid,text)','d097bf71b410c3f5daa45a449cbd6e32'),
('private.require_039_import(text,text)','4997ae332c276418b0a2df735b822298'),
('public.restore_financial_movement(uuid)','55216b62904f97af171f78c3147a490a'),
('public.restore_normalized_record(uuid)','64134c70e927d1c20119a62a447d20a8')) e(signature,hash) LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
      AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
      AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
      RAISE EXCEPTION '039b LIVE definition differs: %',r.signature; END IF;
  END LOOP;
  IF (SELECT count(*) FROM private.eco_platform_owner)<>1 THEN RAISE EXCEPTION 'Structural owner required'; END IF;
  -- BEGIN GENERATED ADOPTION PREFLIGHT
  -- NULL means verified expectation of absence. Existing rows require an exact reviewed LIVE snapshot.
  FOR r IN SELECT * FROM (VALUES
    ('DATA_RESTORE_ANY_ORG','PLATFORM','PLATFORM_DELEGABLE',NULL::JSONB),
    ('MICA_ADMIN_MANAGE','PLATFORM','PLATFORM_DELEGABLE',NULL::JSONB),
    ('PURCHASES_INVOICES_MANAGE','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"270d5828-d17e-48a7-b21a-a880747dfb21","code":"PURCHASES_INVOICES_MANAGE","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"Register and match supplier invoices","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('SUPPLIERS_VIEW','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"50058bd3-8718-4721-a97d-79a0b4456236","code":"SUPPLIERS_VIEW","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"View supplier directory","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('SUPPLIERS_MANAGE','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"6adf675e-cc3c-4b18-a074-572495f48ac7","code":"SUPPLIERS_MANAGE","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"Create and edit supplier profiles","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('SALES_VIEW','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"6012bcd5-8268-40b8-8e29-849623403198","code":"SALES_VIEW","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"View sales overview and dashboards","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('PERSONNEL_EMPLOYEES_MANAGE','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"642cb49c-1b99-4f09-a56d-2f86e1c7b3ac","code":"PERSONNEL_EMPLOYEES_MANAGE","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"Manage staff records and contracts","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('INTEGRATIONS_CONFIG_MANAGE','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"c2159755-beeb-4f22-9584-359956a410c5","code":"INTEGRATIONS_CONFIG_MANAGE","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"Configure POS and accounting integrations","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('INTEGRATIONS_SYNC_TRIGGER','ORGANIZATION','ORGANIZATION_DELEGABLE','{"id":"ccee9aa3-f941-4c92-9e95-fbe4bb38a17c","code":"INTEGRATIONS_SYNC_TRIGGER","scope":"ORGANIZATION","is_active":true,"created_at":"2026-09-15T20:04:40.479794+00:00","description":"Trigger on-demand data synchronizations","delegation_class":"ORGANIZATION_DELEGABLE"}'::JSONB),
    ('MANUAL_MOVEMENT_VIEW','ORGANIZATION','ORGANIZATION_DELEGABLE',NULL::JSONB),
    ('MANUAL_MOVEMENT_CREATE','ORGANIZATION','ORGANIZATION_DELEGABLE',NULL::JSONB),
    ('MANUAL_MOVEMENT_EDIT','ORGANIZATION','ORGANIZATION_DELEGABLE',NULL::JSONB),
    ('MANUAL_MOVEMENT_SOFT_DELETE','ORGANIZATION','ORGANIZATION_DELEGABLE',NULL::JSONB)
  ) x(code,scope,delegation_class,expected) LOOP
    IF r.expected IS NULL THEN
      IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code=r.code) THEN
        RAISE EXCEPTION '039b collision: review LIVE and fill adoption manifest for %',r.code; END IF;
    ELSIF NOT EXISTS(SELECT 1 FROM public.eco_capabilities c WHERE c.code=r.code AND c.scope=r.scope
      AND c.delegation_class=r.delegation_class AND c.is_active AND to_jsonb(c)=r.expected) THEN
      RAISE EXCEPTION '039b exact adoption preflight differs: %',r.code;
    END IF;
  END LOOP;
  -- END GENERATED ADOPTION PREFLIGHT
  IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code=ANY(ARRAY['MICA_ORG_ADMIN','MICA_ACCOUNTANT','MICA_IMPORT_OPERATOR','MICA_READ_ONLY']::TEXT[])) THEN RAISE EXCEPTION 'Tenant preset code collision: review first'; END IF;
  IF EXISTS(SELECT 1 FROM unnest(ARRAY['ORG_VIEW','ORG_SETTINGS_VIEW','ORG_SETTINGS_MANAGE','ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PERMISSION_MANAGE','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','RECORD_CLASSIFY','RECORD_SOFT_DELETE','RECORD_RESTORE','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','ISSUE_RESOLVE','CATALOG_ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','REPORT_VIEW','REPORT_EXPORT','TICKET_CREATE','TICKET_VIEW_ORG','AUDIT_VIEW_ORG','FINANCIAL_ALLOCATION_EDIT','SENSITIVEDATA_BANKING_READ','SENSITIVEDATA_SALARIES_READ','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY']::TEXT[]) c(code) WHERE NOT EXISTS
    (SELECT 1 FROM public.eco_capabilities k WHERE k.code=c.code AND k.scope='ORGANIZATION' AND k.is_active AND k.delegation_class='ORGANIZATION_DELEGABLE')) THEN
    RAISE EXCEPTION 'Approved MICA organization capability contract missing'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039b_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed_definition TEXT);
CREATE TABLE private.migration_039b_rows(seq BIGSERIAL PRIMARY KEY,relation TEXT NOT NULL,key JSONB NOT NULL,installed JSONB NOT NULL);
CREATE TABLE private.eco_mica_all_org_presets(role_template_id UUID PRIMARY KEY REFERENCES public.eco_role_templates(id) ON DELETE RESTRICT);
ALTER TABLE private.migration_039b_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.migration_039b_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_mica_all_org_presets ENABLE ROW LEVEL SECURITY;
INSERT INTO private.migration_039b_functions(signature,definition)
SELECT e.signature,pg_get_functiondef(p.oid) FROM (VALUES ('private.mica_capability_allowed(text,text)','aae7df3af4b1674a42f22495097030e7'),
('private.admin_038_authorize(uuid,text,text)','97b909ec8fe5ec13fd6710b0fb8e6520'),
('private.admin_038_target(uuid)','80359e81c6a37691e95a3c9400a1278e'),
('private.admin_038_cap(text,text,uuid)','7cdf262ee4799662e5875c69686aa920'),
('public.mica_admin_apply(text,jsonb)','14ea590d5f6c276b1e094da9fcc69021'),
('public.mica_admin_read(uuid,text)','d097bf71b410c3f5daa45a449cbd6e32'),
('private.require_039_import(text,text)','4997ae332c276418b0a2df735b822298'),
('public.restore_financial_movement(uuid)','55216b62904f97af171f78c3147a490a'),
('public.restore_normalized_record(uuid)','64134c70e927d1c20119a62a447d20a8')) e(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(e.signature);

CREATE FUNCTION private.admin_039b_users() RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE(private.can_platform('GLOBAL_USER_MANAGE'),FALSE) OR COALESCE(private.can_platform('MICA_ADMIN_MANAGE'),FALSE);
$$;
CREATE FUNCTION private.admin_039b_presets() RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT COALESCE(private.can_platform('PLATFORM_MANAGE'),FALSE) OR COALESCE(private.can_platform('MICA_ADMIN_MANAGE'),FALSE);
$$;
CREATE FUNCTION private.admin_039b_target_visible(p_target UUID) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT private.is_platform_owner() OR (
  NOT EXISTS(SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=p_target)
  AND (NOT COALESCE(private.can_platform('MICA_ADMIN_MANAGE'),FALSE) OR (
    NOT EXISTS(SELECT 1 FROM public.eco_organization_members m WHERE m.user_profile_id=p_target AND NOT private.platform_org_in_scope(m.organization_id))
    AND NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes s WHERE s.user_profile_id=p_target AND s.is_active AND NOT private.platform_org_in_scope(s.organization_id))
  )));
$$;
CREATE OR REPLACE FUNCTION private.mica_capability_allowed(p_code TEXT,p_scope TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM (VALUES
    ('DATA_RESTORE_ANY_ORG','PLATFORM'),
    ('MICA_ADMIN_MANAGE','PLATFORM'),
    ('PLATFORM_MANAGE','PLATFORM'),
    ('GLOBAL_USER_MANAGE','PLATFORM'),
    ('PLAN_MANAGE','PLATFORM'),
    ('ACCESS_ANY_ORG','PLATFORM'),
    ('SUPPORT_IMPERSONATE','PLATFORM'),
    ('HARD_DELETE_EXCEPTIONAL','PLATFORM'),
    ('ORGANIZATION_CREATE','PLATFORM'),
    ('ORGANIZATION_UPDATE','PLATFORM'),
    ('ORGANIZATION_ARCHIVE','PLATFORM'),
    ('PLATFORM_MIGRATIONS_APPLY','PLATFORM'),
    ('PLATFORM_TENANTS_PROVISION','PLATFORM'),
    ('PLATFORM_SYSTEM_MONITOR','PLATFORM'),
    ('GLOBAL_CATALOG_VIEW','PLATFORM'),
    ('GLOBAL_CATALOG_MANAGE','PLATFORM'),
    ('CATALOG_ASSIGN_ANY_ORG','PLATFORM'),
    ('RATE_MANAGE_ANY_ORG','PLATFORM'),
    ('REPORT_COMPARE_SCOPED_ORGS','PLATFORM'),
    ('REPORT_CONSOLIDATED_SCOPED_ORGS','PLATFORM'),
    ('SAAS_ANALYTICS_VIEW','PLATFORM'),
    ('AUDIT_PLATFORM_VIEW','PLATFORM'),
    ('ORG_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_VIEW','ORGANIZATION'),
    ('ORG_MEMBER_INVITE','ORGANIZATION'),
    ('ORG_MEMBER_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_PERMISSION_MANAGE','ORGANIZATION'),
    ('IMPORT_VIEW','ORGANIZATION'),
    ('IMPORT_CREATE','ORGANIZATION'),
    ('IMPORT_RETRY','ORGANIZATION'),
    ('IMPORT_REVIEW','ORGANIZATION'),
    ('RECORD_VIEW','ORGANIZATION'),
    ('RECORD_CLASSIFY','ORGANIZATION'),
    ('RECORD_SOFT_DELETE','ORGANIZATION'),
    ('RECORD_RESTORE','ORGANIZATION'),
    ('PERCEPTION_IMPORT','ORGANIZATION'),
    ('BANK_IMPORT','ORGANIZATION'),
    ('PAYROLL_IMPORT','ORGANIZATION'),
    ('ISSUE_RESOLVE','ORGANIZATION'),
    ('CATALOG_ORG_VIEW','ORGANIZATION'),
    ('CATALOG_ACTIVITY_MANAGE','ORGANIZATION'),
    ('CATALOG_CATEGORY_MANAGE','ORGANIZATION'),
    ('REPORT_VIEW','ORGANIZATION'),
    ('REPORT_EXPORT','ORGANIZATION'),
    ('TICKET_CREATE','ORGANIZATION'),
    ('TICKET_VIEW_ORG','ORGANIZATION'),
    ('AUDIT_VIEW_ORG','ORGANIZATION'),
    ('FINANCIAL_ALLOCATION_EDIT','ORGANIZATION'),
    ('SENSITIVEDATA_BANKING_READ','ORGANIZATION'),
    ('SENSITIVEDATA_SALARIES_READ','ORGANIZATION'),
    ('DOCUMENTS_UPLOAD','ORGANIZATION'),
    ('DOCUMENTS_OCR_PROCESS','ORGANIZATION'),
    ('DOCUMENTS_OCR_VERIFY','ORGANIZATION'),
    ('PURCHASES_INVOICES_MANAGE','ORGANIZATION'),
    ('SUPPLIERS_VIEW','ORGANIZATION'),
    ('SUPPLIERS_MANAGE','ORGANIZATION'),
    ('SALES_VIEW','ORGANIZATION'),
    ('PERSONNEL_EMPLOYEES_MANAGE','ORGANIZATION'),
    ('INTEGRATIONS_CONFIG_MANAGE','ORGANIZATION'),
    ('INTEGRATIONS_SYNC_TRIGGER','ORGANIZATION'),
    ('MANUAL_MOVEMENT_VIEW','ORGANIZATION'),
    ('MANUAL_MOVEMENT_CREATE','ORGANIZATION'),
    ('MANUAL_MOVEMENT_EDIT','ORGANIZATION'),
    ('MANUAL_MOVEMENT_SOFT_DELETE','ORGANIZATION')
  ) allowed(code,scope) WHERE code=p_code AND scope=p_scope);
$$;

CREATE OR REPLACE FUNCTION private.admin_038_authorize(p_org UUID,p_platform TEXT,p_tenant TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.admin_038_actor();
  -- Global identity/preset administration is a PLATFORM action, not an ACCESS_ANY_ORG bypass.
  IF p_org IS NULL THEN
    IF NOT COALESCE((private.can_platform(p_platform) OR (p_platform IN ('GLOBAL_USER_MANAGE','PLATFORM_MANAGE') AND private.can_platform('MICA_ADMIN_MANAGE'))),FALSE) THEN
      RAISE EXCEPTION 'Platform administration denied' USING ERRCODE='42501'; END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=private.admin_038_actor() AND organization_id=p_org)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org AND is_active)
    OR NOT (COALESCE(private.admin_039b_users(),FALSE)
      OR COALESCE(private.can_operate_mica_org(p_org,p_tenant),FALSE)) THEN
    RAISE EXCEPTION 'Tenant administration denied: confirmed context and action required' USING ERRCODE='42501';
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION private.admin_038_target(p_profile UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NOT private.admin_039b_target_visible(p_profile) THEN RAISE EXCEPTION 'Target outside MICA administrative scope' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM public.eco_user_profiles WHERE id=p_profile FOR UPDATE;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=p_profile) THEN
    RAISE EXCEPTION 'Missing or protected target' USING ERRCODE='42501'; END IF;
  IF p_profile=private.admin_038_actor() THEN
    RAISE EXCEPTION 'Self administration is not allowed' USING ERRCODE='42501'; END IF;
END; $$;

CREATE OR REPLACE FUNCTION private.admin_038_cap(p_code TEXT,p_scope TEXT,p_org UUID)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v UUID;
BEGIN
  SELECT id INTO v FROM public.eco_capabilities WHERE code=p_code AND scope=p_scope AND is_active
    AND delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(code,scope);
  IF v IS NULL THEN RAISE EXCEPTION 'Capability not administrable in MICA' USING ERRCODE='42501'; END IF;
  IF p_code='RECORD_RESTORE' AND p_org IS NOT NULL THEN
    RAISE EXCEPTION 'Restore is delegated through MICA platform scopes, not tenant memberships' USING ERRCODE='42501'; END IF;
  -- A tenant permission manager may never delegate beyond their own effective authority.
  IF p_org IS NOT NULL AND NOT COALESCE(private.admin_039b_users(),FALSE)
    AND NOT COALESCE(private.can_operate_mica_org(p_org,p_code),FALSE) THEN
    RAISE EXCEPTION 'Cannot delegate an action you do not possess' USING ERRCODE='42501'; END IF;
  IF NOT private.is_platform_owner() AND private.can_platform('MICA_ADMIN_MANAGE') THEN
    IF (p_scope='PLATFORM' AND NOT COALESCE(private.can_platform(p_code),FALSE))
      OR (p_scope='ORGANIZATION' AND NOT COALESCE(private.can_operate_mica_org(COALESCE(p_org,private.active_org_id()),p_code),FALSE)) THEN
      RAISE EXCEPTION 'Cannot delegate beyond own effective authority' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN v;
END; $$;

CREATE OR REPLACE FUNCTION public.mica_admin_apply(p_action TEXT,p_data JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor UUID:=private.admin_038_actor(); org UUID:=(p_data->>'organization_id')::UUID;
  target UUID:=(p_data->>'user_profile_id')::UUID; result UUID:=(p_data->>'id')::UUID;
  tpl UUID:=(p_data->>'role_template_id')::UUID; cap UUID; member UUID;
  active BOOLEAN:=COALESCE((p_data->>'is_active')::BOOLEAN,TRUE);
  sc TEXT:=p_data->>'scope'; effect TEXT:=p_data->>'effect'; code TEXT; kind TEXT:=p_data->>'kind';
  old_org public.eco_organizations%ROWTYPE; existing RECORD; recipients INTEGER; k TEXT;
BEGIN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::TEXT)>32768 THEN RAISE EXCEPTION 'Invalid payload'; END IF;
  -- Serialize before checking recipients and authority to avoid assignment races.
  PERFORM pg_advisory_xact_lock(380038);
  IF NOT private.is_platform_owner() AND private.can_platform('MICA_ADMIN_MANAGE') THEN
    IF org IS NOT NULL AND NOT private.platform_org_in_scope(org) THEN RAISE EXCEPTION 'Organization outside scope' USING ERRCODE='42501'; END IF;
    IF p_action='preset' AND result IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role r WHERE r.role_template_id=result AND NOT private.admin_039b_target_visible(r.user_profile_id))
        OR EXISTS (SELECT 1 FROM public.eco_organization_members m WHERE m.role_template_id=result AND NOT private.platform_org_in_scope(m.organization_id)) THEN
        RAISE EXCEPTION 'Preset recipients outside scope' USING ERRCODE='42501'; END IF;
    END IF;
    IF p_action='platform_role' THEN
      IF EXISTS (SELECT 1 FROM private.eco_mica_all_org_presets WHERE role_template_id=tpl)
        AND EXISTS (SELECT 1 FROM public.eco_organizations o WHERE o.is_active AND NOT private.platform_org_in_scope(o.id)) THEN
        RAISE EXCEPTION 'Cannot assign all-organization preset beyond own scope' USING ERRCODE='42501'; END IF;
      FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
        PERFORM private.admin_038_cap(code,'PLATFORM',NULL); END LOOP;
      FOR code IN SELECT c.code FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
        PERFORM private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;
    END IF;
  END IF;

  IF p_action='organization' THEN
    FOR k IN SELECT jsonb_object_keys(p_data) LOOP
      IF k NOT IN ('id','name','legal_name','trade_name','tax_id','is_active') THEN RAISE EXCEPTION 'Unsupported organization field %',k; END IF;
    END LOOP;
    IF result IS NULL THEN
      PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_CREATE',NULL);
      IF length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Name required'; END IF;
      INSERT INTO public.eco_organizations(name,legal_name,trade_name,tax_id,tax_id_type,country_code,currency,timezone,is_active)
        VALUES(btrim(p_data->>'name'),COALESCE(NULLIF(p_data->>'legal_name',''),p_data->>'name'),p_data->>'trade_name',p_data->>'tax_id',
        'CUIT','AR','ARS','America/Argentina/Buenos_Aires',TRUE) RETURNING id INTO result;
    ELSE
      SELECT * INTO STRICT old_org FROM public.eco_organizations WHERE id=result FOR UPDATE;
      IF p_data ? 'is_active' THEN
        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_ARCHIVE',NULL);
      END IF;
      IF NOT p_data ?| ARRAY['name','legal_name','trade_name','tax_id','is_active'] THEN RAISE EXCEPTION 'No organization changes supplied'; END IF;
      IF p_data ?| ARRAY['name','legal_name','trade_name','tax_id'] THEN
        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_UPDATE',NULL);
        IF NOT private.is_platform_owner() AND NOT EXISTS (SELECT 1 FROM private.eco_platform_org_scopes
          WHERE user_profile_id=actor AND organization_id=result AND is_active) THEN
          RAISE EXCEPTION 'Organization outside explicit scope' USING ERRCODE='42501'; END IF;
      END IF;
      IF p_data ? 'name' AND length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Name required'; END IF;
      UPDATE public.eco_organizations SET name=COALESCE(p_data->>'name',name),
        legal_name=CASE WHEN p_data?'legal_name' THEN p_data->>'legal_name' ELSE legal_name END,
        trade_name=CASE WHEN p_data?'trade_name' THEN p_data->>'trade_name' ELSE trade_name END,
        tax_id=CASE WHEN p_data?'tax_id' THEN p_data->>'tax_id' ELSE tax_id END,
        is_active=CASE WHEN p_data?'is_active' THEN active ELSE is_active END WHERE id=result;
    END IF;
  ELSIF p_action='preset' THEN
    PERFORM private.admin_038_authorize(org,'PLATFORM_MANAGE','ORG_MEMBER_PERMISSION_MANAGE');
    IF sc NOT IN ('PLATFORM','ORGANIZATION') OR sc IS NULL OR (sc='PLATFORM' AND org IS NOT NULL) THEN RAISE EXCEPTION 'Invalid preset scope'; END IF;
    IF length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Preset name required'; END IF;
    IF jsonb_typeof(p_data->'capabilities') IS DISTINCT FROM 'array' OR
       jsonb_typeof(p_data->'bridge') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Capability arrays required'; END IF;
    IF sc='ORGANIZATION' AND jsonb_array_length(p_data->'bridge')<>0 THEN RAISE EXCEPTION 'Bridge requires PLATFORM'; END IF;
    IF sc='ORGANIZATION' AND (p_data->'capabilities') ? 'RECORD_RESTORE' THEN
      RAISE EXCEPTION 'Restore requires a MICA platform preset bridge' USING ERRCODE='42501'; END IF;
    IF result IS NOT NULL THEN
      SELECT t.scope,r.organization_id INTO STRICT existing FROM private.eco_mica_presets r
        JOIN public.eco_role_templates t ON t.id=r.role_template_id WHERE t.id=result FOR UPDATE OF t;
      IF existing.scope<>sc OR existing.organization_id IS DISTINCT FROM org THEN RAISE EXCEPTION 'Preset scope is immutable'; END IF;
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role r JOIN private.eco_platform_owner o ON o.user_profile_id=r.user_profile_id WHERE r.role_template_id=result)
        OR EXISTS (SELECT 1 FROM public.eco_organization_members m JOIN private.eco_platform_owner o ON o.user_profile_id=m.user_profile_id WHERE m.role_template_id=result)
        THEN RAISE EXCEPTION 'Root preset protected' USING ERRCODE='42501'; END IF;
      SELECT (SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id=result)+
        (SELECT count(*) FROM public.eco_organization_members WHERE role_template_id=result) INTO recipients;
      IF recipients>0 AND (p_data->>'expected_recipients')::INTEGER IS DISTINCT FROM recipients THEN
        RAISE EXCEPTION 'Confirm current preset recipient count: %',recipients; END IF;
      IF org IS NOT NULL AND EXISTS (SELECT 1 FROM public.eco_organization_members WHERE role_template_id=result AND organization_id<>org)
        THEN RAISE EXCEPTION 'Preset has recipients outside organization' USING ERRCODE='42501'; END IF;
    ELSE
      result:=gen_random_uuid();
      INSERT INTO public.eco_role_templates(id,code,name,scope,is_system,is_active)
        VALUES(result,'MICA_'||replace(result::TEXT,'-',''),p_data->>'name',sc,FALSE,active);
      INSERT INTO private.eco_mica_presets VALUES(result,org);
    END IF;
    FOR code IN SELECT jsonb_array_elements_text(p_data->'capabilities') LOOP
      PERFORM private.admin_038_cap(code,sc,org);
    END LOOP;
    FOR code IN SELECT jsonb_array_elements_text(p_data->'bridge') LOOP
      PERFORM private.admin_038_cap(code,'ORGANIZATION',org);
    END LOOP;
    DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=result;
    DELETE FROM public.eco_platform_role_org_capabilities WHERE role_template_id=result;
    INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
      SELECT DISTINCT result,private.admin_038_cap(value,sc,org) FROM jsonb_array_elements_text(p_data->'capabilities');
    INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
      SELECT DISTINCT result,private.admin_038_cap(value,'ORGANIZATION',org) FROM jsonb_array_elements_text(p_data->'bridge');
    UPDATE public.eco_role_templates SET name=p_data->>'name',is_active=active,updated_at=now() WHERE id=result;
  ELSIF p_action IN ('user','platform_role','membership','scope','override') THEN
    PERFORM private.admin_038_target(target);
    IF p_action='membership' THEN
      PERFORM private.admin_038_authorize(org,'GLOBAL_USER_MANAGE','ORG_MEMBER_MANAGE');
      IF org IS NULL THEN RAISE EXCEPTION 'Membership requires organization'; END IF;
      PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN
        RAISE EXCEPTION 'Platform user requires explicit scopes, not artificial membership'; END IF;
    ELSIF p_action='override' AND kind='membership' THEN
      IF org IS NULL THEN RAISE EXCEPTION 'Membership override requires organization'; END IF;
      PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');
    ELSE
      PERFORM private.admin_038_authorize(NULL,'GLOBAL_USER_MANAGE',NULL);
    END IF;
    IF p_action IN ('platform_role','membership') THEN
      SELECT t.scope,r.organization_id INTO STRICT existing FROM private.eco_mica_presets r
        JOIN public.eco_role_templates t ON t.id=r.role_template_id WHERE t.id=tpl AND t.is_active;
      IF (p_action='platform_role' AND (existing.scope<>'PLATFORM' OR org IS NOT NULL))
        OR (p_action='membership' AND (existing.scope<>'ORGANIZATION' OR
          (existing.organization_id IS NOT NULL AND existing.organization_id<>org))) THEN RAISE EXCEPTION 'Incompatible preset'; END IF;
      IF p_action='membership' THEN
        FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
          PERFORM private.admin_038_cap(code,'ORGANIZATION',org);
        END LOOP;
        IF NOT EXISTS (SELECT 1 FROM public.eco_organization_members WHERE organization_id=org AND user_profile_id=target) THEN
          PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_INVITE'); END IF;
        INSERT INTO public.eco_organization_members(organization_id,user_profile_id,role_template_id,is_active)
          VALUES(org,target,tpl,active) ON CONFLICT(organization_id,user_profile_id)
          DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=EXCLUDED.is_active RETURNING id INTO result;
      ELSE
        IF EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active) THEN
          RAISE EXCEPTION 'Deactivate tenant memberships before platform assignment'; END IF;
        INSERT INTO public.eco_user_platform_role(user_profile_id,role_template_id,is_active) VALUES(target,tpl,active)
          ON CONFLICT(user_profile_id) DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=EXCLUDED.is_active;
        result:=target;
      END IF;
    ELSIF p_action='scope' THEN
      IF org IS NULL OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=org AND is_active)
        OR NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN RAISE EXCEPTION 'Active organization and platform assignment required'; END IF;
      INSERT INTO private.eco_platform_org_scopes(user_profile_id,organization_id,is_active) VALUES(target,org,active)
        ON CONFLICT(user_profile_id,organization_id) DO UPDATE SET is_active=EXCLUDED.is_active;
      result:=target;
    ELSIF p_action='override' THEN
      IF effect IS NULL OR effect NOT IN ('ALLOW','DENY','INHERITED') OR kind IS NULL OR kind NOT IN ('platform','membership','platform_org') THEN RAISE EXCEPTION 'Invalid override'; END IF;
      IF p_data->>'capability'='DATA_RESTORE_ANY_ORG' AND effect='ALLOW' AND
        (kind<>'platform' OR NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a
          JOIN public.eco_role_templates t ON t.id=a.role_template_id
          WHERE a.user_profile_id=target AND a.is_active AND t.is_active AND t.scope='PLATFORM')
          OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active)) THEN
        RAISE EXCEPTION 'Restore platform delegation requires a MICA platform recipient, never a tenant' USING ERRCODE='42501'; END IF;
      cap:=private.admin_038_cap(p_data->>'capability',CASE WHEN kind='platform' THEN 'PLATFORM' ELSE 'ORGANIZATION' END,
        CASE WHEN kind='membership' THEN org ELSE NULL END);
      IF kind='membership' THEN
        SELECT id INTO STRICT member FROM public.eco_organization_members WHERE organization_id=org AND user_profile_id=target;
        DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=member AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(member,cap,effect); END IF;
      ELSIF kind='platform_org' THEN
        IF NOT EXISTS (SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=target AND organization_id=org AND is_active)
          OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=org AND is_active) THEN RAISE EXCEPTION 'Explicit active scope required'; END IF;
        DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=target AND organization_id=org AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO private.eco_platform_org_overrides VALUES(target,org,cap,effect,now()); END IF;
      ELSE
        IF org IS NOT NULL THEN RAISE EXCEPTION 'Platform override cannot name a tenant'; END IF;
        DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=target AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES(target,cap,effect); END IF;
      END IF;
      result:=target;
    ELSE
      IF active AND NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active)
        AND NOT EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active) THEN
        RAISE EXCEPTION 'Assign an active preset and scope before approval'; END IF;
      UPDATE public.eco_user_profiles SET is_active=active WHERE id=target;
      IF active AND EXISTS (SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=target AND approved_at IS NULL) THEN
        IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN
          org:=NULL;
        ELSE
          IF org IS NULL THEN
            IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=target AND is_active)<>1 THEN
              RAISE EXCEPTION 'Select the initial organization for this pending user'; END IF;
            SELECT organization_id INTO org FROM public.eco_organization_members WHERE user_profile_id=target AND is_active;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM public.eco_organization_members m JOIN public.eco_organizations o ON o.id=m.organization_id
            WHERE m.user_profile_id=target AND m.organization_id=org AND m.is_active AND o.is_active) THEN
            RAISE EXCEPTION 'Initial context requires an active membership and organization'; END IF;
        END IF;
        INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(target,org)
          ON CONFLICT(user_profile_id) DO UPDATE SET organization_id=EXCLUDED.organization_id,updated_at=now();
        UPDATE public.eco_user_profiles SET organization_id=org WHERE id=target;
        UPDATE private.eco_mica_pending_profiles SET approved_at=now() WHERE user_profile_id=target;
      END IF;
      result:=target;
    END IF;
  ELSE RAISE EXCEPTION 'Unknown administration action';
  END IF;
  INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,target_user_profile_id,metadata)
    VALUES(actor,'MICA_ADMIN_'||upper(p_action),target,jsonb_build_object('organization_id',org,'target_id',result,'changes',p_data));
  RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.mica_admin_read(p_org UUID DEFAULT NULL,p_search TEXT DEFAULT '')
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor(); global_users BOOLEAN:=COALESCE(private.admin_039b_users(),FALSE);
  users_allowed BOOLEAN; presets_allowed BOOLEAN; result JSONB;
BEGIN
  IF length(COALESCE(p_search,''))>100 THEN RAISE EXCEPTION 'Search too long'; END IF;
  IF p_org IS NOT NULL AND (NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=actor AND organization_id=p_org)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org AND is_active)) THEN
    RAISE EXCEPTION 'Confirmed active tenant context required' USING ERRCODE='42501'; END IF;
  users_allowed:=global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_VIEW'),FALSE));
  presets_allowed:=COALESCE(private.admin_039b_presets(),FALSE)
    OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE));
  SELECT jsonb_build_object(
    'rights',jsonb_build_object(
      'organizations',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'create_organization',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE),
      'update_organization',COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE),
      'archive_organization',COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'users',users_allowed,'global_users',global_users,'presets',presets_allowed,
      'global_presets',COALESCE(private.admin_039b_presets(),FALSE),
      'assignments',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)),
      'memberships',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)
        AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_MANAGE'),FALSE))),
    'organizations',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'legal_name',legal_name,'trade_name',trade_name,'tax_id',tax_id,'is_active',is_active))
      FROM (SELECT o.* FROM public.eco_organizations o WHERE
        ((COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE) OR global_users)
          AND (private.is_platform_owner() OR EXISTS (SELECT 1 FROM private.eco_platform_org_scopes s WHERE s.organization_id=o.id AND s.user_profile_id=actor AND s.is_active)))
        OR (o.id=p_org AND COALESCE(private.can_operate_mica_org(p_org,'ORG_VIEW'),FALSE))
        ORDER BY o.name,o.id LIMIT 250) q),'[]'::JSONB),
    'users',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'email',email,'is_active',is_active,'protected',protected,'pending',pending))
      FROM (SELECT p.id,u.email,p.is_active,EXISTS(SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=p.id) AS protected,
        EXISTS(SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=p.id AND approved_at IS NULL) AS pending
        FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
        WHERE users_allowed AND private.admin_039b_target_visible(p.id) AND (global_users OR EXISTS (SELECT 1 FROM public.eco_organization_members m WHERE m.user_profile_id=p.id AND m.organization_id=p_org))
          AND (COALESCE(p_search,'')='' OR strpos(lower(COALESCE(u.email,'')),lower(p_search))>0)
        ORDER BY u.email,p.id LIMIT 200) q),'[]'::JSONB),
    'capabilities',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',code,'scope',scope,'description',description) ORDER BY scope,code)
      FROM public.eco_capabilities WHERE (presets_allowed OR users_allowed) AND is_active AND delegation_class<>'OWNER_RESERVED'
        AND private.mica_capability_allowed(code,scope) AND (scope='ORGANIZATION' OR global_users OR COALESCE(private.admin_039b_presets(),FALSE))),'[]'::JSONB),
    'presets',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'scope',t.scope,'organization_id',r.organization_id,'is_active',t.is_active,
      'recipients',(SELECT count(*) FROM public.eco_organization_members WHERE role_template_id=t.id)+(SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id=t.id),
      'capabilities',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB),
      'bridge',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB)))
      FROM private.eco_mica_presets r JOIN public.eco_role_templates t ON t.id=r.role_template_id
      WHERE (presets_allowed OR users_allowed) AND (global_users OR COALESCE(private.admin_039b_presets(),FALSE) OR
        (t.scope='ORGANIZATION' AND (r.organization_id IS NULL OR r.organization_id=p_org)))),'[]'::JSONB)
  ) INTO result;
  -- Assignment rows are restricted to the same bounded visible user set.
  RETURN result || jsonb_build_object(
    'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',x.user_profile_id,'organization_id',x.organization_id)) FROM public.eco_user_active_context x WHERE x.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v) AND (global_users OR x.organization_id=p_org)), '[]'::JSONB),
    'memberships',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',m.id,'user_profile_id',m.user_profile_id,'organization_id',m.organization_id,'role_template_id',m.role_template_id,'is_active',m.is_active))
      FROM public.eco_organization_members m WHERE (global_users OR m.organization_id=p_org) AND m.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'platform_roles',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',r.user_profile_id,'role_template_id',r.role_template_id,'is_active',r.is_active))
      FROM public.eco_user_platform_role r WHERE global_users AND r.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'scopes',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',s.user_profile_id,'organization_id',s.organization_id,'is_active',s.is_active))
      FROM private.eco_platform_org_scopes s WHERE global_users AND s.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'overrides',COALESCE((SELECT jsonb_agg(jsonb_build_object('kind',q.kind,'user_profile_id',q.profile,'organization_id',q.org,'capability',c.code,'effect',q.effect))
      FROM (
        SELECT 'platform' AS kind,user_profile_id AS profile,NULL::UUID AS org,capability_id,effect FROM public.eco_user_platform_capability_overrides WHERE global_users
        UNION ALL SELECT 'platform_org',user_profile_id,organization_id,capability_id,effect FROM private.eco_platform_org_overrides WHERE global_users
        UNION ALL SELECT 'membership',m.user_profile_id,m.organization_id,o.capability_id,o.effect FROM public.eco_membership_capability_overrides o
          JOIN public.eco_organization_members m ON m.id=o.membership_id WHERE global_users OR m.organization_id=p_org
      ) q JOIN public.eco_capabilities c ON c.id=q.capability_id
      WHERE c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)
        AND q.profile IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB));
END; $$;

CREATE OR REPLACE FUNCTION private.require_039_import(p_source TEXT,p_operation TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW');
  PERFORM private.require_039_action('IMPORT_VIEW');
  PERFORM private.require_039_action('IMPORT_CREATE');
  IF NOT EXISTS (SELECT 1 FROM (VALUES
    -- Fiscal imports stay closed until a specific MICA capability is approved.
    ('PERCEPCIONES_IVA','PERCEPCION'),
    ('PERCEPCIONES_ARBA','PERCEPCION'),('BANK_STATEMENT_BBVA','BANCO'),('PAYROLL_ACONPY','SUELDO')
  ) allowed(source,operation) WHERE source=p_source AND operation=p_operation) THEN
    RAISE EXCEPTION '039: unsupported MICA source/operation' USING ERRCODE='42501'; END IF;
  IF p_operation='BANCO' THEN PERFORM private.require_039_action('BANK_IMPORT');
  ELSIF p_operation='PERCEPCION' THEN PERFORM private.require_039_action('PERCEPTION_IMPORT');
  ELSIF p_operation='SUELDO' THEN PERFORM private.require_039_action('PAYROLL_IMPORT');
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.restore_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  IF NOT COALESCE(private.can_platform('DATA_RESTORE_ANY_ORG'),FALSE)
    OR NOT COALESCE(private.platform_org_in_scope(private.active_org_id()),FALSE) THEN
    RAISE EXCEPTION '039b restore requires MICA platform action and organization scope' USING ERRCODE='42501'; END IF;
  -- require_039_action validates confirmed context, active organization and contextual DENY.
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_RESTORE');
  v_org_id := private.active_org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'RESTORE_RECORD');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  IF NOT COALESCE(private.can_platform('DATA_RESTORE_ANY_ORG'),FALSE)
    OR NOT COALESCE(private.platform_org_in_scope(private.active_org_id()),FALSE) THEN
    RAISE EXCEPTION '039b restore requires MICA platform action and organization scope' USING ERRCODE='42501'; END IF;
  -- require_039_action validates confirmed context, active organization and contextual DENY.
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_RESTORE');
  v_org_id := private.active_org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'RESTORE_MOVEMENT');
  END IF;
END;
$$;

-- Automatic scope provisioning writes explicit rows. Existing inactive scopes stay revoked.
CREATE FUNCTION private.provision_039b_scopes() RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r RECORD;
BEGIN
  FOR r IN INSERT INTO private.eco_platform_org_scopes(user_profile_id,organization_id)
    SELECT a.user_profile_id,o.id FROM public.eco_user_platform_role a
    JOIN private.eco_mica_all_org_presets x ON x.role_template_id=a.role_template_id
    JOIN public.eco_role_templates t ON t.id=a.role_template_id AND t.is_active
    CROSS JOIN public.eco_organizations o WHERE a.is_active AND o.is_active
    ON CONFLICT(user_profile_id,organization_id) DO NOTHING RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('private.eco_platform_org_scopes',
      jsonb_build_object('user_profile_id',r.user_profile_id,'organization_id',r.organization_id),to_jsonb(r));
  END LOOP;
END; $$;
CREATE FUNCTION private.trigger_039b_scopes() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM private.provision_039b_scopes(); RETURN NULL; END; $$;
CREATE TRIGGER provision_039b_org AFTER INSERT OR UPDATE OF is_active ON public.eco_organizations
  FOR EACH STATEMENT EXECUTE FUNCTION private.trigger_039b_scopes();
CREATE TRIGGER provision_039b_role AFTER INSERT OR UPDATE OF role_template_id,is_active ON public.eco_user_platform_role
  FOR EACH STATEMENT EXECUTE FUNCTION private.trigger_039b_scopes();
CREATE TRIGGER provision_039b_template AFTER UPDATE OF is_active ON public.eco_role_templates
  FOR EACH STATEMENT EXECUTE FUNCTION private.trigger_039b_scopes();

DO $seed$
DECLARE root_template UUID; accounting UUID; tpl UUID; r RECORD; c TEXT; rowdata JSONB; spec RECORD;
BEGIN
  SELECT a.role_template_id INTO STRICT root_template FROM private.eco_platform_owner o
    JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id AND a.is_active
    JOIN public.eco_role_templates t ON t.id=a.role_template_id AND t.scope='PLATFORM' AND t.is_active;
  IF EXISTS(SELECT 1 FROM public.eco_user_platform_role a WHERE a.role_template_id=root_template
    AND NOT EXISTS(SELECT 1 FROM private.eco_platform_owner o WHERE o.user_profile_id=a.user_profile_id)) THEN
    RAISE EXCEPTION 'Root template has other recipients: review before seeding'; END IF;
  -- BEGIN GENERATED CAPABILITY SEED
  -- Adopted rows keep their UUID, metadata and grants; no grant is copied from another product.
  FOR r IN INSERT INTO public.eco_capabilities(code,description,scope,is_active,delegation_class)
    SELECT x.code,x.description,x.scope,TRUE,x.delegation_class FROM (VALUES
      ('DATA_RESTORE_ANY_ORG','Restaurar datos de empresas autorizadas — Restaurar con alcance, contexto confirmado y RECORD_RESTORE efectivo.','PLATFORM','PLATFORM_DELEGABLE'),
      ('MICA_ADMIN_MANAGE','Administrar usuarios y permisos MICA — Gestionar usuarios, presets y asignaciones dentro del alcance delegado.','PLATFORM','PLATFORM_DELEGABLE'),
      ('PURCHASES_INVOICES_MANAGE','Gestionar comprobantes de compras — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('SUPPLIERS_VIEW','Ver proveedores — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('SUPPLIERS_MANAGE','Administrar proveedores — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('SALES_VIEW','Ver comprobantes de ventas — Permiso MICA aprobado; la vista compartida actual sigue requiriendo RECORD_VIEW.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('PERSONNEL_EMPLOYEES_MANAGE','Administrar empleados — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('INTEGRATIONS_CONFIG_MANAGE','Configurar integraciones — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('INTEGRATIONS_SYNC_TRIGGER','Ejecutar sincronizaciones — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('MANUAL_MOVEMENT_VIEW','Ver movimientos manuales — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('MANUAL_MOVEMENT_CREATE','Crear movimientos manuales — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('MANUAL_MOVEMENT_EDIT','Editar movimientos manuales — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE'),
      ('MANUAL_MOVEMENT_SOFT_DELETE','Eliminar lógicamente movimientos manuales — Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.','ORGANIZATION','ORGANIZATION_DELEGABLE')
    ) x(code,description,scope,delegation_class)
    WHERE NOT EXISTS(SELECT 1 FROM public.eco_capabilities c WHERE c.code=x.code) RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed)
      VALUES('public.eco_capabilities',jsonb_build_object('id',r.id),to_jsonb(r));
  END LOOP;
  -- END GENERATED CAPABILITY SEED
  SELECT id INTO accounting FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN' AND scope='PLATFORM' AND is_active;
  IF accounting IS NULL THEN
    IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN') THEN RAISE EXCEPTION 'Accounting preset inactive or incompatible'; END IF;
    INSERT INTO public.eco_role_templates(code,name,scope,is_system,is_active) VALUES('ACCOUNTING_SUPERADMIN','Administracion general MICA','PLATFORM',FALSE,TRUE)
      RETURNING id,to_jsonb(eco_role_templates) INTO accounting,rowdata;
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('public.eco_role_templates',jsonb_build_object('id',accounting),rowdata);
  END IF;
  IF accounting=root_template THEN RAISE EXCEPTION 'Accounting and root presets must be distinct'; END IF;
  IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
    WHERE g.role_template_id=accounting AND (c.delegation_class='OWNER_RESERVED' OR NOT private.mica_capability_allowed(c.code,c.scope))) THEN
    RAISE EXCEPTION 'Accounting template has non-MICA grants; do not reuse'; END IF;
  IF EXISTS(SELECT 1 FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
    WHERE g.role_template_id=accounting AND NOT private.mica_capability_allowed(c.code,'ORGANIZATION')) THEN
    RAISE EXCEPTION 'Accounting bridge has non-MICA grants; do not reuse'; END IF;
  INSERT INTO private.eco_mica_all_org_presets VALUES(accounting);
  FOR r IN INSERT INTO private.eco_mica_presets(role_template_id,organization_id) VALUES(accounting,NULL)
    ON CONFLICT DO NOTHING RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('private.eco_mica_presets',jsonb_build_object('role_template_id',r.role_template_id),to_jsonb(r)); END LOOP;
  IF EXISTS(SELECT 1 FROM private.eco_mica_presets WHERE role_template_id=accounting AND organization_id IS NOT NULL) THEN RAISE EXCEPTION 'Accounting registry incompatible'; END IF;
  FOR r IN INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
    SELECT t,c.id FROM unnest(ARRAY[root_template,accounting]) t CROSS JOIN public.eco_capabilities c
    WHERE c.code=ANY(ARRAY['ORG_VIEW','ORG_SETTINGS_VIEW','ORG_SETTINGS_MANAGE','ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PERMISSION_MANAGE','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','RECORD_CLASSIFY','RECORD_SOFT_DELETE','RECORD_RESTORE','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','ISSUE_RESOLVE','CATALOG_ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','REPORT_VIEW','REPORT_EXPORT','TICKET_CREATE','TICKET_VIEW_ORG','AUDIT_VIEW_ORG','FINANCIAL_ALLOCATION_EDIT','SENSITIVEDATA_BANKING_READ','SENSITIVEDATA_SALARIES_READ','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE']::TEXT[]) AND c.scope='ORGANIZATION' AND c.is_active
    ON CONFLICT DO NOTHING RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('public.eco_platform_role_org_capabilities',
      jsonb_build_object('role_template_id',r.role_template_id,'capability_id',r.capability_id),to_jsonb(r)); END LOOP;
  IF EXISTS(SELECT 1 FROM unnest(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','ORGANIZATION_UPDATE','GLOBAL_CATALOG_VIEW','GLOBAL_CATALOG_MANAGE','CATALOG_ASSIGN_ANY_ORG','RATE_MANAGE_ANY_ORG','REPORT_COMPARE_SCOPED_ORGS','REPORT_CONSOLIDATED_SCOPED_ORGS','SAAS_ANALYTICS_VIEW','AUDIT_PLATFORM_VIEW']::TEXT[]) x(code) WHERE NOT EXISTS
    (SELECT 1 FROM public.eco_capabilities c WHERE c.code=x.code AND c.scope='PLATFORM' AND c.is_active AND c.delegation_class='PLATFORM_DELEGABLE')) THEN
    RAISE EXCEPTION 'Delegable platform capability contract missing'; END IF;
  FOR r IN INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
    SELECT accounting,c.id FROM public.eco_capabilities c WHERE c.code=ANY(ARRAY['DATA_RESTORE_ANY_ORG','MICA_ADMIN_MANAGE','ORGANIZATION_UPDATE','GLOBAL_CATALOG_VIEW','GLOBAL_CATALOG_MANAGE','CATALOG_ASSIGN_ANY_ORG','RATE_MANAGE_ANY_ORG','REPORT_COMPARE_SCOPED_ORGS','REPORT_CONSOLIDATED_SCOPED_ORGS','SAAS_ANALYTICS_VIEW','AUDIT_PLATFORM_VIEW']::TEXT[])
    UNION SELECT root_template,c.id FROM public.eco_capabilities c WHERE c.scope='PLATFORM' AND c.is_active
      AND c.delegation_class='PLATFORM_DELEGABLE' AND private.mica_capability_allowed(c.code,c.scope)
    ON CONFLICT DO NOTHING RETURNING * LOOP
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('public.eco_role_template_capabilities',
      jsonb_build_object('role_template_id',r.role_template_id,'capability_id',r.capability_id),to_jsonb(r)); END LOOP;
  FOR spec IN SELECT * FROM (VALUES ('MICA_ORG_ADMIN',ARRAY['ORG_VIEW','ORG_SETTINGS_VIEW','ORG_SETTINGS_MANAGE','ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PERMISSION_MANAGE','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','RECORD_CLASSIFY','RECORD_SOFT_DELETE','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','ISSUE_RESOLVE','CATALOG_ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','REPORT_VIEW','REPORT_EXPORT','TICKET_CREATE','TICKET_VIEW_ORG','AUDIT_VIEW_ORG','FINANCIAL_ALLOCATION_EDIT','SENSITIVEDATA_BANKING_READ','SENSITIVEDATA_SALARIES_READ','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE']::TEXT[],'Administrador de organización'),
('MICA_ACCOUNTANT',ARRAY['ORG_VIEW','ORG_SETTINGS_VIEW','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','RECORD_CLASSIFY','RECORD_SOFT_DELETE','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','ISSUE_RESOLVE','CATALOG_ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','REPORT_VIEW','REPORT_EXPORT','TICKET_CREATE','TICKET_VIEW_ORG','AUDIT_VIEW_ORG','FINANCIAL_ALLOCATION_EDIT','SENSITIVEDATA_BANKING_READ','SENSITIVEDATA_SALARIES_READ','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE']::TEXT[],'Contador / operador contable'),
('MICA_IMPORT_OPERATOR',ARRAY['ORG_VIEW','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','CATALOG_ORG_VIEW','TICKET_CREATE','TICKET_VIEW_ORG']::TEXT[],'Operador de importaciones'),
('MICA_READ_ONLY',ARRAY['ORG_VIEW','IMPORT_VIEW','RECORD_VIEW','CATALOG_ORG_VIEW','REPORT_VIEW','REPORT_EXPORT','TICKET_VIEW_ORG','AUDIT_VIEW_ORG']::TEXT[],'Consulta / auditor')) x(code,caps,label) LOOP
    INSERT INTO public.eco_role_templates(code,name,scope,is_system,is_active) VALUES(spec.code,spec.label,'ORGANIZATION',FALSE,TRUE)
      RETURNING id,to_jsonb(eco_role_templates) INTO tpl,rowdata;
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('public.eco_role_templates',jsonb_build_object('id',tpl),rowdata);
    INSERT INTO private.eco_mica_presets VALUES(tpl,NULL) RETURNING to_jsonb(eco_mica_presets) INTO rowdata;
    INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('private.eco_mica_presets',jsonb_build_object('role_template_id',tpl),rowdata);
    FOR r IN INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
      SELECT tpl,c.id FROM public.eco_capabilities c WHERE c.code=ANY(spec.caps) ON CONFLICT DO NOTHING RETURNING * LOOP
      INSERT INTO private.migration_039b_rows(relation,key,installed) VALUES('public.eco_role_template_capabilities',
        jsonb_build_object('role_template_id',r.role_template_id,'capability_id',r.capability_id),to_jsonb(r)); END LOOP;
  END LOOP;
  PERFORM private.provision_039b_scopes();
  INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
    SELECT user_profile_id,'MICA_039B_OPERATIONAL_PRESETS',jsonb_build_object('accounting_template',accounting,'root_template',root_template) FROM private.eco_platform_owner;
END; $seed$;
-- Existing replaced functions preserve ACL/owner through CREATE OR REPLACE.
DO $acl$
DECLARE r RECORD; a RECORD; who TEXT;
BEGIN
  FOR r IN SELECT oid,relowner,relacl FROM pg_class WHERE oid IN('private.migration_039b_functions'::regclass,'private.migration_039b_rows'::regclass,'private.eco_mica_all_org_presets'::regclass) LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(r.relacl,acldefault('r',r.relowner))) WHERE grantee<>r.relowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON TABLE %s FROM %s',r.oid::regclass,who); END LOOP;
  END LOOP;
  FOR r IN SELECT oid,proowner,proacl FROM pg_proc WHERE oid IN('private.admin_039b_users()'::regprocedure,'private.admin_039b_presets()'::regprocedure,
    'private.admin_039b_target_visible(uuid)'::regprocedure,'private.provision_039b_scopes()'::regprocedure,'private.trigger_039b_scopes()'::regprocedure) LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(r.proacl,acldefault('f',r.proowner))) WHERE grantee<>r.proowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',r.oid::regprocedure,who); END LOOP;
  END LOOP;
  UPDATE private.migration_039b_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
END; $acl$;
COMMIT;
