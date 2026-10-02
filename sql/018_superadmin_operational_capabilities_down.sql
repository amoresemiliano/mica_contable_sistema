BEGIN;

-- ============================================================
-- MIGRATION 018 DOWN: RESTORE PRE-M018 CANONICAL RPC DEFINITIONS
-- ============================================================
-- Restores the exact canonical pre-M018 RPC definitions for all 20 RPCs.
-- ============================================================

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

REVOKE ALL ON FUNCTION public.create_import(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_import(text, text) TO authenticated;

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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  -- 1. Role Check
  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role';
  END IF;

  -- 2. Límite de Batch (Máximo 500 filas)
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
      -- Fila Inválida
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
        'Fila inválida omitida durante la importación',
        v_row_record->'errors'
      );

    ELSE
      -- Reconstrucción Server-Side de Identidad y Fingerprint
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

      -- Normalización Server-Side de Fecha (Soporta YYYY-MM-DD y DD/MM/YYYY con validación estricta)
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

      -- Algoritmo Server-Side de Clasificación
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
            'Se detectó una versión modificada de un comprobante existente',
            jsonb_build_object('computedFingerprint', v_computed_fingerprint)
          );
        END IF;

      ELSIF v_computed_status = 'EXACT_DUPLICATE' THEN
        v_duplicate_cnt := v_duplicate_cnt + 1;
      END IF;

    END IF;
  END LOOP;

  -- 8. Finalizar Importación
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

REVOKE ALL ON FUNCTION public.persist_import_batch(uuid, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_import_batch(uuid, jsonb, jsonb) TO authenticated;

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

  -- Clasificación y contadores
  v_is_exact_duplicate BOOLEAN;
  v_is_amendment BOOLEAN;
  v_computed_status TEXT;

  v_accepted_cnt INT := 0;
  v_invalid_cnt  INT := 0;
  v_duplicate_cnt INT := 0;
  v_total_cnt    INT := 0;
  v_issue_cnt    INT := 0;

BEGIN
  -- ============================================================
  -- § AUTORIZACIÓN: org_id + rol server-side
  -- ============================================================
  v_org_id      := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  -- Permiso exclusivo: UPLOADER / ADMIN
  -- Rechaza: USER, REVIEWER
  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN
    RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role (got %)', v_caller_role;
  END IF;

  -- ============================================================
  -- § BATCH LIMIT: máximo 500 filas server-side
  -- ============================================================
  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds maximum allowed limit of 500 rows';
  END IF;

  -- ============================================================
  -- § IMPORT AUTHORITY
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
  -- § FILE METADATA — defensas idénticas a Migration 010/011
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
  -- § TRANSICIÓN ATÓMICA: PENDING → PROCESSING
  -- ============================================================
  UPDATE public.eco_source_imports
  SET status = 'PROCESSING'
  WHERE id = p_import_id;

  -- ============================================================
  -- § REGISTRAR METADATOS DE ARCHIVO EN eco_source_files
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
  -- § PROCESAMIENTO DE FILAS
  -- ============================================================
  v_source_type := v_import_record.source_type;

  FOR v_row_elem IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row_elem->'normalizedData';

    -- ─── FILA INVÁLIDA (normalizedData ausente o null) ─────────────────────
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
        NULL,   -- record_id = NULL para filas inválidas sin registro normalizado
        'PARSE_ERROR',
        'Fila de percepción inválida omitida durante la importación',
        v_row_elem->'errors'
      );

      CONTINUE;
    END IF;

    -- ─── CUIT: solo dígitos, sin separadores ───────────────────────────────
    v_cuit_clean := REGEXP_REPLACE(COALESCE(v_norm->>'cuit', ''), '\D', '', 'g');

    -- ─── CANONICALIZACIÓN SERVER-SIDE DE FECHA ─────────────────────────────
    -- Acepta: DD/MM/YYYY  y  YYYY-MM-DD
    -- Rechaza cualquier otra forma, vacío o fecha inválida en calendario.
    -- Una fecha inválida convierte la fila en INVALID (PARSE_ERROR), NO rollback total.
    v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));
    v_date_ok := FALSE;
    v_fecha := NULL;

    BEGIN
      IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN
        -- Formato ISO
        v_fecha := v_fecha_raw::DATE;
        -- Verificar que la fecha sea calendáricamente válida (e.g. no 2026-02-31)
        IF TO_CHAR(v_fecha, 'YYYY-MM-DD') = v_fecha_raw THEN
          v_date_ok := TRUE;
        END IF;

      ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN
        -- Formato argentino DD/MM/YYYY
        v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
        -- Verificar que la conversión sea exacta (round-trip)
        IF TO_CHAR(v_fecha, 'DD/MM/YYYY') = v_fecha_raw THEN
          v_date_ok := TRUE;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_date_ok := FALSE;
      v_fecha   := NULL;
    END;

    IF NOT v_date_ok OR v_fecha IS NULL THEN
      -- Fecha inválida: registrar fila como INVALID + PARSE_ERROR
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
            'Formato de fecha inválido o fecha inexistente: "' || v_fecha_raw || '". Se acepta DD/MM/YYYY o YYYY-MM-DD')
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
        'Fecha inválida en percepción: "' || v_fecha_raw || '"',
        jsonb_build_object('field', 'fecha', 'raw', v_fecha_raw)
      );

      CONTINUE;
    END IF;

    -- Fecha canonical server-side — NUNCA fecha raw
    v_fecha_canonical := TO_CHAR(v_fecha, 'YYYY-MM-DD');

    -- ─── MONTO Y FINGERPRINT FISCAL DETERMINÍSTICO ─────────────────────────
    -- Prioridad: monto > amount > importe
    -- Canonicalizado a NUMERIC(15,2)
    -- Fingerprint: SHA-256 sobre representación TO_CHAR determinística con 2 decimales
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

    -- ─── IDENTIDAD CANÓNICA POR SOURCE_TYPE ────────────────────────────────

    IF v_source_type = 'PERCEPCIONES_ARBA' THEN
      -- ARBA: regimen, sucursal y comprobante sin convertir a número.
      -- TRIM, preservar ceros iniciales.
      v_regimen_norm    := COALESCE(NULLIF(TRIM(v_norm->>'regimen'),    ''), '');
      v_sucursal_norm   := COALESCE(NULLIF(TRIM(v_norm->>'sucursal'),   ''), '');
      v_comprobante_norm:= COALESCE(NULLIF(TRIM(v_norm->>'comprobante'),''), '');

      -- razon_social: NULL si no existe en el payload ARBA
      v_razon_social := NULLIF(TRIM(COALESCE(v_norm->>'razonSocial', '')), '');

      -- identity_key ARBA — server-side, no confiar en frontend
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
      -- IVA: comprobante preservado como TEXT, sin inventar régimen
      v_comprobante_norm := COALESCE(NULLIF(TRIM(v_norm->>'comprobante'), ''), '');
      v_regimen_norm     := NULL;  -- IVA no tiene régimen
      v_sucursal_norm    := NULL;

      -- razon_social: desde razonSocial del payload IVA
      v_razon_social := NULLIF(TRIM(COALESCE(v_norm->>'razonSocial', '')), '');

      -- identity_key IVA — server-side
      v_computed_identity_key := jsonb_build_array(
        'PERCEPCION',
        'PERCEPCIONES_IVA',
        'IVA',
        v_cuit_clean,
        v_fecha_canonical,
        v_comprobante_norm
      )::text;

    END IF;

    -- ─── CLASIFICACIÓN: EXACT_DUPLICATE / POSSIBLE_AMENDMENT / ACCEPTED ────
    -- A. EXISTS exact: organization_id + identity_key + fiscal_fingerprint => EXACT_DUPLICATE
    -- B. EXISTS identity (sin fingerprint coincidente)                      => POSSIBLE_AMENDMENT
    -- C. No existe identity                                                  => ACCEPTED
    -- NO comparar solo contra versión más reciente.

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

    -- ─── REGISTRAR FILA (SIEMPRE: ACCEPTED / INVALID / EXACT_DUPLICATE / POSSIBLE_AMENDMENT) ──
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

    -- ─── REGISTRO NORMALIZADO PARA ACCEPTED + POSSIBLE_AMENDMENT ───────────
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
        v_cuit_clean,            -- cuit agente, solo dígitos
        v_razon_social,          -- NULL para ARBA si no viene en payload; razonSocial para IVA
        v_comprobante_norm,      -- texto preservado
        v_monto,                 -- total percepción
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
          'Se detectó una modificación en el monto de una percepción existente',
          -- Solo información segura, no hashes del frontend
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
  -- § ESTADO FINAL Y CONTADORES
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
  -- § AUDIT — esquema real de eco_audit_events
  -- Solo columnas existentes: organization_id, event_type
  -- NO se inventan columnas adicionales
  -- ============================================================
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'IMPORT_COMPLETED');

  -- ============================================================
  -- § RESPUESTA
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
    v_role TEXT;
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
BEGIN
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    v_role := private.func_role();
    IF v_role NOT IN ('ADMIN', 'UPLOADER') THEN
        RAISE EXCEPTION 'Unauthorized: Caller role % cannot persist financial movements', COALESCE(v_role, 'NONE');
    END IF;

    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    IF v_import_record.status NOT IN ('PENDING', 'PROCESSING', 'COMPLETED_WITH_ISSUES', 'FAILED') THEN
        RAISE EXCEPTION 'Import no está en estado válido para procesamiento';
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

    -- Fetch existing file_id linked to current import_id OR retry_of_import_id
    SELECT id INTO v_file_id
    FROM public.eco_source_files
    WHERE (import_id = p_import_id OR (v_import_record.retry_of_import_id IS NOT NULL AND import_id = v_import_record.retry_of_import_id))
      AND organization_id = v_org_id 
    ORDER BY created_at ASC LIMIT 1;

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
        v_row_status := 'ACCEPTED';

        v_total_cnt := v_total_cnt + 1;
        v_norm := v_row->'normalizedData';

        IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' OR (v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0) THEN
            v_is_invalid := TRUE;
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
                    END IF;

                    v_tipo := v_norm->>'tipo';
                    v_account_id := COALESCE(v_norm->>'accountIdentifier', '');
                    v_descripcion := TRIM(COALESCE(v_norm->>'descripcion', ''));

                    IF NOT v_is_invalid THEN
                        IF v_referencia != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), v_referencia, v_monto, v_tipo)::text;
                        ELSIF v_saldo IS NOT NULL THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REFERENCE', v_saldo, v_monto, v_tipo)::text;
                        ELSE
                            v_is_invalid := TRUE;
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
            END;
        END IF;

        IF v_is_invalid THEN
            v_invalid_cnt := v_invalid_cnt + 1;
            v_row_status := 'INVALID';
            
            INSERT INTO public.eco_import_issues (
                organization_id,
                import_id,
                issue_type,
                message,
                status
            ) VALUES (
                v_org_id,
                p_import_id,
                'PARSE_ERROR',
                'Fila inválida o incompleta',
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
                v_row_status := 'DUPLICATE';
            ELSE
                INSERT INTO public.eco_financial_movements (
                    organization_id,
                    import_id,
                    operation_type,
                    source_type,
                    fecha,
                    fecha_valor,
                    periodo,
                    descripcion,
                    referencia,
                    monto,
                    tipo,
                    saldo,
                    identity_key,
                    fingerprint,
                    normalized_payload
                ) VALUES (
                    v_org_id,
                    p_import_id,
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

        -- Record import row log
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
        );
    END LOOP;

    -- Update final import attempt status
    UPDATE public.eco_source_imports
    SET status = CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
        total_rows = v_total_cnt,
        accepted_rows = v_accepted_cnt,
        invalid_rows = v_invalid_cnt,
        duplicate_rows = v_duplicate_cnt,
        completed_at = NOW()
    WHERE id = p_import_id;

    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'FINANCIAL_MOVEMENTS_PERSISTED');

    RETURN jsonb_build_object(
        'import_id', p_import_id,
        'total_rows', v_total_cnt,
        'accepted_rows', v_accepted_cnt,
        'invalid_rows', v_invalid_cnt,
        'duplicate_rows', v_duplicate_cnt,
        'status', CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) TO authenticated;

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
    -- Security check: tenant isolation & authorization
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    v_role := private.func_role();
    IF v_role NOT IN ('ADMIN', 'UPLOADER') THEN
        RAISE EXCEPTION 'Unauthorized: Caller role % cannot request import retry', COALESCE(v_role, 'NONE');
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

    -- Check if any existing retry attempt for this original import already has accepted or downstream rows
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

    -- Log audit event using established eco_audit_events schema
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

REVOKE ALL ON FUNCTION public.request_failed_import_retry(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_failed_import_retry(UUID) TO authenticated;

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

REVOKE ALL ON FUNCTION public.resolve_issue(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_issue(UUID, TEXT) TO authenticated;

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
REVOKE ALL ON FUNCTION public.soft_delete_normalized_record(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_normalized_record(UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.restore_normalized_record(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_normalized_record(UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.soft_delete_financial_movement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_financial_movement(UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.restore_financial_movement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_financial_movement(UUID) TO authenticated;

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
  
  -- Validar que la categoría pertenezca a la org y esté activa
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE;
    
    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  -- Validar que la actividad pertenezca a la org y esté activa
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
REVOKE ALL ON FUNCTION public.update_record_classification(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_record_classification(UUID, UUID, UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) TO authenticated;

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
REVOKE ALL ON FUNCTION public.create_global_tax_category(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_global_tax_category(TEXT, TEXT, TEXT) TO authenticated;

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
REVOKE ALL ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) TO authenticated;

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

  INSERT INTO public.eco_economic_activities (name, afip_code, description, is_active)
  VALUES (p_name, p_afip_code, p_description, TRUE)
  RETURNING id INTO v_new_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_global_economic_activity(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_global_economic_activity(TEXT, TEXT, TEXT) TO authenticated;

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
  SET name = p_name, afip_code = p_afip_code, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_activity_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_UPDATED');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

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
REVOKE ALL ON FUNCTION public.upsert_arca_activity_catalog(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_arca_activity_catalog(JSONB) TO authenticated;

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
REVOKE ALL ON FUNCTION public.create_org_activity_iibb_rate(UUID, TEXT, NUMERIC, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_org_activity_iibb_rate(UUID, TEXT, NUMERIC, DATE, DATE) TO authenticated;

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
REVOKE ALL ON FUNCTION public.update_org_activity_iibb_rate(UUID, NUMERIC, DATE, DATE, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_org_activity_iibb_rate(UUID, NUMERIC, DATE, DATE, BOOLEAN) TO authenticated;

COMMIT;
