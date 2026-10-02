BEGIN;

-- 1. Revertir RPCs y Grants
DROP FUNCTION IF EXISTS public.get_active_normalized_records();
DROP FUNCTION IF EXISTS public.check_file_importable(text);
DROP FUNCTION IF EXISTS public.persist_import_batch(uuid, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.create_import(text, text);

-- Restaurar create_import original
CREATE OR REPLACE FUNCTION public.create_import()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_caller_id UUID;
  v_import_id UUID;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('UPLOADER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires UPLOADER or ADMIN role'; END IF;

  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid user profile'; END IF;

  INSERT INTO public.eco_source_imports (organization_id, status) VALUES (v_org_id, 'PENDING') RETURNING id INTO v_import_id;
  INSERT INTO public.eco_audit_events (organization_id, event_type) VALUES (v_org_id, 'IMPORT_CREATED');
  RETURN v_import_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_import() TO authenticated;

-- Restaurar private.has_issue_access original
CREATE OR REPLACE FUNCTION private.has_issue_access(p_issue_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eco_import_issues iss
    JOIN public.eco_normalized_records nr ON iss.record_id = nr.id
    JOIN public.eco_import_rows ir ON nr.row_id = ir.id
    JOIN public.eco_source_files sf ON ir.file_id = sf.id
    JOIN public.eco_source_imports si ON sf.import_id = si.id
    WHERE iss.id = p_issue_id AND si.organization_id = private.org_id()
  );
$$;

-- Restaurar public.resolve_issue original
CREATE OR REPLACE FUNCTION public.resolve_issue(target_issue_id UUID, res_note TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE
  v_org_id UUID; v_caller_role TEXT; v_caller_id UUID; v_issue_org_id UUID;
BEGIN
  v_org_id := private.org_id(); v_caller_role := private.func_role();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;

  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  SELECT i.organization_id INTO v_issue_org_id
  FROM public.eco_import_issues iss
  JOIN public.eco_normalized_records nr ON iss.record_id = nr.id
  JOIN public.eco_import_rows ir ON nr.row_id = ir.id
  JOIN public.eco_source_files sf ON ir.file_id = sf.id
  JOIN public.eco_source_imports i ON sf.import_id = i.id
  WHERE iss.id = target_issue_id;

  IF v_issue_org_id IS NULL THEN RAISE EXCEPTION 'Issue not found'; END IF;
  IF v_issue_org_id != v_org_id THEN RAISE EXCEPTION 'Unauthorized: Issue belongs to another organization'; END IF;

  UPDATE public.eco_import_issues SET status = 'RESOLVED', resolved_by = v_caller_id, resolved_at = NOW(), resolution_note = res_note WHERE id = target_issue_id AND status = 'OPEN';
  IF NOT FOUND THEN RAISE EXCEPTION 'Issue is already resolved or no longer OPEN'; END IF;

  INSERT INTO public.eco_review_actions (issue_id, actor_id, action_type, notes) VALUES (target_issue_id, v_caller_id, 'ISSUE_RESOLVED', res_note);
  INSERT INTO public.eco_audit_events (organization_id, event_type) VALUES (v_org_id, 'ISSUE_RESOLVED');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_issue(UUID, TEXT) TO authenticated;

-- 2. Eliminar índices agregados
DROP INDEX IF EXISTS public.idx_normalized_org_identity_fingerprint;
DROP INDEX IF EXISTS public.idx_normalized_org_lookup;
DROP INDEX IF EXISTS public.idx_source_files_org_hash;

-- 3. Restaurar Policies
DROP POLICY IF EXISTS "Records viewable by org" ON public.eco_normalized_records;
CREATE POLICY "Records viewable by org" ON public.eco_normalized_records FOR SELECT TO authenticated USING (private.has_record_access(id));

DROP POLICY IF EXISTS "Issues viewable by org" ON public.eco_import_issues;
CREATE POLICY "Issues viewable by org" ON public.eco_import_issues FOR SELECT TO authenticated USING (private.has_issue_access(id));

-- 4. Revertir columnas de eco_import_issues
ALTER TABLE public.eco_import_issues
  DROP COLUMN IF EXISTS organization_id,
  DROP COLUMN IF EXISTS import_id,
  DROP COLUMN IF EXISTS row_id,
  DROP COLUMN IF EXISTS issue_type,
  DROP COLUMN IF EXISTS message,
  DROP COLUMN IF EXISTS details;

-- 5. Revertir columnas de eco_normalized_records
ALTER TABLE public.eco_normalized_records
  DROP COLUMN IF EXISTS organization_id,
  DROP COLUMN IF EXISTS record_type,
  DROP COLUMN IF EXISTS identity_key,
  DROP COLUMN IF EXISTS fiscal_fingerprint,
  DROP COLUMN IF EXISTS normalized_payload,
  DROP COLUMN IF EXISTS fecha,
  DROP COLUMN IF EXISTS cuit,
  DROP COLUMN IF EXISTS razon_social,
  DROP COLUMN IF EXISTS comprobante,
  DROP COLUMN IF EXISTS total,
  DROP COLUMN IF EXISTS tipo_operacion,
  DROP COLUMN IF EXISTS categoria,
  DROP COLUMN IF EXISTS confirmada;

-- 6. Revertir columnas de eco_import_rows
ALTER TABLE public.eco_import_rows
  DROP COLUMN IF EXISTS organization_id,
  DROP COLUMN IF EXISTS source_row_number,
  DROP COLUMN IF EXISTS raw_payload,
  DROP COLUMN IF EXISTS parse_status,
  DROP COLUMN IF EXISTS errors,
  DROP COLUMN IF EXISTS warnings;

-- 7. Revertir columnas de eco_source_files
ALTER TABLE public.eco_source_files
  DROP COLUMN IF EXISTS organization_id,
  DROP COLUMN IF EXISTS original_name,
  DROP COLUMN IF EXISTS storage_path,
  DROP COLUMN IF EXISTS mime_type,
  DROP COLUMN IF EXISTS size_bytes,
  DROP COLUMN IF EXISTS sha256_hash,
  DROP COLUMN IF EXISTS source_type;

-- 8. Revertir columnas y check de eco_source_imports
ALTER TABLE public.eco_source_imports
  DROP CONSTRAINT IF EXISTS chk_import_status,
  DROP CONSTRAINT IF EXISTS chk_import_op_type,
  DROP COLUMN IF EXISTS source_type,
  DROP COLUMN IF EXISTS operation_type,
  DROP COLUMN IF EXISTS total_rows,
  DROP COLUMN IF EXISTS accepted_rows,
  DROP COLUMN IF EXISTS invalid_rows,
  DROP COLUMN IF EXISTS duplicate_rows,
  DROP COLUMN IF EXISTS started_at,
  DROP COLUMN IF EXISTS completed_at,
  DROP COLUMN IF EXISTS created_by;

ALTER TABLE public.eco_source_imports
  ADD CONSTRAINT eco_source_imports_status_check CHECK (status = ANY (ARRAY['PENDING'::text, 'PROCESSING'::text, 'COMPLETED'::text, 'FAILED'::text]));

COMMIT;
