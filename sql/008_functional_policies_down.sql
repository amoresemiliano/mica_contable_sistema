-- sql/008_functional_policies_down.sql

DROP FUNCTION IF EXISTS public.change_user_role(UUID, TEXT);
DROP FUNCTION IF EXISTS public.set_user_active(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.create_import();
DROP FUNCTION IF EXISTS public.resolve_issue(UUID, TEXT);
DROP FUNCTION IF EXISTS private.has_record_access(UUID);
DROP FUNCTION IF EXISTS private.has_issue_access(UUID);

DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;
DROP POLICY IF EXISTS "Profiles viewable by user and admin" ON public.eco_user_profiles;
DROP POLICY IF EXISTS "Imports viewable by org" ON public.eco_source_imports;
DROP POLICY IF EXISTS "Files viewable by org" ON public.eco_source_files;
DROP POLICY IF EXISTS "Records viewable by org" ON public.eco_normalized_records;
DROP POLICY IF EXISTS "Issues viewable by org" ON public.eco_import_issues;
DROP POLICY IF EXISTS "Review actions viewable by org" ON public.eco_review_actions;
DROP POLICY IF EXISTS "Audit events viewable by admin" ON public.eco_audit_events;

-- Restore Bootstrap policies that were explicitly removed in 008
CREATE POLICY "Audit events viewable by org" ON public.eco_audit_events FOR SELECT TO authenticated USING (organization_id = private.org_id());
CREATE POLICY "Audit events insertable by org" ON public.eco_audit_events FOR INSERT TO authenticated WITH CHECK (organization_id = private.org_id());

-- Restore default GRANTS (all operations) exact ACL post-007
GRANT ALL ON public.eco_organizations TO authenticated;
GRANT ALL ON public.eco_user_profiles TO authenticated;
GRANT ALL ON public.eco_source_imports TO authenticated;
GRANT ALL ON public.eco_source_files TO authenticated;
GRANT ALL ON public.eco_import_rows TO authenticated;
GRANT ALL ON public.eco_normalized_records TO authenticated;
GRANT ALL ON public.eco_import_issues TO authenticated;
GRANT ALL ON public.eco_review_actions TO authenticated;
GRANT ALL ON public.eco_audit_events TO authenticated;
