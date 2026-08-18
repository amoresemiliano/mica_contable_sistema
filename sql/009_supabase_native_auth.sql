BEGIN;

-- ============================================================
-- 009 — MIGRACIÓN A SUPABASE AUTH NATIVO
-- MICA
--
-- Objetivos:
-- 1. Eliminar firebase_uid.
-- 2. Vincular eco_user_profiles con auth.users(id).
-- 3. Usar auth.uid() en helpers, RLS y RPCs.
-- 4. Mantener fail-closed mediante is_active.
-- 5. Mantener la API existente de las RPCs de 008.
-- 6. Adaptar auditoría al esquema REAL de eco_audit_events:
--      organization_id
--      event_type
-- ============================================================


-- ============================================================
-- 1. ELIMINAR POLICY QUE DEPENDE DE firebase_uid
-- ============================================================

DROP POLICY IF EXISTS "Profiles viewable by user and admin"
ON public.eco_user_profiles;


-- ============================================================
-- 2. REEMPLAZAR IDENTIDAD FIREBASE POR SUPABASE AUTH
-- ============================================================

ALTER TABLE public.eco_user_profiles
  DROP COLUMN firebase_uid;

ALTER TABLE public.eco_user_profiles
  ADD COLUMN auth_user_id UUID NOT NULL UNIQUE;

ALTER TABLE public.eco_user_profiles
  ADD CONSTRAINT eco_user_profiles_auth_user_id_fkey
  FOREIGN KEY (auth_user_id)
  REFERENCES auth.users(id)
  ON DELETE RESTRICT;


-- ============================================================
-- 3. HELPERS PRIVADOS DE CONTEXTO
-- ============================================================

CREATE OR REPLACE FUNCTION private.org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT organization_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;
$$;


CREATE OR REPLACE FUNCTION private.func_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT role
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;
$$;


-- ============================================================
-- 4. RLS — PERFILES
-- ============================================================

CREATE POLICY "Profiles viewable by user and admin"
ON public.eco_user_profiles
FOR SELECT
TO authenticated
USING (
  (
    auth_user_id = auth.uid()
    AND is_active = TRUE
  )
  OR
  (
    private.func_role() = 'ADMIN'
    AND organization_id = private.org_id()
  )
);


-- ============================================================
-- 5. RPC — change_user_role
--
-- Se conservan exactamente los nombres de parámetros de 008:
--   target_user_id
--   new_role
-- ============================================================

CREATE OR REPLACE FUNCTION public.change_user_role(
  target_user_id UUID,
  new_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id UUID;
  v_org_id UUID;
BEGIN
  SELECT id, organization_id
  INTO v_caller_id, v_org_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  IF private.func_role() <> 'ADMIN' THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF target_user_id = v_caller_id THEN
    RAISE EXCEPTION 'SELF_ROLE_CHANGE_NOT_ALLOWED';
  END IF;

  IF new_role NOT IN ('USER', 'UPLOADER', 'REVIEWER', 'ADMIN') THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  UPDATE public.eco_user_profiles
  SET role = new_role
  WHERE id = target_user_id
    AND organization_id = v_org_id
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_org_id,
    'USER_ROLE_CHANGED'
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.change_user_role(UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.change_user_role(UUID, TEXT)
TO authenticated;


-- ============================================================
-- 6. RPC — set_user_active
--
-- Se conservan exactamente los nombres de parámetros de 008:
--   target_user_id
--   new_active
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_user_active(
  target_user_id UUID,
  new_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id UUID;
  v_org_id UUID;
  v_current_state BOOLEAN;
BEGIN
  SELECT id, organization_id
  INTO v_caller_id, v_org_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  IF private.func_role() <> 'ADMIN' THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF target_user_id = v_caller_id
     AND new_active = FALSE THEN
    RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED';
  END IF;

  SELECT is_active
  INTO v_current_state
  FROM public.eco_user_profiles
  WHERE id = target_user_id
    AND organization_id = v_org_id;

  IF v_current_state IS NULL THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  -- Idempotencia: no hacer nada si ya tiene ese estado
  IF v_current_state = new_active THEN
    RETURN;
  END IF;

  UPDATE public.eco_user_profiles
  SET is_active = new_active
  WHERE id = target_user_id
    AND organization_id = v_org_id;

  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_org_id,
    'USER_ACTIVE_CHANGED'
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.set_user_active(UUID, BOOLEAN)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.set_user_active(UUID, BOOLEAN)
TO authenticated;


-- ============================================================
-- 7. RPC — create_import
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_import()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

  SELECT id
  INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid user profile';
  END IF;

  INSERT INTO public.eco_source_imports (
    organization_id,
    status
  )
  VALUES (
    v_org_id,
    'PENDING'
  )
  RETURNING id INTO v_import_id;

  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_org_id,
    'IMPORT_CREATED'
  );

  RETURN v_import_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_import()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.create_import()
TO authenticated;


-- ============================================================
-- 8. RPC — resolve_issue
--
-- Se conservan exactamente los nombres de parámetros de 008:
--   target_issue_id
--   res_note
-- ============================================================

CREATE OR REPLACE FUNCTION public.resolve_issue(
  target_issue_id UUID,
  res_note TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

  SELECT id
  INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid()
    AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid user profile';
  END IF;

  SELECT i.organization_id
  INTO v_issue_org_id
  FROM public.eco_import_issues iss
  JOIN public.eco_normalized_records nr
    ON iss.record_id = nr.id
  JOIN public.eco_import_rows ir
    ON nr.row_id = ir.id
  JOIN public.eco_source_files sf
    ON ir.file_id = sf.id
  JOIN public.eco_source_imports i
    ON sf.import_id = i.id
  WHERE iss.id = target_issue_id;

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
  WHERE id = target_issue_id
    AND status = 'OPEN';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Issue is already resolved or no longer OPEN';
  END IF;

  INSERT INTO public.eco_review_actions (
    issue_id,
    actor_id,
    action_type,
    notes
  )
  VALUES (
    target_issue_id,
    v_caller_id,
    'ISSUE_RESOLVED',
    res_note
  );

  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_org_id,
    'ISSUE_RESOLVED'
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.resolve_issue(UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.resolve_issue(UUID, TEXT)
TO authenticated;


COMMIT;