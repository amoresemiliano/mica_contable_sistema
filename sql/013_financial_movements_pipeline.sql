-- ============================================================
-- MIGRATION 013: PERSISTENT FINANCIAL MOVEMENTS PIPELINE
-- Aconpy & Bank Statements
-- ============================================================

-- ============================================================
-- 1. CREACIÓN DE LA TABLA PRINCIPAL
-- ============================================================

CREATE TABLE IF NOT EXISTS public.eco_financial_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  import_id UUID NOT NULL,
  row_id UUID NOT NULL,

  source_type TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ACTIVE',

  identity_key TEXT NOT NULL,
  financial_fingerprint TEXT NOT NULL,
  normalized_payload JSONB NOT NULL,

  fecha DATE NULL,
  fecha_valor DATE NULL,
  periodo TEXT NULL,

  descripcion TEXT NULL,
  referencia TEXT NULL,
  account_identifier TEXT NULL,

  movement_type TEXT NULL,
  monto NUMERIC(15,2) NULL,
  saldo NUMERIC(15,2) NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NULL,

  -- Foreign Keys
  CONSTRAINT fk_fm_organization FOREIGN KEY (organization_id) REFERENCES public.eco_organizations(id) ON DELETE CASCADE,
  CONSTRAINT fk_fm_import FOREIGN KEY (import_id) REFERENCES public.eco_source_imports(id) ON DELETE CASCADE,
  CONSTRAINT fk_fm_row FOREIGN KEY (row_id) REFERENCES public.eco_import_rows(id) ON DELETE CASCADE,

  -- La clave de unicidad para evitar duplicados y detectar enmiendas
  CONSTRAINT uq_fm_identity UNIQUE (organization_id, identity_key, financial_fingerprint)
);

-- Índices de búsqueda
CREATE INDEX IF NOT EXISTS idx_fm_org ON public.eco_financial_movements(organization_id);
CREATE INDEX IF NOT EXISTS idx_fm_import ON public.eco_financial_movements(import_id);
CREATE INDEX IF NOT EXISTS idx_fm_identity ON public.eco_financial_movements(identity_key);
CREATE INDEX IF NOT EXISTS idx_fm_source_type ON public.eco_financial_movements(source_type);
CREATE INDEX IF NOT EXISTS idx_fm_fecha ON public.eco_financial_movements(fecha);
CREATE INDEX IF NOT EXISTS idx_fm_periodo ON public.eco_financial_movements(periodo);

-- ============================================================
-- 2. SEGURIDAD (RLS)
-- ============================================================

ALTER TABLE public.eco_financial_movements ENABLE ROW LEVEL SECURITY;

-- Select únicamente para la organización actual
CREATE POLICY "Select active financial movements by org"
ON public.eco_financial_movements
FOR SELECT
TO authenticated
USING (organization_id = private.org_id());

-- ============================================================
-- 3. RPC DE PERSISTENCIA
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
  v_accepted_count INT := 0;
  v_invalid_count INT := 0;
  v_duplicate_count INT := 0;
  v_issue_count INT := 0;
  v_row JSONB;
  v_row_id UUID;
  v_existing_fm_id UUID;
  v_existing_fingerprint TEXT;
BEGIN
  -- Autorización
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

  -- Validar longitud del batch (Máximo 500)
  IF jsonb_array_length(p_staged_rows) > 500 THEN
    RAISE EXCEPTION 'Batch size exceeds 500 rows limit';
  END IF;

  -- Actualizar a PROCESSING
  UPDATE public.eco_source_imports
  SET status = 'PROCESSING'
  WHERE id = p_import_id;

  -- File Handling
  IF p_file_info IS NOT NULL AND p_file_info->>'sha256Hash' IS NOT NULL THEN
    SELECT id INTO v_file_id
    FROM public.eco_source_files
    WHERE organization_id = v_org_id AND sha256_hash = p_file_info->>'sha256Hash';

    IF v_file_id IS NULL THEN
      INSERT INTO public.eco_source_files (
        organization_id,
        import_id,
        sha256_hash,
        file_name,
        file_size,
        mime_type,
        storage_path,
        created_by
      ) VALUES (
        v_org_id,
        p_import_id,
        p_file_info->>'sha256Hash',
        p_file_info->>'name',
        (p_file_info->>'size')::BIGINT,
        p_file_info->>'type',
        p_file_info->>'storagePath',
        v_caller_id
      ) RETURNING id INTO v_file_id;
    END IF;
  END IF;

  -- Procesamiento de Filas
  FOR v_row IN SELECT * FROM jsonb_array_elements(p_staged_rows)
  LOOP
    -- Determinar estado inicial
    DECLARE
      v_row_status TEXT := 'ACCEPTED';
      v_is_invalid BOOLEAN := FALSE;
      v_norm JSONB := v_row->'normalizedData';
    BEGIN
      IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' OR jsonb_array_length(v_row->'errors') > 0 THEN
        v_is_invalid := TRUE;
        v_row_status := 'INVALID';
        v_invalid_count := v_invalid_count + 1;
      END IF;

      -- Crear Row Base
      INSERT INTO public.eco_import_rows (
        organization_id,
        import_id,
        source_row_number,
        raw_payload,
        parse_status,
        created_by
      ) VALUES (
        v_org_id,
        p_import_id,
        (v_row->>'sourceRowNumber')::INT,
        (v_row->>'rawRow')::JSONB,
        v_row_status,
        v_caller_id
      ) RETURNING id INTO v_row_id;

      -- Registrar Issues
      IF v_is_invalid THEN
        DECLARE v_err JSONB;
        BEGIN
          FOR v_err IN SELECT * FROM jsonb_array_elements(v_row->'errors')
          LOOP
            INSERT INTO public.eco_import_issues (
              organization_id, import_id, row_id, issue_type, severity, description
            ) VALUES (
              v_org_id, p_import_id, v_row_id, 'PARSE_ERROR', 'ERROR', v_err#>>'{}'
            );
          END LOOP;
          v_issue_count := v_issue_count + 1;
        END;
        CONTINUE; -- Saltar el resto del proceso para inválidos
      END IF;

      -- Verificación de duplicados/enmiendas
      SELECT id, financial_fingerprint INTO v_existing_fm_id, v_existing_fingerprint
      FROM public.eco_financial_movements
      WHERE organization_id = v_org_id
        AND identity_key = (v_row->>'identityKey')
      LIMIT 1;

      IF v_existing_fm_id IS NOT NULL THEN
        IF v_existing_fingerprint = (v_row->>'financialFingerprint') THEN
          v_duplicate_count := v_duplicate_count + 1;
          UPDATE public.eco_import_rows SET parse_status = 'EXACT_DUPLICATE' WHERE id = v_row_id;
          CONTINUE;
        ELSE
          v_issue_count := v_issue_count + 1;
          v_accepted_count := v_accepted_count + 1;
          UPDATE public.eco_import_rows SET parse_status = 'POSSIBLE_AMENDMENT' WHERE id = v_row_id;
          INSERT INTO public.eco_import_issues (
            organization_id, import_id, row_id, issue_type, severity, description
          ) VALUES (
            v_org_id, p_import_id, v_row_id, 'AMENDMENT_DETECTED', 'WARNING', 'Posible modificación detectada sobre movimiento existente'
          );
        END IF;
      ELSE
        v_accepted_count := v_accepted_count + 1;
      END IF;

      -- Inserción Final
      INSERT INTO public.eco_financial_movements (
        organization_id,
        import_id,
        row_id,
        source_type,
        operation_type,
        status,
        identity_key,
        financial_fingerprint,
        normalized_payload,
        fecha,
        fecha_valor,
        periodo,
        descripcion,
        referencia,
        account_identifier,
        movement_type,
        monto,
        saldo,
        created_by
      ) VALUES (
        v_org_id,
        p_import_id,
        v_row_id,
        v_import_record.source_type,
        v_import_record.operation_type,
        'ACTIVE',
        v_row->>'identityKey',
        v_row->>'financialFingerprint',
        v_norm,
        (v_norm->>'fecha')::DATE,
        (v_norm->>'fechaValor')::DATE,
        v_norm->>'periodo',
        v_norm->>'descripcion',
        v_norm->>'referencia',
        v_norm->>'accountIdentifier',
        v_norm->>'tipo',
        (v_norm->>'monto')::NUMERIC(15,2),
        (v_norm->>'saldo')::NUMERIC(15,2),
        v_caller_id
      );
    END;
  END LOOP;

  -- Finalizar
  UPDATE public.eco_source_imports
  SET status = CASE WHEN v_issue_count > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
      completed_at = NOW()
  WHERE id = p_import_id;

  RETURN jsonb_build_object(
    'import_id', p_import_id,
    'total_rows', jsonb_array_length(p_staged_rows),
    'accepted_rows', v_accepted_count,
    'invalid_rows', v_invalid_count,
    'duplicate_rows', v_duplicate_count,
    'issue_rows', v_issue_count,
    'status', CASE WHEN v_issue_count > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
  );
EXCEPTION WHEN OTHERS THEN
  UPDATE public.eco_source_imports SET status = 'PENDING' WHERE id = p_import_id;
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) TO authenticated;

-- ============================================================
-- 4. RPC DE LECTURA (GET_ACTIVE_FINANCIAL_MOVEMENTS)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_active_financial_movements()
RETURNS SETOF public.eco_financial_movements
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_financial_movements
  WHERE organization_id = private.org_id()
    AND status = 'ACTIVE';
$$;

REVOKE ALL ON FUNCTION public.get_active_financial_movements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_financial_movements() TO authenticated;
