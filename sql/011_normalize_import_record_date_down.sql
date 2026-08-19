BEGIN;

-- ============================================================
-- ROLLBACK MIGRATION 011: RESTAURAR DEFINICION ANTERIOR DE PERSIST_IMPORT_BATCH (MIGRATION 010)
-- ============================================================

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
          (v_norm->>'fecha')::DATE,
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

COMMIT;
