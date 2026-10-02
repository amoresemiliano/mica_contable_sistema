-- 039 MICA only. Prepared for manual review; no SQL executed by tooling.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
  IF to_regclass('private.migration_039_functions') IS NOT NULL THEN RAISE EXCEPTION '039 already installed'; END IF;
  IF to_regprocedure('public.mica_admin_apply(text,jsonb)') IS NULL THEN RAISE EXCEPTION '038 required'; END IF;
  IF to_regclass('private.migration_038_backup') IS NULL THEN RAISE EXCEPTION '038 backup required'; END IF;
  FOR r IN SELECT unnest(ARRAY['private.can_operate_mica_org(uuid,text)',
    'public.can_operate_mica_org(uuid,text)','private.active_org_id()',
    'private.org_id()','private.current_profile_id()']) AS signature LOOP
    IF to_regprocedure(r.signature) IS NULL THEN RAISE EXCEPTION '039 missing dependency: %',r.signature; END IF;
  END LOOP;
  FOR r IN SELECT * FROM (VALUES ('public.create_import(text,text)','44af4071c2e6efa61c9e34b5201560ee'),
('public.persist_import_batch(uuid,jsonb,jsonb)','4ec257f1deccb099ee3ca43485ad9f40'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','5e51b97b79bfcd556f91a93bca288488'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','32787b5f20ec6781b7c4c51b221f6faa'),
('public.request_failed_import_retry(uuid)','288284ae2611572da43cdd744c58cf1c'),
('public.check_file_importable(text)','11ed6fc83312f88a5d44ec1426765bbe'),
('public.soft_delete_normalized_record(uuid)','c90cb428d54baf598bb4912dcb4d3122'),
('public.soft_delete_financial_movement(uuid)','3a7c75142ac68f354354c09d3fa2214a'),
('public.restore_normalized_record(uuid)','c5d545377a4d27174e718cb3d3eff52a'),
('public.restore_financial_movement(uuid)','9d7a43998cc2cc535ace9764c6a29103'),
('public.update_record_classification(uuid,uuid,uuid)','e3d9687abd70d9974d03668101580ac9'),
('public.update_movement_classification(uuid,uuid,uuid)','7593a3a547813b98bb5bdf1df291e177'),
('public.bulk_update_record_classification(text,date,date,uuid,uuid)','6cc0a335b007b21ded2e58e3c0f4275a'),
('public.get_active_org_iibb_rates()','b514b0f3d1f886303e3a1a7572644cd7'),
('public.get_active_normalized_records()','9dc4cb1cf48e80cce449026367585ab7'),
('public.get_active_financial_movements()','8aeed6886048ea6443b9e6e95c382977'),
('public.get_deleted_normalized_records()','be2172f131e5a008ea82dd7f44b98773'),
('public.get_deleted_financial_movements()','ee4dad2b401a152c78764eaf87217bbb')) expected(signature,hash) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
      AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
      AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
      RAISE EXCEPTION '039: LIVE body/attributes differ: %',r.signature; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM unnest(ARRAY['public.eco_normalized_records','public.eco_financial_movements','public.eco_source_imports','public.eco_source_files','public.eco_import_rows','public.eco_import_issues','public.eco_org_tax_categories','public.eco_org_economic_activities','public.eco_org_activity_iibb_rates']) AS target(name)
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass(target.name) AND attname='organization_id' AND NOT attisdropped)) THEN
    RAISE EXCEPTION '039: dataset organization_id contract missing'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,
  owner_name TEXT NOT NULL,acl ACLITEM[],installed_definition TEXT,installed_acl ACLITEM[]);
ALTER TABLE private.migration_039_functions ENABLE ROW LEVEL SECURITY;
INSERT INTO private.migration_039_functions(signature,definition,owner_name,acl)
SELECT expected.signature,pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl
FROM (VALUES ('public.create_import(text,text)','44af4071c2e6efa61c9e34b5201560ee'),
('public.persist_import_batch(uuid,jsonb,jsonb)','4ec257f1deccb099ee3ca43485ad9f40'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','5e51b97b79bfcd556f91a93bca288488'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','32787b5f20ec6781b7c4c51b221f6faa'),
('public.request_failed_import_retry(uuid)','288284ae2611572da43cdd744c58cf1c'),
('public.check_file_importable(text)','11ed6fc83312f88a5d44ec1426765bbe'),
('public.soft_delete_normalized_record(uuid)','c90cb428d54baf598bb4912dcb4d3122'),
('public.soft_delete_financial_movement(uuid)','3a7c75142ac68f354354c09d3fa2214a'),
('public.restore_normalized_record(uuid)','c5d545377a4d27174e718cb3d3eff52a'),
('public.restore_financial_movement(uuid)','9d7a43998cc2cc535ace9764c6a29103'),
('public.update_record_classification(uuid,uuid,uuid)','e3d9687abd70d9974d03668101580ac9'),
('public.update_movement_classification(uuid,uuid,uuid)','7593a3a547813b98bb5bdf1df291e177'),
('public.bulk_update_record_classification(text,date,date,uuid,uuid)','6cc0a335b007b21ded2e58e3c0f4275a'),
('public.get_active_org_iibb_rates()','b514b0f3d1f886303e3a1a7572644cd7'),
('public.get_active_normalized_records()','9dc4cb1cf48e80cce449026367585ab7'),
('public.get_active_financial_movements()','8aeed6886048ea6443b9e6e95c382977'),
('public.get_deleted_normalized_records()','be2172f131e5a008ea82dd7f44b98773'),
('public.get_deleted_financial_movements()','ee4dad2b401a152c78764eaf87217bbb')) expected(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);

CREATE FUNCTION private.require_039_action(p_code TEXT)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_org UUID:=private.active_org_id();
BEGIN
  IF NOT COALESCE(private.can_operate_mica_org(v_org,p_code),FALSE) THEN
    RAISE EXCEPTION '039: capability % denied in confirmed tenant context',p_code USING ERRCODE='42501'; END IF;
  RETURN v_org;
END; $$;
CREATE FUNCTION private.require_039_import(p_source TEXT,p_operation TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW');
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
CREATE FUNCTION private.require_039_batch(p_import UUID,p_operations TEXT[])
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_row RECORD;
BEGIN
  SELECT source_type,operation_type INTO v_row FROM public.eco_source_imports
    WHERE id=p_import AND organization_id=private.active_org_id();
  IF NOT FOUND OR NOT (v_row.operation_type=ANY(p_operations)) THEN
    RAISE EXCEPTION '039: import outside context or wrong endpoint' USING ERRCODE='42501'; END IF;
  PERFORM private.require_039_import(v_row.source_type,v_row.operation_type);
END; $$;
CREATE FUNCTION public.mica_storage_import_allowed(p_name TEXT,p_action TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_row RECORD;
BEGIN
  SELECT * INTO v_row FROM public.eco_source_imports
    WHERE id::TEXT=split_part(p_name,'/',2) AND organization_id::TEXT=split_part(p_name,'/',1)
      AND organization_id=private.active_org_id();
  IF NOT FOUND THEN RETURN FALSE; END IF;
  IF p_action='read' AND private.can_operate_mica_org(v_row.organization_id,'IMPORT_VIEW') THEN RETURN TRUE; END IF;
  IF v_row.created_by IS DISTINCT FROM private.current_profile_id() THEN RETURN FALSE; END IF;
  IF p_action NOT IN ('read','write','delete') OR p_action IS NULL THEN RETURN FALSE; END IF;
  IF p_action='delete' AND COALESCE(v_row.accepted_rows,0)>0 THEN RETURN FALSE; END IF;
  PERFORM private.require_039_import(v_row.source_type,v_row.operation_type);
  RETURN TRUE;
EXCEPTION WHEN insufficient_privilege THEN RETURN FALSE;
END; $$;

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
CREATE OR REPLACE FUNCTION public.create_import(
  p_source_type TEXT DEFAULT 'ARCA_RECIBIDOS',
  p_operation_type TEXT DEFAULT 'COMPRA'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;

  v_caller_id UUID;
  v_import_id UUID;
BEGIN
  PERFORM private.require_039_import(p_source_type,p_operation_type);
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;



  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Profile not found';
  END IF;

  INSERT INTO public.eco_source_imports (
    organization_id,
    source_type,
    operation_type,
    status,
    created_by
  ) VALUES (
    v_org_id,
    p_source_type,
    p_operation_type,
    'PENDING',
    v_caller_id
  )
  RETURNING id INTO v_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'IMPORT_CREATED');

  RETURN jsonb_build_object(
    'import_id', v_import_id,
    'organization_id', v_org_id,
    'storage_prefix', v_org_id::text || '/' || v_import_id::text
  );
END;
$$;

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
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
  IF NOT (v_storage_path LIKE v_expected_prefix || '%') THEN
    RAISE EXCEPTION 'Invalid storage path: Must start with %', v_expected_prefix;
  END IF;

  -- 5. Pre-check de Archivo Duplicado por Hash SHA-256
  SELECT id INTO v_existing_file_id
  FROM public.eco_source_files
  WHERE organization_id = v_org_id AND sha256_hash = v_hash;

  IF v_existing_file_id IS NOT NULL THEN
    RAISE EXCEPTION 'FILE_ALREADY_EXISTS: File with hash % already imported (File ID: %)',
      v_hash, v_existing_file_id;
  END IF;

  -- Actualizar estado a PROCESSING
  UPDATE public.eco_source_imports SET status = 'PROCESSING' WHERE id = p_import_id;

  -- 6. Registrar Archivo
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

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
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
  IF NOT (v_storage_path LIKE v_expected_prefix || '%') THEN
    RAISE EXCEPTION 'Invalid storage path: Must start with %', v_expected_prefix;
  END IF;

  -- Pre-check duplicado por organization_id + sha256_hash
  SELECT id INTO v_existing_file_id
  FROM public.eco_source_files
  WHERE organization_id = v_org_id AND sha256_hash = v_hash;

  IF v_existing_file_id IS NOT NULL THEN
    RAISE EXCEPTION 'FILE_ALREADY_EXISTS: File with hash % already imported (File ID: %)',
      v_hash, v_existing_file_id;
  END IF;

  -- ============================================================
  -- Â§ TRANSICIÃ“N ATÃ“MICA: PENDING â†’ PROCESSING
  -- ============================================================
  UPDATE public.eco_source_imports
  SET status = 'PROCESSING'
  WHERE id = p_import_id;

  -- ============================================================
  -- Â§ REGISTRAR METADATOS DE ARCHIVO EN eco_source_files
  -- ============================================================
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

-- Reviewed baseline: 029_fix_import_row_duplicate_status.sql
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

    -- Check existing file for sha256 duplicate: Only block if duplicate belongs to an import with accepted business rows
    SELECT COUNT(*) INTO v_existing_successful_cnt
    FROM public.eco_source_files sf
    JOIN public.eco_source_imports si ON si.id = sf.import_id
    WHERE sf.organization_id = v_org_id
      AND sf.sha256_hash = v_hash
      AND sf.import_id != p_import_id
      AND si.id != COALESCE(v_import_record.retry_of_import_id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND COALESCE(si.accepted_rows, 0) > 0;

    IF v_existing_successful_cnt > 0 THEN
        RAISE EXCEPTION 'FILE_ALREADY_EXISTS: File with hash % already successfully imported', v_hash;
    END IF;

    -- 1. Fetch existing file_id linked to current import_id OR retry_of_import_id
    SELECT id INTO v_file_id
    FROM public.eco_source_files
    WHERE (import_id = p_import_id OR (v_import_record.retry_of_import_id IS NOT NULL AND import_id = v_import_record.retry_of_import_id))
      AND organization_id = v_org_id
    ORDER BY created_at ASC LIMIT 1;

    -- 2. Defensive fallback: If not found by direct lineage, search by (org_id, sha256_hash)
    IF v_file_id IS NULL THEN
        SELECT sf.id INTO v_file_id
        FROM public.eco_source_files sf
        WHERE sf.organization_id = v_org_id
          AND sf.sha256_hash = v_hash
        ORDER BY sf.created_at ASC LIMIT 1;
    END IF;

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

-- Reviewed baseline: 027_fix_bbva_import_and_retry.sql
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
        WHERE sf.import_id = p_import_id AND sf.organization_id = v_org_id AND nr.deleted_at IS NULL;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_financial_movements
        WHERE import_id = p_import_id AND organization_id = v_org_id AND deleted_at IS NULL;
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
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id AND nr.deleted_at IS NULL;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_financial_movements fm
        JOIN public.eco_source_imports si ON si.id = fm.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id AND fm.deleted_at IS NULL;
    END IF;

    IF v_retry_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: A retry attempt for this import already has % downstream records persisted', v_retry_downstream_count;
    END IF;

    SELECT id INTO v_profile_id
    FROM public.eco_user_profiles
    WHERE auth_user_id = auth.uid() AND organization_id = v_org_id LIMIT 1;

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
        COALESCE(v_profile_id, v_import_record.created_by)
    );

    -- Log audit event
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED');

    RETURN jsonb_build_object(
        'status', 'RETRY_CREATED',
        'original_import_id', p_import_id,
        'new_import_id', v_new_import_id,
        'source_file_reused', v_orig_file IS NOT NULL,
        'storage_path', v_orig_file.storage_path,
        'message', 'Retry import attempt created successfully'
    );
END;
$$;

-- Reviewed baseline: 028_fix_source_file_reuse_and_retry_flow.sql
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
    AND COALESCE(si.accepted_rows, 0) > 0
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

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
CREATE OR REPLACE FUNCTION public.soft_delete_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_SOFT_DELETE');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'SOFT_DELETE_RECORD');
  END IF;
END;
$$;

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
CREATE OR REPLACE FUNCTION public.soft_delete_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_SOFT_DELETE');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'SOFT_DELETE_MOVEMENT');
  END IF;
END;
$$;

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
CREATE OR REPLACE FUNCTION public.restore_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_RESTORE');
  v_org_id := private.org_id();

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

-- Reviewed baseline: 018_superadmin_operational_capabilities.sql
CREATE OR REPLACE FUNCTION public.restore_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_RESTORE');
  v_org_id := private.org_id();

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

-- Reviewed baseline: 030_separate_assignment_and_activation.sql
CREATE OR REPLACE FUNCTION public.update_record_classification(
  p_record_id UUID,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_CLASSIFY');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  -- Validar que la categorÃ­a pertenezca a la org y estÃ© activa
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE;

    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  -- Validar que la actividad pertenezca a la org y estÃ© activa
  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE;

    IF v_valid_activity IS NOT TRUE THEN
      RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET category_id = p_category_id,
      activity_id = p_activity_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;

-- Reviewed baseline: 030_separate_assignment_and_activation.sql
CREATE OR REPLACE FUNCTION public.update_movement_classification(
  p_movement_id UUID,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_CLASSIFY');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE;
    IF v_valid_category IS NOT TRUE THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE;
    IF v_valid_activity IS NOT TRUE THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET category_id = p_category_id,
      activity_id = p_activity_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;

-- Reviewed baseline: 030_separate_assignment_and_activation.sql
CREATE OR REPLACE FUNCTION public.bulk_update_record_classification(
  p_cuit TEXT,
  p_date_from DATE,
  p_date_to DATE,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
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
$$;

-- Reviewed baseline: 014_consolidation_crud_categorization.sql
CREATE OR REPLACE FUNCTION public.get_active_normalized_records()
RETURNS SETOF public.eco_normalized_records
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_normalized_records
  WHERE organization_id = private.require_039_action('RECORD_VIEW')
    AND deleted_at IS NULL
  ORDER BY fecha DESC, created_at DESC;
$$;

-- Reviewed baseline: 014_consolidation_crud_categorization.sql
CREATE OR REPLACE FUNCTION public.get_active_financial_movements()
RETURNS SETOF public.eco_financial_movements
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_financial_movements
  WHERE organization_id = private.require_039_action('RECORD_VIEW')
    AND deleted_at IS NULL
  ORDER BY fecha DESC, created_at DESC;
$$;

-- Reviewed baseline: 014_consolidation_crud_categorization.sql
CREATE OR REPLACE FUNCTION public.get_deleted_normalized_records()
RETURNS SETOF public.eco_normalized_records
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_normalized_records
  WHERE organization_id = private.require_039_action('RECORD_VIEW')
    AND deleted_at IS NOT NULL
  ORDER BY deleted_at DESC, fecha DESC;
$$;

-- Reviewed baseline: 014_consolidation_crud_categorization.sql
CREATE OR REPLACE FUNCTION public.get_deleted_financial_movements()
RETURNS SETOF public.eco_financial_movements
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_financial_movements
  WHERE organization_id = private.require_039_action('RECORD_VIEW')
    AND deleted_at IS NOT NULL
  ORDER BY deleted_at DESC, fecha DESC;
$$;
-- Reviewed baseline: 014_consolidation_crud_categorization.sql
CREATE OR REPLACE FUNCTION public.get_active_org_iibb_rates()
RETURNS SETOF public.eco_org_activity_iibb_rates
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_org_activity_iibb_rates
  WHERE organization_id = private.require_039_action('CATALOG_ORG_VIEW')
    AND is_active = TRUE;
$$;
CREATE POLICY guard_039_storage_read ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated USING
(bucket_id<>'eco-imports-private-staging' OR public.mica_storage_import_allowed(name,'read'));
CREATE POLICY guard_039_storage_write ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK
(bucket_id<>'eco-imports-private-staging' OR public.mica_storage_import_allowed(name,'write'));
CREATE POLICY guard_039_storage_delete ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated USING
(bucket_id<>'eco-imports-private-staging' OR public.mica_storage_import_allowed(name,'delete'));

CREATE POLICY guard_039_read ON public.eco_normalized_records AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'RECORD_VIEW'));
CREATE POLICY guard_039_read ON public.eco_financial_movements AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'RECORD_VIEW'));
CREATE POLICY guard_039_read ON public.eco_source_imports AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'IMPORT_VIEW'));
CREATE POLICY guard_039_read ON public.eco_source_files AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'IMPORT_VIEW'));
CREATE POLICY guard_039_read ON public.eco_import_rows AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'IMPORT_VIEW'));
CREATE POLICY guard_039_read ON public.eco_import_issues AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'IMPORT_VIEW'));

CREATE POLICY guard_039_read ON public.eco_org_tax_categories AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'ORG_VIEW'));
CREATE POLICY guard_039_read ON public.eco_org_economic_activities AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'ORG_VIEW'));
CREATE POLICY guard_039_read ON public.eco_org_activity_iibb_rates AS RESTRICTIVE FOR SELECT TO authenticated
USING (public.can_operate_mica_org(organization_id,'CATALOG_ORG_VIEW'));
DO $acl$
DECLARE r RECORD; a RECORD; who TEXT;
BEGIN
  FOR a IN SELECT DISTINCT grantee FROM pg_class c,
    LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) WHERE c.oid='private.migration_039_functions'::regclass AND grantee<>c.relowner LOOP
    who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
    EXECUTE format('REVOKE ALL ON TABLE private.migration_039_functions FROM %s',who);
  END LOOP;
  FOR r IN SELECT signature FROM private.migration_039_functions UNION ALL SELECT unnest(ARRAY[
    'private.require_039_action(text)','private.require_039_import(text,text)','private.require_039_batch(uuid,text[])',
    'public.mica_storage_import_allowed(text,text)']) LOOP
    FOR a IN SELECT DISTINCT grantee FROM pg_proc p,
      LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) WHERE p.oid=to_regprocedure(r.signature) AND grantee<>p.proowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',r.signature,who);
    END LOOP;
    IF r.signature LIKE 'public.%' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',r.signature); END IF;
  END LOOP;
  UPDATE private.migration_039_functions b SET installed_definition=pg_get_functiondef(p.oid),installed_acl=p.proacl
    FROM pg_proc p WHERE p.oid=to_regprocedure(b.signature);
END; $acl$;
COMMIT;
