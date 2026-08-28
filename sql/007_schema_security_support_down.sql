-- sql/007_schema_security_support_down.sql

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
    LIMIT 1;
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
    LIMIT 1;
$$;
REVOKE ALL ON FUNCTION private.func_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.func_role() TO authenticated;

ALTER TABLE public.eco_review_actions
  DROP CONSTRAINT IF EXISTS fk_review_actions_actor_id;

ALTER TABLE public.eco_review_actions
  DROP COLUMN IF EXISTS notes,
  DROP COLUMN IF EXISTS action_type,
  DROP COLUMN IF EXISTS actor_id;

ALTER TABLE public.eco_import_issues
  DROP CONSTRAINT IF EXISTS eco_import_issues_resolution_check,
  DROP CONSTRAINT IF EXISTS fk_import_issues_resolved_by,
  DROP CONSTRAINT IF EXISTS eco_import_issues_status_check;

ALTER TABLE public.eco_import_issues
  DROP COLUMN IF EXISTS resolved_at,
  DROP COLUMN IF EXISTS resolved_by,
  DROP COLUMN IF EXISTS resolution_note,
  DROP COLUMN IF EXISTS status;

ALTER TABLE public.eco_normalized_records
  DROP CONSTRAINT IF EXISTS eco_normalized_records_status_check;

ALTER TABLE public.eco_normalized_records
  DROP COLUMN IF EXISTS status;

ALTER TABLE public.eco_source_imports
  DROP CONSTRAINT IF EXISTS eco_source_imports_status_check;

ALTER TABLE public.eco_source_imports
  DROP COLUMN IF EXISTS status;

ALTER TABLE public.eco_user_profiles
  DROP COLUMN IF EXISTS is_active;
