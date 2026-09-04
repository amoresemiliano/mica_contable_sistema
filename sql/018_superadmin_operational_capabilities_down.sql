BEGIN;

-- ============================================================
-- MIGRATION 018 DOWN: RESTORE PRE-M018 RPC DEFINITIONS
-- ============================================================

-- 1. RESTORE IMPORT & PERSISTENCE RPCs

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
  v_caller_role TEXT;
  v_caller_id UUID;
  v_import_id UUID;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role';
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
  v_caller_role TEXT;
  v_import_record RECORD;
  v_existing_file_id UUID;
  v_file_id UUID;
  v_row_record JSONB;
  v_norm JSONB;
  v_row_id UUID;
  v_record_id UUID;

  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;

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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role';
  END IF;

  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds maximum allowed limit of 500 rows';
  END IF;

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

  v_hash := p_file_info->>'sha256_hash';
  IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
  END IF;

  v_filename := p_file_info->>'original_name';
  IF v_filename IS NULL OR length(trim(v_filename)) = 0 THEN
    RAISE EXCEPTION 'Original filename is required';
  END IF;

  v_size := (p_file_info->>'size_bytes')::BIGINT;
  IF v_size IS NULL OR v_size <= 0 THEN
    RAISE EXCEPTION 'File size must be greater than zero';
  END IF;

  v_mime := p_file_info->>'mime_type';

  v_storage_path := p_file_info->>'storage_path';
  v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
  IF v_storage_path IS NULL OR NOT (v_storage_path LIKE v_expected_prefix || '%') THEN
    RAISE EXCEPTION 'Storage path must start with authorized prefix %', v_expected_prefix;
  END IF;

  SELECT id INTO v_existing_file_id
  FROM public.eco_source_files
  WHERE organization_id = v_org_id AND sha256_hash = v_hash;

  IF v_existing_file_id IS NOT NULL THEN
    RAISE EXCEPTION 'File with hash % has already been imported for this organization', v_hash;
  END IF;

  UPDATE public.eco_source_imports
  SET status = 'PROCESSING', started_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_source_files (
    organization_id, import_id, original_name, storage_path, mime_type, size_bytes, sha256_hash, source_type
  ) VALUES (
    v_org_id, p_import_id, v_filename, v_storage_path, v_mime, v_size, v_hash, v_import_record.source_type
  )
  RETURNING id INTO v_file_id;

  FOR v_row_record IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row_record->'normalizedData';

    IF v_norm IS NULL OR v_norm = 'null'::jsonb OR (v_row_record->'errors' IS NOT NULL AND jsonb_array_length(v_row_record->'errors') > 0) THEN
      v_computed_status := 'INVALID';
      v_invalid_cnt := v_invalid_cnt + 1;
    ELSE
      v_cuit_clean := regexp_replace(COALESCE(v_norm->>'cuitEmisor', v_norm->>'cuitReceptor', v_norm->>'cuit', ''), '\D', '', 'g');
      v_tipo_cbte := LPAD(COALESCE(v_norm->>'tipo_cbte', '1'), 3, '0');
      v_pdv := LPAD(COALESCE(v_norm->>'pdv', '1'), 5, '0');
      v_nro_desde := LPAD(COALESCE(v_norm->>'nroDesde', '1'), 8, '0');
      v_nro_hasta := LPAD(COALESCE(v_norm->>'nroHasta', v_norm->>'nroDesde', '1'), 8, '0');
      v_moneda := COALESCE(v_norm->>'moneda', 'PES');

      v_computed_identity_key := v_cuit_clean || ':' || v_tipo_cbte || ':' || v_pdv || ':' || v_nro_desde || ':' || v_nro_hasta;

      v_neto := COALESCE((v_norm->>'netoGravado')::NUMERIC, 0);
      v_iva := COALESCE((v_norm->>'totalIva')::NUMERIC, 0);
      v_otros := COALESCE((v_norm->>'otrosTributos')::NUMERIC, 0);
      v_exento := COALESCE((v_norm->>'exento')::NUMERIC, 0);
      v_nograv := COALESCE((v_norm->>'netoNoGravado')::NUMERIC, 0);
      v_total := COALESCE((v_norm->>'total')::NUMERIC, 0);

      v_computed_fingerprint := digest(
        (v_norm->>'fecha') || '|' ||
        trim(to_char(v_neto, 'FM999999999990.00')) || '|' ||
        trim(to_char(v_iva, 'FM999999999990.00')) || '|' ||
        trim(to_char(v_otros, 'FM999999999990.00')) || '|' ||
        trim(to_char(v_exento, 'FM999999999990.00')) || '|' ||
        trim(to_char(v_nograv, 'FM999999999990.00')) || '|' ||
        trim(to_char(v_total, 'FM999999999990.00')) || '|' ||
        v_moneda,
        'sha256'
      )::text;

      SELECT EXISTS (
        SELECT 1 FROM public.eco_normalized_records
        WHERE organization_id = v_org_id
          AND identity_key = v_computed_identity_key
          AND fiscal_fingerprint = v_computed_fingerprint
      ) INTO v_is_exact_duplicate;

      IF v_is_exact_duplicate THEN
        v_computed_status := 'EXACT_DUPLICATE';
        v_duplicate_cnt := v_duplicate_cnt + 1;
      ELSE
        SELECT EXISTS (
          SELECT 1 FROM public.eco_normalized_records
          WHERE organization_id = v_org_id
            AND identity_key = v_computed_identity_key
            AND fiscal_fingerprint != v_computed_fingerprint
        ) INTO v_is_amendment;

        IF v_is_amendment THEN
          v_computed_status := 'POSSIBLE_AMENDMENT';
          v_accepted_cnt := v_accepted_cnt + 1;
        ELSE
          v_computed_status := 'ACCEPTED';
          v_accepted_cnt := v_accepted_cnt + 1;
        END IF;
      END IF;
    END IF;

    INSERT INTO public.eco_import_rows (
      organization_id, import_id, source_row_number, raw_payload, parse_status, errors, warnings
    ) VALUES (
      v_org_id, p_import_id, (v_row_record->>'sourceRowNumber')::INT, v_row_record->'rawRow', v_computed_status,
      COALESCE(v_row_record->'errors', '[]'::jsonb), COALESCE(v_row_record->'warnings', '[]'::jsonb)
    )
    RETURNING id INTO v_row_id;

    IF v_computed_status IN ('ACCEPTED', 'POSSIBLE_AMENDMENT') THEN
      INSERT INTO public.eco_normalized_records (
        organization_id, import_id, record_type, identity_key, fiscal_fingerprint, normalized_payload,
        fecha, cuit, razon_social, comprobante, total, tipo_operacion, categoria, confirmada
      ) VALUES (
        v_org_id, p_import_id, v_import_record.source_type, v_computed_identity_key, v_computed_fingerprint, v_norm,
        (v_norm->>'fecha')::DATE, v_cuit_clean, v_norm->>'razonSocial', v_tipo_cbte || '-' || v_pdv || '-' || v_nro_desde,
        v_total, v_import_record.operation_type, NULL, FALSE
      )
      RETURNING id INTO v_record_id;
    END IF;

    IF v_computed_status = 'INVALID' OR (v_row_record->'errors' IS NOT NULL AND jsonb_array_length(v_row_record->'errors') > 0) THEN
      v_issue_cnt := v_issue_cnt + 1;
      INSERT INTO public.eco_import_issues (
        organization_id, import_id, row_id, record_id, issue_type, message, details
      ) VALUES (
        v_org_id, p_import_id, v_row_id, v_record_id, 'PARSE_ERROR', 'Fila inválida o con errores de parseo',
        jsonb_build_object('errors', v_row_record->'errors', 'warnings', v_row_record->'warnings')
      );
    END IF;
  END LOOP;

  UPDATE public.eco_source_imports
  SET status = CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
      total_rows = v_total_cnt, accepted_rows = v_accepted_cnt, invalid_rows = v_invalid_cnt,
      duplicate_rows = v_duplicate_cnt, completed_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'IMPORT_BATCH_PERSISTED');

  RETURN jsonb_build_object(
    'import_id', p_import_id, 'total_rows', v_total_cnt, 'accepted_rows', v_accepted_cnt,
    'invalid_rows', v_invalid_cnt, 'duplicate_rows', v_duplicate_cnt, 'issues_created', v_issue_cnt,
    'status', CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
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
  v_caller_role TEXT;
  v_import_record RECORD;
  v_existing_file_id UUID;
  v_file_id UUID;
  v_row_elem JSONB;
  v_norm JSONB;
  v_row_id UUID;
  v_record_id UUID;

  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;

  v_source_type TEXT;
  v_fecha_raw TEXT;
  v_fecha DATE;
  v_cuit_clean TEXT;
  v_regimen_norm TEXT;
  v_sucursal_norm TEXT;
  v_comprobante_norm TEXT;
  v_razon_social TEXT;
  v_monto NUMERIC(15,2);
  v_computed_identity_key TEXT;
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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role (got %)', v_caller_role;
  END IF;

  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds maximum allowed limit of 500 rows';
  END IF;

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

  v_hash := p_file_info->>'sha256_hash';
  IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
  END IF;

  v_filename := p_file_info->>'original_name';
  IF v_filename IS NULL OR length(trim(v_filename)) = 0 THEN
    RAISE EXCEPTION 'Original filename is required';
  END IF;

  v_size := (p_file_info->>'size_bytes')::BIGINT;
  IF v_size IS NULL OR v_size <= 0 THEN
    RAISE EXCEPTION 'File size must be greater than zero';
  END IF;

  v_mime := p_file_info->>'mime_type';
  v_storage_path := p_file_info->>'storage_path';
  v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
  IF v_storage_path IS NULL OR NOT (v_storage_path LIKE v_expected_prefix || '%') THEN
    RAISE EXCEPTION 'Storage path must start with authorized prefix %', v_expected_prefix;
  END IF;

  SELECT id INTO v_existing_file_id
  FROM public.eco_source_files
  WHERE organization_id = v_org_id AND sha256_hash = v_hash;

  IF v_existing_file_id IS NOT NULL THEN
    RAISE EXCEPTION 'File with hash % has already been imported for this organization', v_hash;
  END IF;

  UPDATE public.eco_source_imports
  SET status = 'PROCESSING', started_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_source_files (
    organization_id, import_id, original_name, storage_path, mime_type, size_bytes, sha256_hash, source_type
  ) VALUES (
    v_org_id, p_import_id, v_filename, v_storage_path, v_mime, v_size, v_hash, v_import_record.source_type
  )
  RETURNING id INTO v_file_id;

  v_source_type := v_import_record.source_type;

  FOR v_row_elem IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row_elem->'normalizedData';

    IF v_norm IS NULL OR v_norm = 'null'::jsonb OR (v_row_elem->'errors' IS NOT NULL AND jsonb_array_length(v_row_elem->'errors') > 0) THEN
      v_computed_status := 'INVALID';
      v_invalid_cnt := v_invalid_cnt + 1;
    ELSE
      v_fecha_raw := v_norm->>'fecha';
      v_fecha := v_fecha_raw::DATE;
      v_cuit_clean := regexp_replace(COALESCE(v_norm->>'cuit', ''), '\D', '', 'g');
      v_regimen_norm := COALESCE(v_norm->>'regimen', '0');
      v_sucursal_norm := COALESCE(v_norm->>'sucursal', '0');
      v_comprobante_norm := COALESCE(v_norm->>'comprobante', '0');
      v_razon_social := COALESCE(v_norm->>'razonSocial', 'AGENTE PERCEPCION');
      v_monto := COALESCE((v_norm->>'monto')::NUMERIC, (v_norm->>'amount')::NUMERIC, 0);

      v_computed_identity_key := v_source_type || ':' || v_cuit_clean || ':' || v_comprobante_norm || ':' || v_regimen_norm;
      v_computed_fingerprint := digest(
        v_source_type || '|' || v_fecha_raw || '|' || v_cuit_clean || '|' ||
        v_comprobante_norm || '|' || v_regimen_norm || '|' || v_sucursal_norm || '|' ||
        trim(to_char(v_monto, 'FM999999999990.00')),
        'sha256'
      )::text;

      SELECT EXISTS (
        SELECT 1 FROM public.eco_normalized_records
        WHERE organization_id = v_org_id
          AND identity_key = v_computed_identity_key
          AND fiscal_fingerprint = v_computed_fingerprint
      ) INTO v_is_exact_duplicate;

      IF v_is_exact_duplicate THEN
        v_computed_status := 'EXACT_DUPLICATE';
        v_duplicate_cnt := v_duplicate_cnt + 1;
      ELSE
        SELECT EXISTS (
          SELECT 1 FROM public.eco_normalized_records
          WHERE organization_id = v_org_id
            AND identity_key = v_computed_identity_key
            AND fiscal_fingerprint != v_computed_fingerprint
        ) INTO v_is_amendment;

        IF v_is_amendment THEN
          v_computed_status := 'POSSIBLE_AMENDMENT';
          v_accepted_cnt := v_accepted_cnt + 1;
        ELSE
          v_computed_status := 'ACCEPTED';
          v_accepted_cnt := v_accepted_cnt + 1;
        END IF;
      END IF;
    END IF;

    INSERT INTO public.eco_import_rows (
      organization_id, import_id, source_row_number, raw_payload, parse_status, errors, warnings
    ) VALUES (
      v_org_id, p_import_id, (v_row_elem->>'sourceRowNumber')::INT, v_row_elem->'rawRow', v_computed_status,
      COALESCE(v_row_elem->'errors', '[]'::jsonb), COALESCE(v_row_elem->'warnings', '[]'::jsonb)
    )
    RETURNING id INTO v_row_id;

    IF v_computed_status IN ('ACCEPTED', 'POSSIBLE_AMENDMENT') THEN
      INSERT INTO public.eco_normalized_records (
        organization_id, import_id, record_type, identity_key, fiscal_fingerprint, normalized_payload,
        fecha, cuit, razon_social, comprobante, total, tipo_operacion, categoria, confirmada
      ) VALUES (
        v_org_id, p_import_id, v_source_type, v_computed_identity_key, v_computed_fingerprint, v_norm,
        v_fecha, v_cuit_clean, v_razon_social, v_comprobante_norm, v_monto, 'PERCEPCION', NULL, FALSE
      )
      RETURNING id INTO v_record_id;
    END IF;

    IF v_computed_status = 'INVALID' OR (v_row_elem->'errors' IS NOT NULL AND jsonb_array_length(v_row_elem->'errors') > 0) THEN
      v_issue_cnt := v_issue_cnt + 1;
      INSERT INTO public.eco_import_issues (
        organization_id, import_id, row_id, record_id, issue_type, message, details
      ) VALUES (
        v_org_id, p_import_id, v_row_id, v_record_id, 'PARSE_ERROR',
        'Fila inválida o con errores de parseo de percepción',
        jsonb_build_object('errors', v_row_elem->'errors', 'warnings', v_row_elem->'warnings')
      );
    END IF;
  END LOOP;

  UPDATE public.eco_source_imports
  SET status = CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
      total_rows = v_total_cnt, accepted_rows = v_accepted_cnt, invalid_rows = v_invalid_cnt,
      duplicate_rows = v_duplicate_cnt, completed_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'PERCEPTIONS_BATCH_PERSISTED');

  RETURN jsonb_build_object(
    'import_id', p_import_id, 'total_rows', v_total_cnt, 'accepted_rows', v_accepted_cnt,
    'invalid_rows', v_invalid_cnt, 'duplicate_rows', v_duplicate_cnt, 'issues_created', v_issue_cnt,
    'status', CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
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
  v_caller_role TEXT;
  v_caller_id UUID;
  v_import_record RECORD;
  v_file_id UUID;
  v_accepted_cnt INT := 0;
  v_invalid_cnt INT := 0;
  v_duplicate_cnt INT := 0;
  v_issue_cnt INT := 0;
  v_total_cnt INT := 0;
  v_row JSONB;
  v_row_id UUID;
  v_existing_fm_id UUID;

  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;
  v_existing_file_id UUID;

  v_norm JSONB;
  v_is_invalid BOOLEAN;
  v_row_status TEXT;
  v_err JSONB;

  v_computed_identity_key TEXT;
  v_computed_fingerprint TEXT;

  v_fecha_raw TEXT;
  v_fecha DATE;
  v_fecha_valor_raw TEXT;
  v_fecha_valor DATE;
  v_referencia TEXT;
  v_saldo NUMERIC(15,2);
  v_monto NUMERIC(15,2);
  v_tipo TEXT;
  v_account_id TEXT;
  v_descripcion TEXT;

  v_periodo TEXT;
  v_remunerativo NUMERIC(15,2);
  v_noremunerativo NUMERIC(15,2);
  v_anticipos NUMERIC(15,2);
  v_sac NUMERIC(15,2);
  v_sindicato NUMERIC(15,2);
  v_faecys NUMERIC(15,2);
  v_neto NUMERIC(15,2);
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role';
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  SELECT * INTO v_import_record
  FROM public.eco_source_imports
  WHERE id = p_import_id AND organization_id = v_org_id;

  IF v_import_record.id IS NULL THEN
    RAISE EXCEPTION 'Import no encontrado o no pertenece a la organización';
  END IF;

  IF v_import_record.status != 'PENDING' THEN
    RAISE EXCEPTION 'Import no está en estado PENDING';
  END IF;

  IF p_file_info IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.eco_source_files WHERE import_id = p_import_id) THEN
      RAISE EXCEPTION 'Archivo ya registrado para este import %', p_import_id;
    END IF;

    v_hash := p_file_info->>'sha256_hash';
    IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
      RAISE EXCEPTION 'Hash SHA-256 inválido o faltante';
    END IF;

    v_filename := p_file_info->>'original_name';
    v_size := (p_file_info->>'size_bytes')::BIGINT;
    v_mime := p_file_info->>'mime_type';
    v_storage_path := p_file_info->>'storage_path';
    v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
    IF v_storage_path IS NULL OR NOT (v_storage_path LIKE v_expected_prefix || '%') THEN
      RAISE EXCEPTION 'Storage path no cumple con el prefijo autorizado %', v_expected_prefix;
    END IF;

    SELECT id INTO v_existing_file_id
    FROM public.eco_source_files
    WHERE organization_id = v_org_id AND sha256_hash = v_hash;

    IF v_existing_file_id IS NOT NULL THEN
      RAISE EXCEPTION 'Archivo con hash % ya fue importado anteriormente', v_hash;
    END IF;

    INSERT INTO public.eco_source_files (
      organization_id, import_id, original_name, storage_path, mime_type, size_bytes, sha256_hash, source_type
    ) VALUES (
      v_org_id, p_import_id, v_filename, v_storage_path, v_mime, v_size, v_hash, v_import_record.source_type
    ) RETURNING id INTO v_file_id;
  END IF;

  UPDATE public.eco_source_imports
  SET status = 'PROCESSING', started_at = now()
  WHERE id = p_import_id;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row->'normalizedData';
    v_err := COALESCE(v_row->'errors', '[]'::jsonb);

    v_is_invalid := (v_norm IS NULL OR v_norm = 'null'::jsonb OR jsonb_array_length(v_err) > 0);

    IF v_is_invalid THEN
      v_row_status := 'INVALID';
      v_invalid_cnt := v_invalid_cnt + 1;
    ELSE
      IF v_import_record.operation_type = 'BANCO' THEN
        v_fecha_raw := v_norm->>'fecha';
        v_fecha := v_fecha_raw::DATE;
        v_fecha_valor_raw := COALESCE(v_norm->>'fechaValor', v_fecha_raw);
        v_fecha_valor := v_fecha_valor_raw::DATE;
        v_referencia := COALESCE(v_norm->>'referencia', '');
        v_saldo := COALESCE((v_norm->>'saldo')::NUMERIC, 0);
        v_monto := COALESCE((v_norm->>'monto')::NUMERIC, 0);
        v_tipo := COALESCE(v_norm->>'tipo', 'debit');
        v_account_id := COALESCE(v_norm->>'accountIdentifier', 'GENERIC_BANK');
        v_descripcion := COALESCE(v_norm->>'descripcion', '');

        v_computed_identity_key := v_import_record.source_type || ':' || v_account_id || ':' || v_fecha_raw || ':' || v_referencia;
        v_computed_fingerprint := digest(
          v_import_record.source_type || '|' || v_account_id || '|' || v_fecha_raw || '|' ||
          trim(to_char(v_monto, 'FM999999999990.00')) || '|' || trim(to_char(v_saldo, 'FM999999999990.00')) || '|' ||
          v_referencia || '|' || v_tipo,
          'sha256'
        )::text;

      ELSIF v_import_record.operation_type = 'SUELDO' THEN
        v_fecha_raw := v_norm->>'fecha';
        v_fecha := v_fecha_raw::DATE;
        v_fecha_valor := v_fecha;
        v_referencia := COALESCE(v_norm->>'cuil', v_norm->>'legajo', '');
        v_periodo := COALESCE(v_norm->>'periodo', to_char(v_fecha, 'YYYY-MM'));
        v_remunerativo := COALESCE((v_norm->>'remunerativo')::NUMERIC, 0);
        v_noremunerativo := COALESCE((v_norm->>'noRemunerativo')::NUMERIC, 0);
        v_anticipos := COALESCE((v_norm->>'anticipos')::NUMERIC, 0);
        v_sac := COALESCE((v_norm->>'sac')::NUMERIC, 0);
        v_sindicato := COALESCE((v_norm->>'sindicato')::NUMERIC, 0);
        v_faecys := COALESCE((v_norm->>'faecys')::NUMERIC, 0);
        v_neto := COALESCE((v_norm->>'neto')::NUMERIC, (v_norm->>'monto')::NUMERIC, 0);
        v_monto := v_neto;
        v_saldo := 0;
        v_tipo := 'credit';
        v_account_id := 'ACONPY_PAYROLL';
        v_descripcion := COALESCE(v_norm->>'empleado', v_norm->>'descripcion', 'LIQUIDACION SUELDO');

        v_computed_identity_key := v_import_record.source_type || ':' || v_periodo || ':' || v_referencia;
        v_computed_fingerprint := digest(
          v_import_record.source_type || '|' || v_periodo || '|' || v_referencia || '|' ||
          trim(to_char(v_neto, 'FM999999999990.00')) || '|' || trim(to_char(v_remunerativo, 'FM999999999990.00')),
          'sha256'
        )::text;
      END IF;

      SELECT id INTO v_existing_fm_id
      FROM public.eco_financial_movements
      WHERE organization_id = v_org_id
        AND identity_key = v_computed_identity_key
        AND financial_fingerprint = v_computed_fingerprint;

      IF v_existing_fm_id IS NOT NULL THEN
        v_row_status := 'EXACT_DUPLICATE';
        v_duplicate_cnt := v_duplicate_cnt + 1;
      ELSE
        v_row_status := 'ACCEPTED';
        v_accepted_cnt := v_accepted_cnt + 1;
      END IF;
    END IF;

    INSERT INTO public.eco_import_rows (
      organization_id, import_id, source_row_number, raw_payload, parse_status, errors, warnings
    ) VALUES (
      v_org_id, p_import_id, (v_row->>'sourceRowNumber')::INT, v_row->'rawRow', v_row_status,
      v_err, COALESCE(v_row->'warnings', '[]'::jsonb)
    ) RETURNING id INTO v_row_id;

    IF v_row_status = 'ACCEPTED' THEN
      INSERT INTO public.eco_financial_movements (
        organization_id, import_id, source_type, operation_type, fecha, fecha_valor, periodo,
        descripcion, referencia, account_identifier, movement_type, monto, saldo, identity_key, financial_fingerprint, normalized_payload
      ) VALUES (
        v_org_id, p_import_id, v_import_record.source_type, v_import_record.operation_type, v_fecha, v_fecha_valor,
        CASE WHEN v_import_record.operation_type = 'SUELDO' THEN v_periodo ELSE to_char(v_fecha, 'YYYY-MM') END,
        v_descripcion, v_referencia, v_account_id, v_tipo, v_monto, v_saldo, v_computed_identity_key, v_computed_fingerprint, v_norm
      );
    END IF;

    IF v_row_status = 'INVALID' THEN
      v_issue_cnt := v_issue_cnt + 1;
      INSERT INTO public.eco_import_issues (
        organization_id, import_id, row_id, issue_type, message, details
      ) VALUES (
        v_org_id, p_import_id, v_row_id, 'PARSE_ERROR', 'Error de parseo en movimiento financiero',
        jsonb_build_object('errors', v_err, 'warnings', v_row->'warnings')
      );
    END IF;
  END LOOP;

  UPDATE public.eco_source_imports
  SET status = CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
      total_rows = v_total_cnt, accepted_rows = v_accepted_cnt, invalid_rows = v_invalid_cnt,
      duplicate_rows = v_duplicate_cnt, completed_at = now()
  WHERE id = p_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'FINANCIAL_MOVEMENTS_PERSISTED');

  RETURN jsonb_build_object(
    'import_id', p_import_id, 'total_rows', v_total_cnt, 'accepted_rows', v_accepted_cnt,
    'invalid_rows', v_invalid_cnt, 'duplicate_rows', v_duplicate_cnt, 'issues_created', v_issue_cnt,
    'status', CASE WHEN (v_invalid_cnt + v_duplicate_cnt) > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
  );
END;
$$;


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
  v_role TEXT;
  v_import_record RECORD;
  v_orig_file RECORD;
  v_downstream_count INT := 0;
  v_retry_downstream_count INT := 0;
  v_new_import_id UUID;
  v_profile_id UUID;
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'No active organization found for caller';
  END IF;

  v_role := private.func_role();
  IF v_role NOT IN ('ADMIN', 'UPLOADER') THEN
    RAISE EXCEPTION 'Unauthorized: Caller role % cannot request import retry', COALESCE(v_role, 'NONE');
  END IF;

  SELECT * INTO v_import_record
  FROM public.eco_source_imports
  WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

  IF v_import_record IS NULL THEN
    RAISE EXCEPTION 'Import record not found or access denied';
  END IF;

  IF COALESCE(v_import_record.accepted_rows, 0) > 0 THEN
    RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % accepted rows', v_import_record.accepted_rows;
  END IF;

  IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
    SELECT COUNT(*) INTO v_downstream_count
    FROM public.eco_normalized_records
    WHERE import_id = p_import_id AND organization_id = v_org_id AND deleted_at IS NULL;
  ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
    SELECT COUNT(*) INTO v_downstream_count
    FROM public.eco_financial_movements
    WHERE import_id = p_import_id AND organization_id = v_org_id AND deleted_at IS NULL;
  END IF;

  IF v_downstream_count > 0 THEN
    RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % downstream records persisted', v_downstream_count;
  END IF;

  IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
    SELECT COUNT(*) INTO v_retry_downstream_count
    FROM public.eco_normalized_records nr
    JOIN public.eco_source_imports si ON si.id = nr.import_id
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
  WHERE auth_user_id = auth.uid() AND is_active = TRUE LIMIT 1;

  SELECT * INTO v_orig_file
  FROM public.eco_source_files
  WHERE import_id = p_import_id AND organization_id = v_org_id
  ORDER BY created_at DESC LIMIT 1;

  IF v_orig_file IS NULL THEN
    RAISE EXCEPTION 'Original file not found for import %', p_import_id;
  END IF;

  INSERT INTO public.eco_source_imports (
    organization_id, source_type, operation_type, status, created_by, retry_of_import_id
  ) VALUES (
    v_org_id, v_import_record.source_type, v_import_record.operation_type, 'PENDING', v_profile_id, p_import_id
  )
  RETURNING id INTO v_new_import_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type, details)
  VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED', jsonb_build_object(
    'original_import_id', p_import_id, 'new_import_id', v_new_import_id, 'file_id', v_orig_file.id
  ));

  RETURN jsonb_build_object(
    'new_import_id', v_new_import_id,
    'original_import_id', p_import_id,
    'organization_id', v_org_id,
    'file_info', jsonb_build_object(
      'original_name', v_orig_file.original_name,
      'storage_path', v_orig_file.storage_path,
      'mime_type', v_orig_file.mime_type,
      'size_bytes', v_orig_file.size_bytes,
      'sha256_hash', v_orig_file.sha256_hash
    )
  );
END;
$$;


-- 2. RESTORE REVIEW & CLASSIFICATION RPCs

CREATE OR REPLACE FUNCTION public.resolve_issue(target_issue_id UUID, res_note TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_caller_id UUID;
  v_issue_org_id UUID;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role';
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  SELECT organization_id INTO v_issue_org_id
  FROM public.eco_import_issues
  WHERE id = target_issue_id;

  IF v_issue_org_id IS NULL THEN
    RAISE EXCEPTION 'Issue not found';
  END IF;

  IF v_issue_org_id != v_org_id THEN
    RAISE EXCEPTION 'Unauthorized: Issue belongs to another organization';
  END IF;

  UPDATE public.eco_import_issues
  SET status = 'RESOLVED',
      resolved_by = v_caller_id,
      resolved_at = NOW(),
      resolution_note = res_note
  WHERE id = target_issue_id AND status = 'OPEN';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Issue is already resolved or no longer OPEN';
  END IF;

  INSERT INTO public.eco_review_actions (issue_id, actor_id, action_type, notes)
  VALUES (target_issue_id, v_caller_id, 'ISSUE_RESOLVED', res_note);

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ISSUE_RESOLVED');
END;
$$;


CREATE OR REPLACE FUNCTION public.soft_delete_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
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


CREATE OR REPLACE FUNCTION public.restore_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
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


CREATE OR REPLACE FUNCTION public.soft_delete_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
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


CREATE OR REPLACE FUNCTION public.restore_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
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
  v_caller_role TEXT;
  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE;
    
    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE;
    
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
  v_caller_role TEXT;
  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE;
    IF v_valid_category IS NOT TRUE THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE;
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
  v_caller_role TEXT;
  v_caller_id UUID;
  v_rows_affected INT := 0;
  v_valid BOOLEAN;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF p_category_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_tax_categories WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_economic_activities WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE
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


-- 3. RESTORE CATALOG & IIBB ADMIN RPCs

CREATE OR REPLACE FUNCTION public.create_global_tax_category(
  p_name TEXT,
  p_description TEXT,
  p_category_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_new_id UUID;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  INSERT INTO public.eco_tax_categories (name, description, category_type, is_active)
  VALUES (p_name, p_description, p_category_type, TRUE)
  RETURNING id INTO v_new_id;
  
  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CATEGORY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_global_tax_category(
  p_category_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_tax_categories
  SET name = p_name, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_category_id;
  
  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CATEGORY_UPDATED');
  END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_global_economic_activity(
  p_name TEXT,
  p_afip_code TEXT,
  p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_new_id UUID;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  INSERT INTO public.eco_economic_activities (name, arca_code, description, is_active)
  VALUES (p_name, p_afip_code, p_description, TRUE)
  RETURNING id INTO v_new_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_global_economic_activity(
  p_activity_id UUID,
  p_name TEXT,
  p_afip_code TEXT,
  p_description TEXT,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_economic_activities
  SET name = p_name, arca_code = p_afip_code, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_activity_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_UPDATED');
  END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.upsert_arca_activity_catalog(
  p_activities JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_act JSONB;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: Must be authenticated'; END IF;

  FOR v_act IN SELECT * FROM jsonb_array_elements(p_activities)
  LOOP
    IF v_act->>'arca_code' IS NULL OR v_act->>'name' IS NULL THEN
      RAISE EXCEPTION 'Invalid activity format: arca_code and name are required';
    END IF;

    INSERT INTO public.eco_economic_activities (name, arca_code, description, is_active)
    VALUES (
      v_act->>'name', 
      v_act->>'arca_code', 
      v_act->>'description', 
      COALESCE((v_act->>'is_active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (arca_code) DO UPDATE
    SET name = EXCLUDED.name,
        description = EXCLUDED.description,
        is_active = EXCLUDED.is_active,
        updated_at = now();
  END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_org_activity_iibb_rate(
  p_activity_id UUID,
  p_jurisdiction TEXT,
  p_rate NUMERIC(5,2),
  p_valid_from DATE DEFAULT NULL,
  p_valid_to DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_rate_id UUID;
  v_valid BOOLEAN;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  IF p_rate < 0 THEN RAISE EXCEPTION 'Rate must be >= 0'; END IF;
  
  p_jurisdiction := TRIM(p_jurisdiction);
  IF p_jurisdiction = '' THEN RAISE EXCEPTION 'Jurisdiction cannot be empty'; END IF;

  IF p_valid_from IS NOT NULL AND p_valid_to IS NOT NULL AND p_valid_from > p_valid_to THEN
    RAISE EXCEPTION 'valid_from must be <= valid_to';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.eco_org_economic_activities 
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE
  ) INTO v_valid;
  IF NOT v_valid THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.eco_org_activity_iibb_rates
    WHERE organization_id = v_org_id 
      AND activity_id = p_activity_id 
      AND jurisdiction = p_jurisdiction 
      AND is_active = TRUE
      AND COALESCE(p_valid_from, '-infinity'::date) <= COALESCE(valid_to, 'infinity'::date)
      AND COALESCE(p_valid_to, 'infinity'::date) >= COALESCE(valid_from, '-infinity'::date)
  ) INTO v_valid;
  IF v_valid THEN RAISE EXCEPTION 'Conflicting active period for the same organization, activity, and jurisdiction'; END IF;

  INSERT INTO public.eco_org_activity_iibb_rates (
    organization_id, activity_id, jurisdiction, rate, valid_from, valid_to
  ) VALUES (
    v_org_id, p_activity_id, p_jurisdiction, p_rate, p_valid_from, p_valid_to
  ) RETURNING id INTO v_rate_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type, details)
  VALUES (v_org_id, 'IIBB_RATE_CREATED', jsonb_build_object('rate_id', v_rate_id, 'activity_id', p_activity_id, 'jurisdiction', p_jurisdiction));

  RETURN v_rate_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_org_activity_iibb_rate(
  p_rate_id UUID,
  p_rate NUMERIC(5,2),
  p_valid_from DATE DEFAULT NULL,
  p_valid_to DATE DEFAULT NULL,
  p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_activity_id UUID;
  v_jurisdiction TEXT;
  v_valid BOOLEAN;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  IF p_rate < 0 THEN RAISE EXCEPTION 'Rate must be >= 0'; END IF;
  IF p_valid_from IS NOT NULL AND p_valid_to IS NOT NULL AND p_valid_from > p_valid_to THEN
    RAISE EXCEPTION 'valid_from must be <= valid_to';
  END IF;

  SELECT activity_id, jurisdiction INTO v_activity_id, v_jurisdiction
  FROM public.eco_org_activity_iibb_rates
  WHERE id = p_rate_id AND organization_id = v_org_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Rate not found or unauthorized'; END IF;

  IF p_is_active THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_activity_iibb_rates
      WHERE organization_id = v_org_id 
        AND activity_id = v_activity_id 
        AND jurisdiction = v_jurisdiction 
        AND is_active = TRUE
        AND id != p_rate_id
        AND COALESCE(p_valid_from, '-infinity'::date) <= COALESCE(valid_to, 'infinity'::date)
        AND COALESCE(p_valid_to, 'infinity'::date) >= COALESCE(valid_from, '-infinity'::date)
    ) INTO v_valid;
    IF v_valid THEN RAISE EXCEPTION 'Conflicting active period for the same organization, activity, and jurisdiction'; END IF;
  END IF;

  UPDATE public.eco_org_activity_iibb_rates
  SET rate = p_rate,
      valid_from = p_valid_from,
      valid_to = p_valid_to,
      is_active = p_is_active,
      updated_at = now()
  WHERE id = p_rate_id AND organization_id = v_org_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type, details)
  VALUES (v_org_id, 'IIBB_RATE_UPDATED', jsonb_build_object('rate_id', p_rate_id, 'is_active', p_is_active));
END;
$$;

COMMIT;
