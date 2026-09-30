-- 039c MICA ourzapkjykzlwsjunzmd. Prepared for manual preflight; NOT executed.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF to_regclass('private.migration_039c_functions') IS NOT NULL THEN RAISE EXCEPTION '039c already installed'; END IF;
 IF to_regclass('private.migration_039b_functions') IS NULL THEN RAISE EXCEPTION '039b required'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='FISCAL_DOCUMENT_IMPORT') THEN RAISE EXCEPTION 'Review fiscal capability collision before adoption'; END IF;
 FOR r IN SELECT * FROM (VALUES ('private.mica_capability_allowed(text,text)','e0c89e3492e59dd4f0e2a5cf84086b40'),
('private.require_039_import(text,text)','a4f8f9f032e1d1ddef886e9c8306e19c'),
('public.request_failed_import_retry(uuid)','a5b2e0a74413514a34e33e98604052c4'),
('public.persist_import_batch(uuid,jsonb,jsonb)','45814412c9cf62dcb2ea7476da7917a7'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','ba0d33f9925a622faf528d9445910e98'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','bdd30c0aade623cc986b7409aca53ed8'),
('public.check_file_importable(text)','bf3df3596d9b6b44d9202052eca29599')) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
   AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
   AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
   RAISE EXCEPTION '039c LIVE function differs: %',r.signature; END IF;
 END LOOP;
END; $preflight$;
CREATE TABLE private.migration_039c_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed_definition TEXT);
CREATE TABLE private.migration_039c_grants(relation TEXT NOT NULL,key JSONB NOT NULL);
ALTER TABLE private.migration_039c_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.migration_039c_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039c_functions,private.migration_039c_grants FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039c_functions SELECT signature,pg_get_functiondef(to_regprocedure(signature)),NULL FROM (VALUES ('private.mica_capability_allowed(text,text)','e0c89e3492e59dd4f0e2a5cf84086b40'),
('private.require_039_import(text,text)','a4f8f9f032e1d1ddef886e9c8306e19c'),
('public.request_failed_import_retry(uuid)','a5b2e0a74413514a34e33e98604052c4'),
('public.persist_import_batch(uuid,jsonb,jsonb)','45814412c9cf62dcb2ea7476da7917a7'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','ba0d33f9925a622faf528d9445910e98'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','bdd30c0aade623cc986b7409aca53ed8'),
('public.check_file_importable(text)','bf3df3596d9b6b44d9202052eca29599')) x(signature,hash);
-- A failed file may be reused only by its explicit retry, with no business rows
-- (including soft-deleted rows) and no successful sibling attempt.
CREATE FUNCTION private.reuse_039c_file(p_import UUID,p_hash TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE f public.eco_source_files%ROWTYPE; parent UUID; org UUID:=private.active_org_id();
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(org::TEXT||p_hash,39));
 SELECT * INTO f FROM public.eco_source_files WHERE organization_id=org AND sha256_hash=p_hash FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT retry_of_import_id INTO parent FROM public.eco_source_imports WHERE id=p_import AND organization_id=org;
 IF parent IS DISTINCT FROM f.import_id OR EXISTS(SELECT 1 FROM public.eco_source_imports WHERE
   (id=parent OR retry_of_import_id=parent) AND COALESCE(accepted_rows,0)>0)
  OR EXISTS(SELECT 1 FROM public.eco_normalized_records nr JOIN public.eco_import_rows ir ON ir.id=nr.row_id WHERE ir.file_id=f.id)
  OR EXISTS(SELECT 1 FROM public.eco_financial_movements fm JOIN public.eco_import_rows ir ON ir.id=fm.row_id WHERE ir.file_id=f.id) THEN
  RAISE EXCEPTION 'FILE_ALREADY_EXISTS: file has business rows or is not the authorized retry'; END IF;
 RETURN f.id;
END; $$;

CREATE FUNCTION public.mica_import_file_status(p_file UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.active_org_id(); total BIGINT; active BIGINT;
BEGIN
 PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('IMPORT_VIEW');
 IF NOT EXISTS(SELECT 1 FROM public.eco_source_files WHERE id=p_file AND organization_id=org) THEN
  RAISE EXCEPTION 'File outside active context' USING ERRCODE='42501'; END IF;
 SELECT count(*),count(*) FILTER(WHERE deleted_at IS NULL) INTO total,active FROM (
  SELECT nr.deleted_at FROM public.eco_normalized_records nr JOIN public.eco_import_rows ir ON ir.id=nr.row_id
   WHERE ir.file_id=p_file AND nr.organization_id=org
  UNION ALL SELECT fm.deleted_at FROM public.eco_financial_movements fm JOIN public.eco_import_rows ir ON ir.id=fm.row_id
   WHERE ir.file_id=p_file AND fm.organization_id=org
 ) q;
 RETURN jsonb_build_object('organization_id',org,'total_rows',total,'active_rows',active);
END; $$;

-- Manual entries are independent of import-file provenance. No fabricated import
-- headers/rows are required, and no changes to fiscal pipeline constraints.
CREATE TABLE private.eco_manual_records(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
 payload JSONB NOT NULL, created_by UUID NOT NULL REFERENCES public.eco_user_profiles(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by UUID REFERENCES public.eco_user_profiles(id),
 updated_at TIMESTAMPTZ, deleted_by UUID REFERENCES public.eco_user_profiles(id), deleted_at TIMESTAMPTZ);
CREATE INDEX ON private.eco_manual_records(organization_id,created_at);
ALTER TABLE private.eco_manual_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.eco_manual_records FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.mica_manual_records(p_action TEXT,p_expected_org UUID,p_id UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.active_org_id(); actor UUID:=private.current_profile_id(); result UUID; f JSONB; k TEXT; d DATE; kind TEXT;
BEGIN
 PERFORM private.require_039_action('MANUAL_MOVEMENT_VIEW');
 IF org IS DISTINCT FROM p_expected_org OR org IS NULL THEN RAISE EXCEPTION 'Manual context changed' USING ERRCODE='42501'; END IF;
 IF p_action='list' THEN
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC,r.id) FROM private.eco_manual_records r
    WHERE organization_id=org AND deleted_at IS NULL),'[]'::JSONB);
 END IF;
 IF p_action='create' THEN PERFORM private.require_039_action('MANUAL_MOVEMENT_CREATE');
 ELSIF p_action='edit' THEN PERFORM private.require_039_action('MANUAL_MOVEMENT_EDIT');
 ELSIF p_action='delete' THEN PERFORM private.require_039_action('MANUAL_MOVEMENT_SOFT_DELETE');
 ELSE RAISE EXCEPTION 'Invalid manual action'; END IF;
 IF p_action IN ('create','edit') THEN
  IF jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::TEXT)>16384 THEN RAISE EXCEPTION 'Invalid manual payload'; END IF;
  kind:=p_data->>'kind'; f:=p_data->'fields';
  IF kind IS NULL OR kind NOT IN ('PURCHASE','INTERNAL') OR jsonb_typeof(f) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid manual kind/fields'; END IF;
  FOR k IN SELECT jsonb_object_keys(p_data) LOOP IF k NOT IN ('kind','fields') THEN RAISE EXCEPTION 'Unsupported manual key'; END IF; END LOOP;
  FOR k IN SELECT jsonb_object_keys(f) LOOP
   IF (kind='PURCHASE' AND k NOT IN ('fecha','tipoComprobante','puntoVenta','numeroComprobante','cuit','razonSocial','categoria','importeTotal','importeNoGravado','importeExento','importePercepIva','importePercepIibb','importePercepMun','importeInternos','moneda','tipoCambio','cantidadAlicuotas'))
    OR (kind='INTERNAL' AND k NOT IN ('tipo','fecha','imputacion','importe','descripcion')) THEN RAISE EXCEPTION 'Unsupported manual field: %',k; END IF;
   IF jsonb_typeof(f->k) NOT IN ('string','number') THEN RAISE EXCEPTION 'Invalid manual field type'; END IF;
  END LOOP;
  IF kind='PURCHASE' THEN
   IF COALESCE(f->>'fecha','') !~ '^[0-9]{8}$' OR COALESCE(f->>'tipoComprobante','') !~ '^[0-9]{3}$'
    OR COALESCE(f->>'puntoVenta','') !~ '^[0-9]{5}$' OR COALESCE(f->>'numeroComprobante','') !~ '^[0-9]{8}$'
    OR COALESCE(f->>'cuit','') !~ '^[0-9]{11}$' OR length(btrim(COALESCE(f->>'razonSocial','')))=0 THEN RAISE EXCEPTION 'Incomplete manual invoice'; END IF;
   d:=to_date(f->>'fecha','YYYYMMDD');
   IF to_char(d,'YYYYMMDD')<>f->>'fecha' THEN RAISE EXCEPTION 'Invalid date'; END IF;
   IF COALESCE(f->>'importeTotal','') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (f->>'importeTotal')::NUMERIC<=0 THEN RAISE EXCEPTION 'Invalid total'; END IF;
   FOREACH k IN ARRAY ARRAY['importeNoGravado','importeExento','importePercepIva','importePercepIibb','importePercepMun','importeInternos'] LOOP
    IF COALESCE(NULLIF(f->>k,''),'0') !~ '^[0-9]+([.][0-9]{1,2})?$' THEN RAISE EXCEPTION 'Invalid amount: %',k; END IF;
   END LOOP;
   IF COALESCE(f->>'moneda','')<>'PES' OR COALESCE(f->>'tipoCambio','') !~ '^[0-9]+([.][0-9]{1,6})?$' OR (f->>'tipoCambio')::NUMERIC<=0
    OR COALESCE(f->>'cantidadAlicuotas','') !~ '^[1-9][0-9]*$' THEN RAISE EXCEPTION 'Invalid currency/tax fields'; END IF;
  ELSE
   IF COALESCE(f->>'tipo','') NOT IN ('Ingreso','Gasto') OR COALESCE(f->>'fecha','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OR COALESCE(f->>'imputacion','') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    OR COALESCE(f->>'importe','') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (f->>'importe')::NUMERIC<=0 THEN RAISE EXCEPTION 'Incomplete internal movement'; END IF;
   d:=(f->>'fecha')::DATE;
  END IF;
 END IF;
 IF p_action='create' THEN
  INSERT INTO private.eco_manual_records(organization_id,payload,created_by) VALUES(org,p_data,actor) RETURNING id INTO result;
 ELSIF p_action='edit' THEN
  UPDATE private.eco_manual_records SET payload=p_data,updated_by=actor,updated_at=now()
   WHERE id=p_id AND organization_id=org AND deleted_at IS NULL RETURNING id INTO result;
 ELSE
  UPDATE private.eco_manual_records SET deleted_at=now(),deleted_by=actor,updated_at=now(),updated_by=actor
   WHERE id=p_id AND organization_id=org AND deleted_at IS NULL RETURNING id INTO result;
 END IF;
 IF result IS NULL THEN RAISE EXCEPTION 'Manual record not found in context' USING ERRCODE='42501'; END IF;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'MICA_MANUAL_'||upper(p_action),jsonb_build_object('organization_id',org,'record_id',result));
 RETURN jsonb_build_object('id',result,'organization_id',org);
END; $$;

-- Preauthorization is not an auth account or a grant. Auth registration stays 038:
-- pending/inactive. Only explicit administrator confirmation assigns the preset.
CREATE TABLE private.eco_mica_invitations(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), email TEXT NOT NULL,
 organization_id UUID REFERENCES public.eco_organizations(id), role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id),
 created_by UUID NOT NULL REFERENCES public.eco_user_profiles(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 assigned_to UUID REFERENCES public.eco_user_profiles(id), assigned_at TIMESTAMPTZ,
 UNIQUE(email));
ALTER TABLE private.eco_mica_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.eco_mica_invitations FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.mica_invitation(p_action TEXT,p_org UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor(); tpl UUID; target UUID; v_email TEXT; result UUID; sc TEXT; tpl_org UUID;
 invitation private.eco_mica_invitations%ROWTYPE; code TEXT;
BEGIN
 PERFORM private.admin_038_authorize(p_org,'GLOBAL_USER_MANAGE','ORG_MEMBER_INVITE');
 IF p_org IS NOT NULL THEN PERFORM private.admin_038_authorize(p_org,NULL,'ORG_MEMBER_PERMISSION_MANAGE'); END IF;
 IF NOT private.is_platform_owner() AND private.can_platform('MICA_ADMIN_MANAGE') AND p_org IS NOT NULL
  AND NOT private.platform_org_in_scope(p_org) THEN RAISE EXCEPTION 'Invitation outside scope' USING ERRCODE='42501'; END IF;
 IF p_action='list' THEN
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(i)||jsonb_build_object('user_profile_id',p.id,'pending',p.is_active=FALSE))
   FROM private.eco_mica_invitations i LEFT JOIN auth.users u ON lower(u.email)=i.email AND u.email_confirmed_at IS NOT NULL
   LEFT JOIN public.eco_user_profiles p ON p.auth_user_id=u.id
   WHERE i.organization_id IS NOT DISTINCT FROM p_org
     AND (p.id IS NULL OR private.admin_039b_target_visible(p.id))),'[]'::JSONB);
 END IF;
 PERFORM pg_advisory_xact_lock(380038);
 IF p_action='assign' THEN
  SELECT * INTO STRICT invitation FROM private.eco_mica_invitations WHERE id=(p_data->>'id')::UUID
   AND organization_id IS NOT DISTINCT FROM p_org FOR UPDATE;
  IF invitation.assigned_at IS NOT NULL THEN RAISE EXCEPTION 'Invitation already assigned'; END IF;
  SELECT p.id INTO STRICT target FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
   WHERE lower(u.email)=invitation.email AND u.email_confirmed_at IS NOT NULL AND NOT p.is_active;
  IF target IS DISTINCT FROM (p_data->>'user_profile_id')::UUID THEN RAISE EXCEPTION 'Review pending identity again'; END IF;
  PERFORM private.admin_038_target(target);
  PERFORM public.mica_admin_apply(CASE WHEN p_org IS NULL THEN 'platform_role' ELSE 'membership' END,
   jsonb_build_object('user_profile_id',target,'role_template_id',invitation.role_template_id,'organization_id',p_org,'is_active',TRUE));
  UPDATE private.eco_mica_invitations SET assigned_to=target,assigned_at=now() WHERE id=invitation.id;
  -- Activation is deliberately separate and uses mica_admin_apply('user').
  RETURN jsonb_build_object('user_profile_id',target,'assigned',TRUE,'activated',FALSE);
 END IF;
 IF p_action IS DISTINCT FROM 'create' OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::TEXT)>2048 THEN RAISE EXCEPTION 'Invalid invitation'; END IF;
 v_email:=lower(btrim(p_data->>'email')); tpl:=(p_data->>'role_template_id')::UUID;
 IF v_email IS NULL OR length(v_email)>254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid email'; END IF;
 IF EXISTS(SELECT 1 FROM auth.users WHERE lower(auth.users.email)=v_email) THEN RAISE EXCEPTION 'Email already registered: use Usuarios and Asignaciones'; END IF;
 SELECT t.scope,m.organization_id INTO STRICT sc,tpl_org FROM public.eco_role_templates t
  JOIN private.eco_mica_presets m ON m.role_template_id=t.id WHERE t.id=tpl AND t.is_active;
 IF (p_org IS NULL AND sc<>'PLATFORM') OR (p_org IS NOT NULL AND sc<>'ORGANIZATION')
  OR (tpl_org IS NOT NULL AND tpl_org IS DISTINCT FROM p_org)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id WHERE a.role_template_id=tpl) THEN
  RAISE EXCEPTION 'Incompatible or protected preset' USING ERRCODE='42501'; END IF;
 FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
  PERFORM private.admin_038_cap(code,sc,p_org); END LOOP;
 FOR code IN SELECT c.code FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
  PERFORM private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;
 INSERT INTO private.eco_mica_invitations(email,organization_id,role_template_id,created_by) VALUES(v_email,p_org,tpl,actor) RETURNING id INTO result;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'MICA_INVITATION_PENDING',jsonb_build_object('invitation_id',result,'organization_id',p_org));
 RETURN jsonb_build_object('id',result,'status','PENDING_AUTHENTICATION');
END; $$;

CREATE OR REPLACE FUNCTION private.mica_capability_allowed(p_code TEXT,p_scope TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM (VALUES
    ('FISCAL_DOCUMENT_IMPORT','ORGANIZATION'),
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
CREATE OR REPLACE FUNCTION private.require_039_import(p_source TEXT,p_operation TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW');
  PERFORM private.require_039_action('IMPORT_VIEW');
  PERFORM private.require_039_action('IMPORT_CREATE');
  IF NOT EXISTS (SELECT 1 FROM (VALUES
    -- Only formats supported by the existing parsers are accepted.
    ('ARCA_RECIBIDOS','COMPRA'),('ARCA_EMITIDOS','VENTA'),
    ('PERCEPCIONES_IVA','PERCEPCION'),
    ('PERCEPCIONES_ARBA','PERCEPCION'),('BANK_STATEMENT_BBVA','BANCO'),('PAYROLL_ACONPY','SUELDO')
  ) allowed(source,operation) WHERE source=p_source AND operation=p_operation) THEN
    RAISE EXCEPTION '039: unsupported MICA source/operation' USING ERRCODE='42501'; END IF;
  IF p_operation IN ('COMPRA','VENTA') THEN PERFORM private.require_039_action('FISCAL_DOCUMENT_IMPORT');
  ELSIF p_operation='BANCO' THEN PERFORM private.require_039_action('BANK_IMPORT');
  ELSIF p_operation='PERCEPCION' THEN PERFORM private.require_039_action('PERCEPTION_IMPORT');
  ELSIF p_operation='SUELDO' THEN PERFORM private.require_039_action('PAYROLL_IMPORT');
  END IF;
END; $$;
CREATE OR REPLACE FUNCTION public.request_failed_import_retry(
    p_import_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_org_id UUID;

    v_import_record RECORD;
    v_orig_file RECORD;
    v_downstream_count INT := 0;
    v_retry_downstream_count INT := 0;
    v_new_import_id UUID;
    v_profile_id UUID;
BEGIN
  PERFORM private.require_039_action('IMPORT_RETRY'); PERFORM private.require_039_batch(p_import_id,ARRAY['COMPRA','VENTA','PERCEPCION','BANCO','SUELDO']);
    -- Security check: tenant isolation & authorization
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;



    -- Lock original import record for inspection
    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    -- Invariant: Retry allowed ONLY if original accepted_rows = 0 (or null)
    IF COALESCE(v_import_record.accepted_rows, 0) > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % accepted rows', v_import_record.accepted_rows;
    END IF;

    -- Check downstream business rows for original import
    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_normalized_records nr
        JOIN public.eco_import_rows ir ON ir.id = nr.row_id
        JOIN public.eco_source_files sf ON sf.id = ir.file_id
        WHERE sf.import_id = p_import_id AND sf.organization_id = v_org_id;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_financial_movements
        WHERE import_id = p_import_id AND organization_id = v_org_id;
    END IF;

    IF v_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % downstream records persisted', v_downstream_count;
    END IF;

    -- Check if any existing retry attempt for this original import already has accepted or downstream rows
    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_normalized_records nr
        JOIN public.eco_import_rows ir ON ir.id = nr.row_id
        JOIN public.eco_source_files sf ON sf.id = ir.file_id
        JOIN public.eco_source_imports si ON si.id = sf.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_financial_movements fm
        JOIN public.eco_source_imports si ON si.id = fm.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id;
    END IF;

    IF v_retry_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: A retry attempt for this import already has % downstream records persisted', v_retry_downstream_count;
    END IF;

    SELECT id INTO v_profile_id
    FROM public.eco_user_profiles
    WHERE auth_user_id = auth.uid() AND is_active LIMIT 1;

    SELECT * INTO v_orig_file
    FROM public.eco_source_files
    WHERE import_id = p_import_id AND organization_id = v_org_id
    ORDER BY created_at ASC LIMIT 1;

    -- Generate new retry import attempt ID
    v_new_import_id := extensions.gen_random_uuid();

    -- Insert new retry import record (Original record & original file record remain 100% IMMUTABLE)
    INSERT INTO public.eco_source_imports (
        id,
        organization_id,
        retry_of_import_id,
        status,
        source_type,
        operation_type,
        total_rows,
        accepted_rows,
        invalid_rows,
        duplicate_rows,
        created_at,
        created_by
    ) VALUES (
        v_new_import_id,
        v_org_id,
        p_import_id,
        'PENDING',
        v_import_record.source_type,
        v_import_record.operation_type,
        0,
        0,
        0,
        0,
        NOW(),
        v_profile_id
    );

    -- Log audit event
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED');

    RETURN jsonb_build_object(
        'status', 'RETRY_CREATED',
        'original_import_id', p_import_id,
        'new_import_id', v_new_import_id,
        'import_id', v_new_import_id,
        'organization_id', v_org_id,
        'storage_prefix', v_org_id::text || '/' || v_new_import_id::text,
        'source_file_reused', v_orig_file IS NOT NULL,
        'storage_path', v_orig_file.storage_path,
        'message', 'Retry import attempt created successfully'
    );
END;
$$;
CREATE OR REPLACE FUNCTION public.persist_import_batch(
  p_import_id UUID,
  p_file_info JSONB,
  p_staged_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;

  v_import_record RECORD;
  v_existing_file_id UUID;
  v_file_id UUID;
  v_row_record JSONB;
  v_norm JSONB;
  v_row_id UUID;
  v_record_id UUID;

  -- Metadatos de archivo
  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;

  -- Computados server-side
  v_fecha_raw TEXT;
  v_fecha DATE;
  v_cuit_clean TEXT;
  v_tipo_cbte TEXT;
  v_pdv TEXT;
  v_nro_desde TEXT;
  v_nro_hasta TEXT;
  v_moneda TEXT;
  v_computed_identity_key TEXT;

  v_neto NUMERIC(15,2);
  v_iva NUMERIC(15,2);
  v_otros NUMERIC(15,2);
  v_exento NUMERIC(15,2);
  v_nograv NUMERIC(15,2);
  v_total NUMERIC(15,2);
  v_computed_fingerprint TEXT;

  v_is_exact_duplicate BOOLEAN;
  v_is_amendment BOOLEAN;
  v_computed_status TEXT;

  v_accepted_cnt INT := 0;
  v_invalid_cnt INT := 0;
  v_duplicate_cnt INT := 0;
  v_total_cnt INT := 0;
  v_issue_cnt INT := 0;
BEGIN
  PERFORM private.require_039_batch(p_import_id,ARRAY['COMPRA','VENTA']);
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  -- 1. Role Check


  -- 2. LÃ­mite de Batch (MÃ¡ximo 500 filas)
  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds maximum allowed limit of 500 rows';
  END IF;

  -- 3. Validar Import y Estado PENDING
  SELECT * INTO v_import_record
  FROM public.eco_source_imports
  WHERE id = p_import_id AND organization_id = v_org_id;

  IF v_import_record.id IS NULL THEN
    RAISE EXCEPTION 'Import record not found or access denied';
  END IF;

  IF v_import_record.status != 'PENDING' THEN
    RAISE EXCEPTION 'Invalid import status: import is in status %', v_import_record.status;
  END IF;

  IF EXISTS (SELECT 1 FROM public.eco_source_files WHERE import_id = p_import_id) THEN
    RAISE EXCEPTION 'File already registered for import %', p_import_id;
  END IF;

  -- 4. Validar Metadatos de Archivo Server-Side
  v_hash := p_file_info->>'sha256_hash';
  IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
  END IF;

  v_filename := TRIM(COALESCE(p_file_info->>'original_name', ''));
  IF v_filename = '' OR LENGTH(v_filename) > 255 THEN
    RAISE EXCEPTION 'Invalid or missing original_name';
  END IF;

  v_size := (p_file_info->>'size_bytes')::BIGINT;
  IF v_size IS NULL OR v_size <= 0 OR v_size > 20971520 THEN
    RAISE EXCEPTION 'Invalid size_bytes: must be between 1 byte and 20MB';
  END IF;

  v_mime := p_file_info->>'mime_type';
  IF v_mime NOT IN (
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv'
  ) THEN
    RAISE EXCEPTION 'Disallowed mime_type: %', v_mime;
  END IF;

  v_storage_path := p_file_info->>'storage_path';
  v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
  IF NOT (v_storage_path LIKE v_expected_prefix || '%') AND NOT EXISTS (
    SELECT 1 FROM public.eco_source_files sf JOIN public.eco_source_imports si ON si.retry_of_import_id=sf.import_id
    WHERE si.id=p_import_id AND si.organization_id=v_org_id AND sf.organization_id=v_org_id
      AND sf.sha256_hash=v_hash AND sf.storage_path=v_storage_path) THEN
    RAISE EXCEPTION 'Invalid storage path: Must start with %', v_expected_prefix;
  END IF;

  -- 5. Pre-check de Archivo Duplicado por Hash SHA-256
  v_existing_file_id := private.reuse_039c_file(p_import_id,v_hash);


  -- Actualizar estado a PROCESSING
  UPDATE public.eco_source_imports SET status = 'PROCESSING' WHERE id = p_import_id;

  -- 6. Registrar Archivo
  IF v_existing_file_id IS NULL THEN
  INSERT INTO public.eco_source_files (
    import_id,
    organization_id,
    original_name,
    storage_path,
    mime_type,
    size_bytes,
    sha256_hash,
    source_type
  ) VALUES (
    p_import_id,
    v_org_id,
    v_filename,
    v_storage_path,
    v_mime,
    v_size,
    v_hash,
    v_import_record.source_type
  )
  RETURNING id INTO v_file_id;
  ELSE v_file_id := v_existing_file_id; END IF;

  -- 7. Procesar Filas
  FOR v_row_record IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row_record->'normalizedData';

    IF v_norm IS NULL OR v_norm = 'null'::jsonb THEN
      -- Fila InvÃ¡lida
      v_invalid_cnt := v_invalid_cnt + 1;
      v_issue_cnt := v_issue_cnt + 1;

      INSERT INTO public.eco_import_rows (
        file_id,
        organization_id,
        source_row_number,
        raw_payload,
        parse_status,
        errors
      ) VALUES (
        v_file_id,
        v_org_id,
        (v_row_record->>'sourceRowNumber')::INT,
        v_row_record->'rawRow',
        'INVALID',
        COALESCE(v_row_record->'errors', '[]'::jsonb)
      )
      RETURNING id INTO v_row_id;

      INSERT INTO public.eco_import_issues (
        organization_id,
        import_id,
        row_id,
        record_id,
        issue_type,
        message,
        details
      ) VALUES (
        v_org_id,
        p_import_id,
        v_row_id,
        NULL,
        'PARSE_ERROR',
        'Fila invÃ¡lida omitida durante la importaciÃ³n',
        v_row_record->'errors'
      );

    ELSE
      -- ReconstrucciÃ³n Server-Side de Identidad y Fingerprint
      v_cuit_clean := REGEXP_REPLACE(COALESCE(v_norm->>'cuit', ''), '-', '', 'g');
      v_tipo_cbte := REGEXP_REPLACE(COALESCE(v_norm->>'tipo_cbte', ''), '^0+', '');
      IF v_tipo_cbte = '' THEN v_tipo_cbte := '0'; END IF;

      v_pdv := REGEXP_REPLACE(COALESCE(v_norm->>'pdv', ''), '^0+', '');
      IF v_pdv = '' THEN v_pdv := '0'; END IF;

      v_nro_desde := REGEXP_REPLACE(COALESCE(v_norm->>'nroDesde', ''), '^0+', '');
      IF v_nro_desde = '' THEN v_nro_desde := '0'; END IF;

      v_nro_hasta := REGEXP_REPLACE(COALESCE(v_norm->>'nroHasta', v_norm->>'nroDesde', ''), '^0+', '');
      IF v_nro_hasta = '' THEN v_nro_hasta := v_nro_desde; END IF;

      v_moneda := UPPER(TRIM(COALESCE(v_norm->>'moneda', 'PES')));

      v_computed_identity_key := jsonb_build_array(
        v_import_record.operation_type,
        v_cuit_clean,
        v_tipo_cbte,
        v_pdv,
        v_nro_desde,
        v_nro_hasta,
        v_moneda
      )::text;

      -- NormalizaciÃ³n Server-Side de Fecha (Soporta YYYY-MM-DD y DD/MM/YYYY con validaciÃ³n estricta)
      v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));

      IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN
        v_fecha := v_fecha_raw::DATE;
        IF TO_CHAR(v_fecha, 'YYYY-MM-DD') != v_fecha_raw THEN
          RAISE EXCEPTION 'Invalid calendar date: %', v_fecha_raw;
        END IF;

      ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN
        v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
        IF TO_CHAR(v_fecha, 'DD/MM/YYYY') != v_fecha_raw THEN
          RAISE EXCEPTION 'Invalid calendar date: %', v_fecha_raw;
        END IF;

      ELSE
        RAISE EXCEPTION 'Invalid date format: "%". Expected YYYY-MM-DD or DD/MM/YYYY', v_fecha_raw;
      END IF;

      v_neto := ROUND(COALESCE((v_norm->>'netoGravado')::numeric, 0), 2);
      v_iva := ROUND(COALESCE((v_norm->>'totalIva')::numeric, 0), 2);
      v_otros := ROUND(COALESCE((v_norm->>'otrosTributos')::numeric, 0), 2);
      v_exento := ROUND(COALESCE((v_norm->>'exento')::numeric, 0), 2);
      v_nograv := ROUND(COALESCE((v_norm->>'netoNoGravado')::numeric, 0), 2);
      v_total := ROUND(COALESCE((v_norm->>'total')::numeric, 0), 2);

      v_computed_fingerprint := ENCODE(extensions.digest(
        v_neto::text || '|' || v_iva::text || '|' || v_otros::text || '|' || v_exento::text || '|' || v_nograv::text || '|' || v_total::text,
        'sha256'
      ), 'hex');

      -- Algoritmo Server-Side de ClasificaciÃ³n
      SELECT EXISTS (
        SELECT 1 FROM public.eco_normalized_records
        WHERE organization_id = v_org_id
          AND identity_key = v_computed_identity_key
          AND fiscal_fingerprint = v_computed_fingerprint
      ) INTO v_is_exact_duplicate;

      IF v_is_exact_duplicate THEN
        v_computed_status := 'EXACT_DUPLICATE';
      ELSE
        SELECT EXISTS (
          SELECT 1 FROM public.eco_normalized_records
          WHERE organization_id = v_org_id
            AND identity_key = v_computed_identity_key
        ) INTO v_is_amendment;

        IF v_is_amendment THEN
          v_computed_status := 'POSSIBLE_AMENDMENT';
        ELSE
          v_computed_status := 'ACCEPTED';
        END IF;
      END IF;

      INSERT INTO public.eco_import_rows (
        file_id,
        organization_id,
        source_row_number,
        raw_payload,
        parse_status,
        errors,
        warnings
      ) VALUES (
        v_file_id,
        v_org_id,
        (v_row_record->>'sourceRowNumber')::INT,
        v_row_record->'rawRow',
        v_computed_status,
        COALESCE(v_row_record->'errors', '[]'::jsonb),
        COALESCE(v_row_record->'warnings', '[]'::jsonb)
      )
      RETURNING id INTO v_row_id;

      IF v_computed_status IN ('ACCEPTED', 'POSSIBLE_AMENDMENT') THEN
        v_accepted_cnt := v_accepted_cnt + 1;

        INSERT INTO public.eco_normalized_records (
          row_id,
          organization_id,
          record_type,
          status,
          identity_key,
          fiscal_fingerprint,
          fecha,
          cuit,
          razon_social,
          comprobante,
          total,
          tipo_operacion,
          normalized_payload
        ) VALUES (
          v_row_id,
          v_org_id,
          v_import_record.source_type,
          'ACCEPTED',
          v_computed_identity_key,
          v_computed_fingerprint,
          v_fecha,
          v_cuit_clean,
          v_norm->>'razonSocial',
          v_tipo_cbte || '-' || v_pdv || '-' || v_nro_desde,
          v_total,
          v_import_record.operation_type,
          v_norm
        )
        RETURNING id INTO v_record_id;

        IF v_computed_status = 'POSSIBLE_AMENDMENT' THEN
          v_issue_cnt := v_issue_cnt + 1;

          INSERT INTO public.eco_import_issues (
            organization_id,
            import_id,
            row_id,
            record_id,
            issue_type,
            message,
            details
          ) VALUES (
            v_org_id,
            p_import_id,
            v_row_id,
            v_record_id,
            'AMENDMENT_DETECTED',
            'Se detectÃ³ una versiÃ³n modificada de un comprobante existente',
            jsonb_build_object('computedFingerprint', v_computed_fingerprint)
          );
        END IF;

      ELSIF v_computed_status = 'EXACT_DUPLICATE' THEN
        v_duplicate_cnt := v_duplicate_cnt + 1;
      END IF;

    END IF;
  END LOOP;

  -- 8. Finalizar ImportaciÃ³n
  UPDATE public.eco_source_imports
  SET
    status = CASE WHEN v_issue_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
    total_rows = v_total_cnt,
    accepted_rows = v_accepted_cnt,
    invalid_rows = v_invalid_cnt,
    duplicate_rows = v_duplicate_cnt,
    completed_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'IMPORT_COMPLETED');

  RETURN jsonb_build_object(
    'import_id', p_import_id,
    'total_rows', v_total_cnt,
    'accepted_rows', v_accepted_cnt,
    'invalid_rows', v_invalid_cnt,
    'duplicate_rows', v_duplicate_cnt,
    'issue_rows', v_issue_cnt,
    'status', CASE WHEN v_issue_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.persist_perceptions_batch(
  p_import_id UUID,
  p_file_info JSONB,
  p_staged_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;

  v_import_record RECORD;
  v_existing_file_id UUID;
  v_file_id UUID;
  v_row_elem JSONB;
  v_norm JSONB;
  v_row_id UUID;
  v_record_id UUID;

  -- Metadatos de archivo
  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;

  -- Campos y valores computados server-side
  v_source_type TEXT;
  v_fecha_raw TEXT;
  v_fecha DATE;
  v_fecha_canonical TEXT;
  v_date_ok BOOLEAN;
  v_cuit_clean TEXT;
  v_regimen_norm TEXT;
  v_sucursal_norm TEXT;
  v_comprobante_norm TEXT;
  v_razon_social TEXT;
  v_monto NUMERIC(15,2);
  v_computed_identity_key TEXT;
  v_computed_fingerprint TEXT;

  -- ClasificaciÃ³n y contadores
  v_is_exact_duplicate BOOLEAN;
  v_is_amendment BOOLEAN;
  v_computed_status TEXT;

  v_accepted_cnt INT := 0;
  v_invalid_cnt  INT := 0;
  v_duplicate_cnt INT := 0;
  v_total_cnt    INT := 0;
  v_issue_cnt    INT := 0;

BEGIN
  PERFORM private.require_039_batch(p_import_id,ARRAY['PERCEPCION']);
  -- ============================================================
  -- Â§ AUTORIZACIÃ“N: org_id + rol server-side
  -- ============================================================
  v_org_id      := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  -- Permiso exclusivo: UPLOADER / ADMIN
  -- Rechaza: USER, REVIEWER


  -- ============================================================
  -- Â§ BATCH LIMIT: mÃ¡ximo 500 filas server-side
  -- ============================================================
  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds maximum allowed limit of 500 rows';
  END IF;

  -- ============================================================
  -- Â§ IMPORT AUTHORITY
  -- ============================================================
  SELECT * INTO v_import_record
  FROM public.eco_source_imports
  WHERE id = p_import_id
    AND organization_id = v_org_id;

  IF v_import_record.id IS NULL THEN
    RAISE EXCEPTION 'Import record not found or access denied';
  END IF;

  IF v_import_record.status != 'PENDING' THEN
    RAISE EXCEPTION 'Invalid import status: import is in status %', v_import_record.status;
  END IF;

  -- source_type debe ser exclusivamente PERCEPCIONES_ARBA o PERCEPCIONES_IVA
  IF v_import_record.source_type NOT IN ('PERCEPCIONES_ARBA', 'PERCEPCIONES_IVA') THEN
    RAISE EXCEPTION 'Invalid source_type for perceptions pipeline: %', v_import_record.source_type;
  END IF;

  -- operation_type obligatoriamente PERCEPCION
  IF v_import_record.operation_type != 'PERCEPCION' THEN
    RAISE EXCEPTION 'Invalid operation_type for perceptions pipeline: %', v_import_record.operation_type;
  END IF;

  -- ============================================================
  -- Â§ FILE METADATA â€” defensas idÃ©nticas a Migration 010/011
  -- ============================================================

  -- Verificar que no exista ya un archivo registrado para este import
  IF EXISTS (SELECT 1 FROM public.eco_source_files WHERE import_id = p_import_id) THEN
    RAISE EXCEPTION 'File already registered for import %', p_import_id;
  END IF;

  -- sha256_hash: 64 hex lowercase, obligatorio
  v_hash := p_file_info->>'sha256_hash';
  IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
  END IF;

  -- original_name: obligatorio, <= 255 chars
  v_filename := TRIM(COALESCE(p_file_info->>'original_name', ''));
  IF v_filename = '' OR LENGTH(v_filename) > 255 THEN
    RAISE EXCEPTION 'Invalid or missing original_name';
  END IF;

  -- size_bytes: > 0 y <= 20 MB
  v_size := (p_file_info->>'size_bytes')::BIGINT;
  IF v_size IS NULL OR v_size <= 0 OR v_size > 20971520 THEN
    RAISE EXCEPTION 'Invalid size_bytes: must be between 1 byte and 20MB';
  END IF;

  -- mime_type: lista permitida
  v_mime := p_file_info->>'mime_type';
  IF v_mime NOT IN (
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv'
  ) THEN
    RAISE EXCEPTION 'Disallowed mime_type: %', v_mime;
  END IF;

  -- storage_path: debe comenzar con {org_id}/{import_id}/
  v_storage_path := p_file_info->>'storage_path';
  v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
  IF NOT (v_storage_path LIKE v_expected_prefix || '%') AND NOT EXISTS (
    SELECT 1 FROM public.eco_source_files sf JOIN public.eco_source_imports si ON si.retry_of_import_id=sf.import_id
    WHERE si.id=p_import_id AND si.organization_id=v_org_id AND sf.organization_id=v_org_id
      AND sf.sha256_hash=v_hash AND sf.storage_path=v_storage_path) THEN
    RAISE EXCEPTION 'Invalid storage path: Must start with %', v_expected_prefix;
  END IF;

  -- Pre-check duplicado por organization_id + sha256_hash
  v_existing_file_id := private.reuse_039c_file(p_import_id,v_hash);


  -- ============================================================
  -- Â§ TRANSICIÃ“N ATÃ“MICA: PENDING â†’ PROCESSING
  -- ============================================================
  UPDATE public.eco_source_imports
  SET status = 'PROCESSING'
  WHERE id = p_import_id;

  -- ============================================================
  -- Â§ REGISTRAR METADATOS DE ARCHIVO EN eco_source_files
  -- ============================================================
  IF v_existing_file_id IS NULL THEN
  INSERT INTO public.eco_source_files (
    import_id,
    organization_id,
    original_name,
    storage_path,
    mime_type,
    size_bytes,
    sha256_hash,
    source_type
  ) VALUES (
    p_import_id,
    v_org_id,
    v_filename,
    v_storage_path,
    v_mime,
    v_size,
    v_hash,
    v_import_record.source_type
  )
  RETURNING id INTO v_file_id;
  ELSE v_file_id := v_existing_file_id; END IF;

  -- ============================================================
  -- Â§ PROCESAMIENTO DE FILAS
  -- ============================================================
  v_source_type := v_import_record.source_type;

  FOR v_row_elem IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row_elem->'normalizedData';

    -- â”€â”€â”€ FILA INVÃLIDA (normalizedData ausente o null) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_norm IS NULL OR v_norm = 'null'::jsonb THEN
      v_invalid_cnt := v_invalid_cnt + 1;
      v_issue_cnt   := v_issue_cnt + 1;

      INSERT INTO public.eco_import_rows (
        file_id,
        organization_id,
        source_row_number,
        raw_payload,
        parse_status,
        errors
      ) VALUES (
        v_file_id,
        v_org_id,
        (v_row_elem->>'sourceRowNumber')::INT,
        v_row_elem->'rawRow',
        'INVALID',
        COALESCE(v_row_elem->'errors', '[]'::jsonb)
      )
      RETURNING id INTO v_row_id;

      INSERT INTO public.eco_import_issues (
        organization_id,
        import_id,
        row_id,
        record_id,
        issue_type,
        message,
        details
      ) VALUES (
        v_org_id,
        p_import_id,
        v_row_id,
        NULL,   -- record_id = NULL para filas invÃ¡lidas sin registro normalizado
        'PARSE_ERROR',
        'Fila de percepciÃ³n invÃ¡lida omitida durante la importaciÃ³n',
        v_row_elem->'errors'
      );

      CONTINUE;
    END IF;

    -- â”€â”€â”€ CUIT: solo dÃ­gitos, sin separadores â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    v_cuit_clean := REGEXP_REPLACE(COALESCE(v_norm->>'cuit', ''), '\D', '', 'g');

    -- â”€â”€â”€ CANONICALIZACIÃ“N SERVER-SIDE DE FECHA â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- Acepta: DD/MM/YYYY  y  YYYY-MM-DD
    -- Rechaza cualquier otra forma, vacÃ­o o fecha invÃ¡lida en calendario.
    -- Una fecha invÃ¡lida convierte la fila en INVALID (PARSE_ERROR), NO rollback total.
    v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));
    v_date_ok := FALSE;
    v_fecha := NULL;

    BEGIN
      IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN
        -- Formato ISO
        v_fecha := v_fecha_raw::DATE;
        -- Verificar que la fecha sea calendÃ¡ricamente vÃ¡lida (e.g. no 2026-02-31)
        IF TO_CHAR(v_fecha, 'YYYY-MM-DD') = v_fecha_raw THEN
          v_date_ok := TRUE;
        END IF;

      ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN
        -- Formato argentino DD/MM/YYYY
        v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
        -- Verificar que la conversiÃ³n sea exacta (round-trip)
        IF TO_CHAR(v_fecha, 'DD/MM/YYYY') = v_fecha_raw THEN
          v_date_ok := TRUE;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_date_ok := FALSE;
      v_fecha   := NULL;
    END;

    IF NOT v_date_ok OR v_fecha IS NULL THEN
      -- Fecha invÃ¡lida: registrar fila como INVALID + PARSE_ERROR
      v_invalid_cnt := v_invalid_cnt + 1;
      v_issue_cnt   := v_issue_cnt + 1;

      INSERT INTO public.eco_import_rows (
        file_id,
        organization_id,
        source_row_number,
        raw_payload,
        parse_status,
        errors
      ) VALUES (
        v_file_id,
        v_org_id,
        (v_row_elem->>'sourceRowNumber')::INT,
        v_row_elem->'rawRow',
        'INVALID',
        jsonb_build_array(
          jsonb_build_object('field', 'fecha', 'message',
            'Formato de fecha invÃ¡lido o fecha inexistente: "' || v_fecha_raw || '". Se acepta DD/MM/YYYY o YYYY-MM-DD')
        )
      )
      RETURNING id INTO v_row_id;

      INSERT INTO public.eco_import_issues (
        organization_id,
        import_id,
        row_id,
        record_id,
        issue_type,
        message,
        details
      ) VALUES (
        v_org_id,
        p_import_id,
        v_row_id,
        NULL,
        'PARSE_ERROR',
        'Fecha invÃ¡lida en percepciÃ³n: "' || v_fecha_raw || '"',
        jsonb_build_object('field', 'fecha', 'raw', v_fecha_raw)
      );

      CONTINUE;
    END IF;

    -- Fecha canonical server-side â€” NUNCA fecha raw
    v_fecha_canonical := TO_CHAR(v_fecha, 'YYYY-MM-DD');

    -- â”€â”€â”€ MONTO Y FINGERPRINT FISCAL DETERMINÃSTICO â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    -- Prioridad: monto > amount > importe
    -- Canonicalizado a NUMERIC(15,2)
    -- Fingerprint: SHA-256 sobre representaciÃ³n TO_CHAR determinÃ­stica con 2 decimales
    v_monto := ROUND(COALESCE(
      NULLIF(TRIM(COALESCE(v_norm->>'monto',  '')), '')::numeric,
      NULLIF(TRIM(COALESCE(v_norm->>'amount', '')), '')::numeric,
      NULLIF(TRIM(COALESCE(v_norm->>'importe','')),'')::numeric,
      0
    ), 2);

    v_computed_fingerprint := ENCODE(
      extensions.digest(
        TO_CHAR(v_monto, 'FM999999999999990.00'),
        'sha256'
      ),
      'hex'
    );

    -- â”€â”€â”€ IDENTIDAD CANÃ“NICA POR SOURCE_TYPE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    IF v_source_type = 'PERCEPCIONES_ARBA' THEN
      -- ARBA: regimen, sucursal y comprobante sin convertir a nÃºmero.
      -- TRIM, preservar ceros iniciales.
      v_regimen_norm    := COALESCE(NULLIF(TRIM(v_norm->>'regimen'),    ''), '');
      v_sucursal_norm   := COALESCE(NULLIF(TRIM(v_norm->>'sucursal'),   ''), '');
      v_comprobante_norm:= COALESCE(NULLIF(TRIM(v_norm->>'comprobante'),''), '');

      -- razon_social: NULL si no existe en el payload ARBA
      v_razon_social := NULLIF(TRIM(COALESCE(v_norm->>'razonSocial', '')), '');

      -- identity_key ARBA â€” server-side, no confiar en frontend
      v_computed_identity_key := jsonb_build_array(
        'PERCEPCION',
        'PERCEPCIONES_ARBA',
        'ARBA',
        v_regimen_norm,
        v_cuit_clean,
        v_fecha_canonical,
        v_sucursal_norm,
        v_comprobante_norm
      )::text;

    ELSIF v_source_type = 'PERCEPCIONES_IVA' THEN
      -- IVA: comprobante preservado como TEXT, sin inventar rÃ©gimen
      v_comprobante_norm := COALESCE(NULLIF(TRIM(v_norm->>'comprobante'), ''), '');
      v_regimen_norm     := NULL;  -- IVA no tiene rÃ©gimen
      v_sucursal_norm    := NULL;

      -- razon_social: desde razonSocial del payload IVA
      v_razon_social := NULLIF(TRIM(COALESCE(v_norm->>'razonSocial', '')), '');

      -- identity_key IVA â€” server-side
      v_computed_identity_key := jsonb_build_array(
        'PERCEPCION',
        'PERCEPCIONES_IVA',
        'IVA',
        v_cuit_clean,
        v_fecha_canonical,
        v_comprobante_norm
      )::text;

    END IF;

    -- â”€â”€â”€ CLASIFICACIÃ“N: EXACT_DUPLICATE / POSSIBLE_AMENDMENT / ACCEPTED â”€â”€â”€â”€
    -- A. EXISTS exact: organization_id + identity_key + fiscal_fingerprint => EXACT_DUPLICATE
    -- B. EXISTS identity (sin fingerprint coincidente)                      => POSSIBLE_AMENDMENT
    -- C. No existe identity                                                  => ACCEPTED
    -- NO comparar solo contra versiÃ³n mÃ¡s reciente.

    SELECT EXISTS (
      SELECT 1 FROM public.eco_normalized_records
      WHERE organization_id = v_org_id
        AND identity_key = v_computed_identity_key
        AND fiscal_fingerprint = v_computed_fingerprint
    ) INTO v_is_exact_duplicate;

    IF v_is_exact_duplicate THEN
      v_computed_status := 'EXACT_DUPLICATE';
    ELSE
      SELECT EXISTS (
        SELECT 1 FROM public.eco_normalized_records
        WHERE organization_id = v_org_id
          AND identity_key = v_computed_identity_key
      ) INTO v_is_amendment;

      IF v_is_amendment THEN
        v_computed_status := 'POSSIBLE_AMENDMENT';
      ELSE
        v_computed_status := 'ACCEPTED';
      END IF;
    END IF;

    -- â”€â”€â”€ REGISTRAR FILA (SIEMPRE: ACCEPTED / INVALID / EXACT_DUPLICATE / POSSIBLE_AMENDMENT) â”€â”€
    INSERT INTO public.eco_import_rows (
      file_id,
      organization_id,
      source_row_number,
      raw_payload,
      parse_status,
      errors,
      warnings
    ) VALUES (
      v_file_id,
      v_org_id,
      (v_row_elem->>'sourceRowNumber')::INT,
      v_row_elem->'rawRow',
      v_computed_status,
      COALESCE(v_row_elem->'errors',   '[]'::jsonb),
      COALESCE(v_row_elem->'warnings', '[]'::jsonb)
    )
    RETURNING id INTO v_row_id;

    -- â”€â”€â”€ REGISTRO NORMALIZADO PARA ACCEPTED + POSSIBLE_AMENDMENT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    IF v_computed_status IN ('ACCEPTED', 'POSSIBLE_AMENDMENT') THEN
      v_accepted_cnt := v_accepted_cnt + 1;

      INSERT INTO public.eco_normalized_records (
        row_id,
        organization_id,
        record_type,
        status,
        identity_key,
        fiscal_fingerprint,
        fecha,
        cuit,
        razon_social,
        comprobante,
        total,
        tipo_operacion,
        categoria,
        confirmada,
        normalized_payload
      ) VALUES (
        v_row_id,
        v_org_id,
        v_source_type,           -- PERCEPCIONES_ARBA o PERCEPCIONES_IVA
        'ACCEPTED',
        v_computed_identity_key,
        v_computed_fingerprint,
        v_fecha,                 -- DATE canonical
        v_cuit_clean,            -- cuit agente, solo dÃ­gitos
        v_razon_social,          -- NULL para ARBA si no viene en payload; razonSocial para IVA
        v_comprobante_norm,      -- texto preservado
        v_monto,                 -- total percepciÃ³n
        'PERCEPCION',
        NULL,                    -- categoria: NULL por ahora
        FALSE,                   -- confirmada: FALSE por defecto
        v_norm                   -- normalizedData completo
      )
      RETURNING id INTO v_record_id;

      -- POSSIBLE_AMENDMENT genera issue adicional
      IF v_computed_status = 'POSSIBLE_AMENDMENT' THEN
        v_issue_cnt := v_issue_cnt + 1;

        INSERT INTO public.eco_import_issues (
          organization_id,
          import_id,
          row_id,
          record_id,
          issue_type,
          message,
          details
        ) VALUES (
          v_org_id,
          p_import_id,
          v_row_id,
          v_record_id,
          'AMENDMENT_DETECTED',
          'Se detectÃ³ una modificaciÃ³n en el monto de una percepciÃ³n existente',
          -- Solo informaciÃ³n segura, no hashes del frontend
          jsonb_build_object(
            'source_type',         v_source_type,
            'computedFingerprint', v_computed_fingerprint
          )
        );
      END IF;

    ELSIF v_computed_status = 'EXACT_DUPLICATE' THEN
      v_duplicate_cnt := v_duplicate_cnt + 1;
    END IF;

  END LOOP;

  -- ============================================================
  -- Â§ ESTADO FINAL Y CONTADORES
  -- POSSIBLE_AMENDMENT cuenta como accepted + issue.
  -- issue_rows > 0 => COMPLETED_WITH_ISSUES; else => COMPLETED
  -- ============================================================
  UPDATE public.eco_source_imports
  SET
    status        = CASE WHEN v_issue_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
    total_rows    = v_total_cnt,
    accepted_rows = v_accepted_cnt,
    invalid_rows  = v_invalid_cnt,
    duplicate_rows= v_duplicate_cnt,
    completed_at  = now()
  WHERE id = p_import_id;

  -- ============================================================
  -- Â§ AUDIT â€” esquema real de eco_audit_events
  -- Solo columnas existentes: organization_id, event_type
  -- NO se inventan columnas adicionales
  -- ============================================================
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'IMPORT_COMPLETED');

  -- ============================================================
  -- Â§ RESPUESTA
  -- ============================================================
  RETURN jsonb_build_object(
    'import_id',    p_import_id,
    'total_rows',   v_total_cnt,
    'accepted_rows',v_accepted_cnt,
    'invalid_rows', v_invalid_cnt,
    'duplicate_rows',v_duplicate_cnt,
    'issue_rows',   v_issue_cnt,
    'status',       CASE WHEN v_issue_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
  );

END;
$$;
CREATE OR REPLACE FUNCTION public.persist_financial_movements_batch(
    p_import_id UUID,
    p_file_info JSONB,
    p_staged_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_org_id UUID;

    v_import_record RECORD;
    v_existing_successful_cnt INT := 0;
    v_file_id UUID;
    v_hash TEXT;
    v_filename TEXT;
    v_size BIGINT;
    v_mime TEXT;
    v_storage_path TEXT;
    v_row JSONB;
    v_norm JSONB;
    v_is_invalid BOOLEAN;
    v_invalid_reason TEXT;
    v_total_cnt INT := 0;
    v_accepted_cnt INT := 0;
    v_invalid_cnt INT := 0;
    v_duplicate_cnt INT := 0;
    v_fecha DATE;
    v_fecha_valor DATE;
    v_referencia TEXT;
    v_saldo NUMERIC(15,2);
    v_monto NUMERIC(15,2);
    v_tipo TEXT;
    v_account_id TEXT;
    v_descripcion TEXT;
    v_periodo TEXT;
    v_computed_identity_key TEXT;
    v_computed_fingerprint TEXT;
    v_existing_mvmt_id UUID;
    v_row_status TEXT;
    v_neto NUMERIC(15,2);
    v_fecha_raw TEXT;
    v_fecha_valor_raw TEXT;
    v_row_id UUID;
BEGIN
  PERFORM private.require_039_batch(p_import_id,ARRAY['BANCO','SUELDO']);
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;



    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    IF v_import_record.status NOT IN ('PENDING', 'PROCESSING', 'COMPLETED_WITH_ISSUES') THEN
        RAISE EXCEPTION 'Import no estÃ¡ en estado vÃ¡lido para procesamiento';
    END IF;

    IF jsonb_array_length(p_staged_rows) > 500 THEN
        RAISE EXCEPTION 'Batch size exceeds 500 rows limit';
    END IF;

    v_hash := p_file_info->>'sha256_hash';
    IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
        RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
    END IF;

    v_filename := TRIM(COALESCE(p_file_info->>'original_name', ''));
    v_size := (p_file_info->>'size_bytes')::BIGINT;
    v_mime := p_file_info->>'mime_type';
    v_storage_path := p_file_info->>'storage_path';

    v_file_id := private.reuse_039c_file(p_import_id,v_hash);
    IF v_file_id IS NULL AND (v_storage_path IS NULL OR split_part(v_storage_path,'/',1)<>v_org_id::TEXT
      OR split_part(v_storage_path,'/',2)<>p_import_id::TEXT) THEN RAISE EXCEPTION 'Invalid storage path'; END IF;
    -- 3. Only insert if truly no source_file exists for this (organization_id, sha256_hash)
    IF v_file_id IS NULL THEN
        INSERT INTO public.eco_source_files (
            import_id,
            organization_id,
            original_name,
            storage_path,
            mime_type,
            size_bytes,
            sha256_hash,
            source_type
        ) VALUES (
            p_import_id,
            v_org_id,
            v_filename,
            v_storage_path,
            v_mime,
            v_size,
            v_hash,
            v_import_record.source_type
        ) RETURNING id INTO v_file_id;
    END IF;

    UPDATE public.eco_source_imports SET status = 'PROCESSING' WHERE id = p_import_id;

    -- Row processing loop
    FOR v_row IN SELECT * FROM jsonb_array_elements(p_staged_rows)
    LOOP
        v_fecha := NULL;
        v_fecha_valor := NULL;
        v_referencia := NULL;
        v_saldo := NULL;
        v_monto := NULL;
        v_tipo := NULL;
        v_account_id := NULL;
        v_descripcion := NULL;
        v_periodo := NULL;
        v_computed_identity_key := NULL;
        v_computed_fingerprint := NULL;
        v_is_invalid := FALSE;
        v_invalid_reason := 'Fila invÃ¡lida o incompleta';
        v_row_status := 'ACCEPTED';
        v_row_id := NULL;

        v_total_cnt := v_total_cnt + 1;
        v_norm := v_row->'normalizedData';

        IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' THEN
            v_is_invalid := TRUE;
            v_invalid_reason := 'Fila sin datos normalizados';
        ELSIF v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0 THEN
            v_is_invalid := TRUE;
            v_invalid_reason := TRIM(BOTH '"' FROM (v_row->'errors'->0)::text);
        END IF;

        IF NOT v_is_invalid THEN
            BEGIN
                IF v_import_record.source_type = 'PAYROLL_ACONPY' THEN
                    v_periodo := TRIM(COALESCE(v_norm->>'periodo', ''));
                    IF v_periodo ~ '^(0[1-9]|1[0-2])/\d{4}$' THEN
                        v_periodo := RIGHT(v_periodo, 4) || '-' || LEFT(v_periodo, 2);
                    ELSIF v_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
                        -- YYYY-MM
                    ELSE
                        v_is_invalid := TRUE;
                        v_invalid_reason := 'Formato de periodo invÃ¡lido: ' || COALESCE(v_periodo, 'NULL');
                    END IF;

                    IF NOT v_is_invalid THEN
                        v_computed_identity_key := jsonb_build_array('PAYROLL_ACONPY', v_periodo)::text;
                        v_neto := ROUND(COALESCE(NULLIF(v_norm->>'sueldoNeto', ''), '0')::numeric, 2);
                        v_computed_fingerprint := ENCODE(extensions.digest(
                            TO_CHAR(v_neto, 'FM999999999999990.00'), 'sha256'
                        ), 'hex');
                    END IF;

                ELSIF v_import_record.source_type = 'BANK_STATEMENT_BBVA' THEN
                    v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));
                    IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_fecha := v_fecha_raw::DATE;
                    ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN
                        v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
                    ELSIF v_fecha_raw ~ '^\d{2}-\d{2}-\d{4}$' THEN
                        v_fecha := TO_DATE(v_fecha_raw, 'DD-MM-YYYY');
                    ELSE
                        v_is_invalid := TRUE;
                        v_invalid_reason := 'Formato de fecha invÃ¡lido o no reconocido: ' || COALESCE(v_fecha_raw, 'NULL');
                    END IF;

                    v_fecha_valor_raw := TRIM(COALESCE(v_norm->>'fechaValor', ''));
                    IF v_fecha_valor_raw = '' THEN
                        v_fecha_valor := v_fecha;
                    ELSIF v_fecha_valor_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN
                        v_fecha_valor := v_fecha_valor_raw::DATE;
                    ELSIF v_fecha_valor_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN
                        v_fecha_valor := TO_DATE(v_fecha_valor_raw, 'DD/MM/YYYY');
                    ELSIF v_fecha_valor_raw ~ '^\d{2}-\d{2}-\d{4}$' THEN
                        v_fecha_valor := TO_DATE(v_fecha_valor_raw, 'DD-MM-YYYY');
                    ELSE
                        v_fecha_valor := v_fecha;
                    END IF;

                    v_referencia := TRIM(COALESCE(v_norm->>'referencia', ''));

                    IF NULLIF(TRIM(v_norm->>'saldo'), '') IS NOT NULL THEN
                        v_saldo := ROUND((v_norm->>'saldo')::numeric, 2);
                    END IF;

                    IF NULLIF(TRIM(v_norm->>'monto'), '') IS NOT NULL THEN
                        v_monto := ROUND((v_norm->>'monto')::numeric, 2);
                    ELSE
                        v_is_invalid := TRUE;
                        v_invalid_reason := 'Importe vacÃ­o o invÃ¡lido';
                    END IF;

                    v_tipo := v_norm->>'tipo';
                    v_account_id := COALESCE(v_norm->>'accountIdentifier', '');
                    v_descripcion := TRIM(COALESCE(v_norm->>'descripcion', ''));

                    IF NOT v_is_invalid THEN
                        IF v_referencia != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), v_referencia, v_monto, v_tipo)::text;
                        ELSIF v_saldo IS NOT NULL THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REFERENCE', v_saldo, v_monto, v_tipo)::text;
                        ELSIF v_descripcion != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REF_NO_SALDO', v_descripcion, v_monto, v_tipo)::text;
                        ELSE
                            v_is_invalid := TRUE;
                            v_invalid_reason := 'Fila sin referencia, saldo ni descripciÃ³n para identificaciÃ³n';
                        END IF;
                    END IF;

                    IF NOT v_is_invalid THEN
                        v_computed_fingerprint := ENCODE(extensions.digest(
                            v_descripcion || '|' || TO_CHAR(v_fecha_valor, 'YYYY-MM-DD'), 'sha256'
                        ), 'hex');
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_is_invalid := TRUE;
                v_invalid_reason := 'Error de procesamiento: ' || SQLERRM;
            END;
        END IF;

        IF v_is_invalid THEN
            v_row_status := 'INVALID';
        END IF;

        -- 1. Insert row log entry FIRST to satisfy fk_fm_row NOT NULL constraint
        INSERT INTO public.eco_import_rows (
            file_id,
            organization_id,
            source_row_number,
            raw_payload,
            parse_status
        ) VALUES (
            v_file_id,
            v_org_id,
            (v_row->>'sourceRowNumber')::INT,
            v_row->'rawRow',
            v_row_status
        ) RETURNING id INTO v_row_id;

        IF v_is_invalid THEN
            v_invalid_cnt := v_invalid_cnt + 1;

            INSERT INTO public.eco_import_issues (
                organization_id,
                import_id,
                row_id,
                issue_type,
                message,
                details,
                status
            ) VALUES (
                v_org_id,
                p_import_id,
                v_row_id,
                'PARSE_ERROR',
                'Fila invÃ¡lida o incompleta',
                jsonb_build_object('technical_error', v_invalid_reason),
                'OPEN'
            );
        ELSE
            -- Check row duplication
            SELECT id INTO v_existing_mvmt_id
            FROM public.eco_financial_movements
            WHERE organization_id = v_org_id
              AND identity_key = v_computed_identity_key
              AND deleted_at IS NULL LIMIT 1;

            IF v_existing_mvmt_id IS NOT NULL THEN
                v_duplicate_cnt := v_duplicate_cnt + 1;
                UPDATE public.eco_import_rows SET parse_status = 'EXACT_DUPLICATE' WHERE id = v_row_id;
            ELSE
                INSERT INTO public.eco_financial_movements (
                    organization_id,
                    import_id,
                    row_id,
                    operation_type,
                    source_type,
                    fecha,
                    fecha_valor,
                    periodo,
                    descripcion,
                    referencia,
                    monto,
                    movement_type,
                    saldo,
                    identity_key,
                    financial_fingerprint,
                    normalized_payload
                ) VALUES (
                    v_org_id,
                    p_import_id,
                    v_row_id,
                    v_import_record.operation_type,
                    v_import_record.source_type,
                    v_fecha,
                    v_fecha_valor,
                    v_periodo,
                    v_descripcion,
                    v_referencia,
                    v_monto,
                    v_tipo,
                    v_saldo,
                    v_computed_identity_key,
                    v_computed_fingerprint,
                    v_norm
                );
                v_accepted_cnt := v_accepted_cnt + 1;
            END IF;
        END IF;
    END LOOP;

    -- Update final import attempt status
    UPDATE public.eco_source_imports
    SET status = CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
        total_rows = v_total_cnt,
        accepted_rows = v_accepted_cnt,
        invalid_rows = v_invalid_cnt,
        duplicate_rows = v_duplicate_cnt,
        completed_at = now()
    WHERE id = p_import_id;

    RETURN jsonb_build_object(
        'import_id', p_import_id,
        'file_id', v_file_id,
        'total_rows', v_total_cnt,
        'accepted_rows', v_accepted_cnt,
        'invalid_rows', v_invalid_cnt,
        'duplicate_rows', v_duplicate_cnt
    );
END;
$$;
CREATE OR REPLACE FUNCTION public.check_file_importable(p_sha256_hash TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_existing_successful_file_id UUID;
  v_retry_candidate_import_id UUID;
  v_existing_file_id UUID;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('IMPORT_CREATE');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF p_sha256_hash IS NULL OR NOT (p_sha256_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid SHA-256 hash format';
  END IF;

  -- 1. Block file re-upload ONLY IF a previous import produced a successful business result (accepted_rows > 0)
  SELECT sf.id INTO v_existing_successful_file_id
  FROM public.eco_source_files sf
  JOIN public.eco_source_imports si ON si.id = sf.import_id
  WHERE sf.organization_id = v_org_id
    AND sf.sha256_hash = p_sha256_hash
    AND (COALESCE(si.accepted_rows, 0) > 0
      OR EXISTS (SELECT 1 FROM public.eco_source_imports retry WHERE retry.retry_of_import_id=si.id AND COALESCE(retry.accepted_rows,0)>0)
      OR EXISTS (SELECT 1 FROM public.eco_normalized_records nr JOIN public.eco_import_rows ir ON ir.id=nr.row_id WHERE ir.file_id=sf.id)
      OR EXISTS (SELECT 1 FROM public.eco_financial_movements fm JOIN public.eco_import_rows ir ON ir.id=fm.row_id WHERE ir.file_id=sf.id))
  LIMIT 1;

  IF v_existing_successful_file_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'importable', false,
      'reason', 'FILE_ALREADY_EXISTS',
      'existing_file_id', v_existing_successful_file_id
    );
  END IF;

  -- 2. Check if there is an existing source file and failed import candidate for retry (accepted_rows = 0)
  SELECT sf.id, sf.import_id INTO v_existing_file_id, v_retry_candidate_import_id
  FROM public.eco_source_files sf
  JOIN public.eco_source_imports si ON si.id = sf.import_id
  WHERE sf.organization_id = v_org_id
    AND sf.sha256_hash = p_sha256_hash
    AND COALESCE(si.accepted_rows, 0) = 0
  ORDER BY sf.created_at ASC
  LIMIT 1;

  IF v_existing_file_id IS NOT NULL AND v_retry_candidate_import_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'importable', true,
      'retry_available', true,
      'retry_candidate_import_id', v_retry_candidate_import_id,
      'existing_file_id', v_existing_file_id
    );
  END IF;

  -- 3. Brand new file
  RETURN jsonb_build_object(
    'importable', true,
    'retry_available', false
  );
END;
$$;
-- BEGIN GENERATED 039C FISCAL SEED
DO $seed$
DECLARE cap UUID; r RECORD;
BEGIN
 INSERT INTO public.eco_capabilities(code,description,scope,is_active,delegation_class)
 VALUES('FISCAL_DOCUMENT_IMPORT','Importar comprobantes fiscales','ORGANIZATION',TRUE,'ORGANIZATION_DELEGABLE') RETURNING id INTO cap;
 FOR r IN INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
  SELECT id,cap FROM public.eco_role_templates WHERE code IN ('MICA_ORG_ADMIN','MICA_ACCOUNTANT','MICA_IMPORT_OPERATOR')
  RETURNING * LOOP
  INSERT INTO private.migration_039c_grants VALUES('public.eco_role_template_capabilities',to_jsonb(r));
 END LOOP;
 FOR r IN INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
  SELECT t.id,cap FROM public.eco_role_templates t WHERE t.code='ACCOUNTING_SUPERADMIN' OR t.id IN (
   SELECT a.role_template_id FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id)
  RETURNING * LOOP
  INSERT INTO private.migration_039c_grants VALUES('public.eco_platform_role_org_capabilities',to_jsonb(r));
 END LOOP;
END; $seed$;
-- END GENERATED 039C FISCAL SEED
REVOKE ALL ON FUNCTION private.reuse_039c_file(UUID,TEXT) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.mica_import_file_status(UUID),public.mica_manual_records(TEXT,UUID,UUID,JSONB),public.mica_invitation(TEXT,UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mica_import_file_status(UUID),public.mica_manual_records(TEXT,UUID,UUID,JSONB),public.mica_invitation(TEXT,UUID,JSONB) TO authenticated;
-- Empty definition marks newly introduced functions; DOWN checks drift before dropping.
INSERT INTO private.migration_039c_functions(signature,definition) VALUES
 ('private.reuse_039c_file(uuid,text)',''),('public.mica_import_file_status(uuid)',''),
 ('public.mica_manual_records(text,uuid,uuid,jsonb)',''),('public.mica_invitation(text,uuid,jsonb)','');
UPDATE private.migration_039c_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
COMMIT;
