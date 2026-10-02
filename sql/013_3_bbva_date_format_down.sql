BEGIN;

-- ============================================================
-- MIGRATION 013.2: HARDEN FINANCIAL RPC CONTRACT
-- ============================================================

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
  
  -- Metadatos de archivo
  v_hash TEXT;
  v_filename TEXT;
  v_size BIGINT;
  v_mime TEXT;
  v_storage_path TEXT;
  v_expected_prefix TEXT;
  v_existing_file_id UUID;

  -- Variables para proceso de filas
  v_norm JSONB;
  v_is_invalid BOOLEAN;
  v_row_status TEXT;
  v_err JSONB;

  -- Server-side Identity & Fingerprint
  v_computed_identity_key TEXT;
  v_computed_fingerprint TEXT;
  
  -- Para Banco
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
  v_signals_str TEXT;

  -- Para Aconpy
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

  -- Validar importación
  SELECT * INTO v_import_record
  FROM public.eco_source_imports
  WHERE id = p_import_id AND organization_id = v_org_id;

  IF v_import_record.id IS NULL THEN
    RAISE EXCEPTION 'Import no encontrado o no pertenece a la organización';
  END IF;

  IF v_import_record.status != 'PENDING' THEN
    RAISE EXCEPTION 'Import no está en estado PENDING';
  END IF;

  IF NOT (
    (v_import_record.source_type = 'PAYROLL_ACONPY' AND v_import_record.operation_type = 'SUELDO') OR
    (v_import_record.source_type = 'BANK_STATEMENT_BBVA' AND v_import_record.operation_type = 'BANCO')
  ) THEN
    RAISE EXCEPTION 'Combinación de source_type y operation_type no soportada por esta RPC';
  END IF;

  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds 500 rows limit';
  END IF;

  -- Validar Metadatos de Archivo Server-Side (013.2 HARDENING)
  v_hash := p_file_info->>'sha256_hash';
  IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
  END IF;

  v_filename := TRIM(COALESCE(p_file_info->>'original_name', ''));
  IF v_filename = '' OR LENGTH(v_filename) > 255 THEN 
    RAISE EXCEPTION 'Invalid original_name'; 
  END IF;

  v_size := (p_file_info->>'size_bytes')::BIGINT;
  IF v_size IS NULL OR v_size <= 0 OR v_size > 20971520 THEN 
    RAISE EXCEPTION 'Invalid size_bytes (must be between 1 and 20MB)'; 
  END IF;

  v_mime := p_file_info->>'mime_type';
  IF v_mime NOT IN (
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain'
  ) THEN 
    RAISE EXCEPTION 'Invalid mime_type'; 
  END IF;

  v_storage_path := p_file_info->>'storage_path';
  v_expected_prefix := v_org_id::text || '/' || p_import_id::text || '/';
  IF NOT (v_storage_path LIKE v_expected_prefix || '%') THEN 
    RAISE EXCEPTION 'Invalid storage path: must begin with %', v_expected_prefix; 
  END IF;

  SELECT id INTO v_existing_file_id
  FROM public.eco_source_files
  WHERE organization_id = v_org_id AND sha256_hash = v_hash;

  IF v_existing_file_id IS NOT NULL THEN
    RAISE EXCEPTION 'FILE_ALREADY_EXISTS: File with hash % already imported', v_hash;
  END IF;

  UPDATE public.eco_source_imports SET status = 'PROCESSING' WHERE id = p_import_id;

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

  -- Procesamiento de Filas
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    -- 013.2 RESET VARIABLES POR ROW
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
    v_signals_str := NULL;
    v_is_invalid := FALSE;
    v_row_status := 'ACCEPTED';

    v_total_cnt := v_total_cnt + 1;
    v_norm := v_row->'normalizedData';

    IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' OR (v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0) THEN
      v_is_invalid := TRUE;
    END IF;

    IF NOT v_is_invalid THEN
      -- Calculo de Identity y Fingerprint server side
      BEGIN
        IF v_import_record.source_type = 'PAYROLL_ACONPY' THEN
          -- 013.2 ACONPY PERIODO SERVER-SIDE
          v_periodo := TRIM(COALESCE(v_norm->>'periodo', ''));
          IF v_periodo ~ '^(0[1-9]|1[0-2])/\d{4}$' THEN
            v_periodo := RIGHT(v_periodo, 4) || '-' || LEFT(v_periodo, 2);
          ELSIF v_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
            -- already correct YYYY-MM
          ELSE
            v_is_invalid := TRUE;
          END IF;

          IF NOT v_is_invalid THEN
            v_computed_identity_key := jsonb_build_array('PAYROLL_ACONPY', v_periodo)::text;
            
            -- Aconpy anticipo fallback: prefer anticipoSueldo then anticipos
            v_anticipos := ROUND(COALESCE(NULLIF(v_norm->>'anticipoSueldo', ''), NULLIF(v_norm->>'anticipos', ''), '0')::numeric, 2);
            
            v_remunerativo := ROUND(COALESCE(NULLIF(v_norm->>'remunerativo', ''), '0')::numeric, 2);
            v_noremunerativo := ROUND(COALESCE(NULLIF(v_norm->>'noRemunerativo', ''), '0')::numeric, 2);
            v_sac := ROUND(COALESCE(NULLIF(v_norm->>'sacProporcional', ''), '0')::numeric, 2);
            v_sindicato := ROUND(COALESCE(NULLIF(v_norm->>'aporteSindicalObligatorio', ''), '0')::numeric, 2);
            v_faecys := ROUND(COALESCE(NULLIF(v_norm->>'faecys', ''), '0')::numeric, 2);
            v_neto := ROUND(COALESCE(NULLIF(v_norm->>'sueldoNeto', ''), '0')::numeric, 2);

            v_computed_fingerprint := ENCODE(extensions.digest(
              TO_CHAR(v_remunerativo, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_noremunerativo, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_anticipos, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_sac, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_sindicato, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_faecys, 'FM999999999999990.00') || '|' || 
              TO_CHAR(v_neto, 'FM999999999999990.00'),
              'sha256'
            ), 'hex');
          END IF;

        ELSIF v_import_record.source_type = 'BANK_STATEMENT_BBVA' THEN
          -- 013.2 FECHAS BBVA ESTRICTAS
          v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));
          IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN 
            v_fecha := v_fecha_raw::DATE;
            IF TO_CHAR(v_fecha, 'YYYY-MM-DD') != v_fecha_raw THEN v_is_invalid := TRUE; END IF;
          ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN 
            v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
            IF TO_CHAR(v_fecha, 'DD/MM/YYYY') != v_fecha_raw THEN v_is_invalid := TRUE; END IF;
          ELSE 
            v_is_invalid := TRUE; 
          END IF;

          v_fecha_valor_raw := TRIM(COALESCE(v_norm->>'fechaValor', ''));
          IF v_fecha_valor_raw = '' THEN 
            v_fecha_valor := v_fecha;
          ELSIF v_fecha_valor_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN 
            v_fecha_valor := v_fecha_valor_raw::DATE;
            IF TO_CHAR(v_fecha_valor, 'YYYY-MM-DD') != v_fecha_valor_raw THEN v_is_invalid := TRUE; END IF;
          ELSIF v_fecha_valor_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN 
            v_fecha_valor := TO_DATE(v_fecha_valor_raw, 'DD/MM/YYYY');
            IF TO_CHAR(v_fecha_valor, 'DD/MM/YYYY') != v_fecha_valor_raw THEN v_is_invalid := TRUE; END IF;
          ELSE 
            v_is_invalid := TRUE; 
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
            -- 013.2 SIGNALS DETERMINÍSTICAS
            IF jsonb_typeof(v_norm->'signals') = 'array' THEN
              SELECT string_agg(s.val, '|' ORDER BY s.val) INTO v_signals_str
              FROM (
                SELECT DISTINCT UPPER(TRIM(value::text, '"')) AS val
                FROM jsonb_array_elements(v_norm->'signals') 
                WHERE TRIM(value::text, '"') != ''
              ) s;
            END IF;
            
            v_signals_str := COALESCE(v_signals_str, '');

            v_computed_fingerprint := ENCODE(extensions.digest(
              v_descripcion || '|' || TO_CHAR(v_fecha_valor, 'YYYY-MM-DD') || '|' || v_signals_str,
              'sha256'
            ), 'hex');
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_is_invalid := TRUE;
      END;
    END IF;

    IF v_is_invalid THEN
      v_invalid_cnt := v_invalid_cnt + 1;
      v_issue_cnt := v_issue_cnt + 1;
      v_row_status := 'INVALID';
      
      INSERT INTO public.eco_import_rows (
        file_id, organization_id, source_row_number, raw_payload, parse_status, errors, warnings
      ) VALUES (
        v_file_id, v_org_id, (v_row->>'sourceRowNumber')::INT, v_row->'rawRow', v_row_status, COALESCE(v_row->'errors', '[]'::jsonb), COALESCE(v_row->'warnings', '[]'::jsonb)
      ) RETURNING id INTO v_row_id;

      IF v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0 THEN
        FOR v_err IN SELECT * FROM jsonb_array_elements(v_row->'errors')
        LOOP
          INSERT INTO public.eco_import_issues (
            organization_id, import_id, row_id, issue_type, message, details
          ) VALUES (
            v_org_id, p_import_id, v_row_id, 'PARSE_ERROR', v_err#>>'{}', v_row->'errors'
          );
        END LOOP;
      ELSE
        INSERT INTO public.eco_import_issues (
          organization_id, import_id, row_id, issue_type, message
        ) VALUES (
          v_org_id, p_import_id, v_row_id, 'PARSE_ERROR', 'Fila inválida o incompleta'
        );
      END IF;
      CONTINUE;
    END IF;

    -- Duplicados y enmiendas exact match logic
    SELECT id INTO v_existing_fm_id
    FROM public.eco_financial_movements
    WHERE organization_id = v_org_id
      AND identity_key = v_computed_identity_key
      AND financial_fingerprint = v_computed_fingerprint
    LIMIT 1;

    IF v_existing_fm_id IS NOT NULL THEN
      v_duplicate_cnt := v_duplicate_cnt + 1;
      v_row_status := 'EXACT_DUPLICATE';
    ELSE
      SELECT id INTO v_existing_fm_id
      FROM public.eco_financial_movements
      WHERE organization_id = v_org_id
        AND identity_key = v_computed_identity_key
      LIMIT 1;

      IF v_existing_fm_id IS NOT NULL THEN
        v_issue_cnt := v_issue_cnt + 1;
        v_accepted_cnt := v_accepted_cnt + 1;
        v_row_status := 'POSSIBLE_AMENDMENT';
      ELSE
        v_accepted_cnt := v_accepted_cnt + 1;
        v_row_status := 'ACCEPTED';
      END IF;
    END IF;

    INSERT INTO public.eco_import_rows (
      file_id, organization_id, source_row_number, raw_payload, parse_status, errors, warnings
    ) VALUES (
      v_file_id, v_org_id, (v_row->>'sourceRowNumber')::INT, v_row->'rawRow', v_row_status, COALESCE(v_row->'errors', '[]'::jsonb), COALESCE(v_row->'warnings', '[]'::jsonb)
    ) RETURNING id INTO v_row_id;

    IF v_row_status IN ('ACCEPTED', 'POSSIBLE_AMENDMENT') THEN
      INSERT INTO public.eco_financial_movements (
        organization_id, import_id, row_id, source_type, operation_type, status,
        identity_key, financial_fingerprint, normalized_payload,
        fecha, fecha_valor, periodo, descripcion, referencia, account_identifier, movement_type, monto, saldo, created_by
      ) VALUES (
        v_org_id, p_import_id, v_row_id, v_import_record.source_type, v_import_record.operation_type, 'ACTIVE',
        v_computed_identity_key, v_computed_fingerprint, v_norm,
        v_fecha, v_fecha_valor, v_periodo, v_descripcion, v_referencia, v_account_id, v_tipo, v_monto, v_saldo, v_caller_id
      );

      IF v_row_status = 'POSSIBLE_AMENDMENT' THEN
        INSERT INTO public.eco_import_issues (
          organization_id, import_id, row_id, issue_type, message, details
        ) VALUES (
          v_org_id, p_import_id, v_row_id, 'AMENDMENT_DETECTED', 'Posible modificación detectada sobre movimiento financiero existente',
          jsonb_build_object('financial_movement_id', v_existing_fm_id, 'computedFingerprint', v_computed_fingerprint)
        );
      END IF;
    END IF;

  END LOOP;

  UPDATE public.eco_source_imports
  SET status = CASE WHEN v_issue_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
      total_rows = v_total_cnt,
      accepted_rows = v_accepted_cnt,
      invalid_rows = v_invalid_cnt,
      duplicate_rows = v_duplicate_cnt,
      completed_at = NOW()
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
EXCEPTION WHEN OTHERS THEN
  UPDATE public.eco_source_imports SET status = 'PENDING' WHERE id = p_import_id;
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) TO authenticated;

COMMIT;
