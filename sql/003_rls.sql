-- sql/003_rls.sql
-- RLS setup and helpers

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;

CREATE OR REPLACE FUNCTION private.org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT organization_id
    FROM public.eco_user_profiles
    WHERE firebase_uid = auth.jwt()->>'sub';
$$;
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
    WHERE firebase_uid = auth.jwt()->>'sub';
$$;
GRANT EXECUTE ON FUNCTION private.func_role() TO authenticated;

ALTER TABLE public.eco_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_source_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_source_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_normalized_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_import_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_review_actions ENABLE ROW LEVEL SECURITY;
