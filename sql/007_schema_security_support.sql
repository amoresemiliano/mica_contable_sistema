-- sql/007_schema_security_support.sql

ALTER TABLE public.eco_user_profiles
  ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.eco_source_imports
  ADD COLUMN status TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE public.eco_source_imports
  ADD CONSTRAINT eco_source_imports_status_check
  CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED'));

ALTER TABLE public.eco_normalized_records
  ADD COLUMN status TEXT NOT NULL;
ALTER TABLE public.eco_normalized_records
  ADD CONSTRAINT eco_normalized_records_status_check
  CHECK (status IN ('ACCEPTED', 'INVALID', 'EXACT_DUPLICATE', 'POSSIBLE_AMENDMENT'));

ALTER TABLE public.eco_import_issues
  ADD COLUMN status TEXT NOT NULL DEFAULT 'OPEN',
  ADD COLUMN resolution_note TEXT NULL,
  ADD COLUMN resolved_by UUID NULL,
  ADD COLUMN resolved_at TIMESTAMPTZ NULL;
ALTER TABLE public.eco_import_issues
  ADD CONSTRAINT eco_import_issues_status_check
  CHECK (status IN ('OPEN', 'RESOLVED')),
  ADD CONSTRAINT fk_import_issues_resolved_by
  FOREIGN KEY (resolved_by) REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT,
  ADD CONSTRAINT eco_import_issues_resolution_check
  CHECK (
    (status = 'OPEN' AND resolved_by IS NULL AND resolved_at IS NULL) OR
    (status = 'RESOLVED' AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL)
  );

ALTER TABLE public.eco_review_actions
  ADD COLUMN actor_id UUID NOT NULL,
  ADD COLUMN action_type TEXT NOT NULL,
  ADD COLUMN notes TEXT NULL;
ALTER TABLE public.eco_review_actions
  ADD CONSTRAINT fk_review_actions_actor_id
  FOREIGN KEY (actor_id) REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION private.org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT organization_id
    FROM public.eco_user_profiles
    WHERE firebase_uid = auth.jwt()->>'sub'
    AND is_active = TRUE;
$$;
REVOKE ALL ON FUNCTION private.org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.org_id() TO authenticated;

CREATE OR REPLACE FUNCTION private.func_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT role
    FROM public.eco_user_profiles
    WHERE firebase_uid = auth.jwt()->>'sub'
    AND is_active = TRUE;
$$;
REVOKE ALL ON FUNCTION private.func_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.func_role() TO authenticated;
