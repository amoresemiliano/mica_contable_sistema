-- sql/008_functional_policies.sql

-- 1. REVOKE DIRECT MUTATIONS FROM AUTHENTICATED
REVOKE INSERT, UPDATE, DELETE ON public.eco_organizations FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_user_profiles FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_source_imports FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_source_files FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_import_rows FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_normalized_records FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_import_issues FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_review_actions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.eco_audit_events FROM authenticated;

-- Ensure SELECT is granted only where needed (no SELECT for eco_import_rows)
GRANT SELECT ON public.eco_organizations TO authenticated;
GRANT SELECT ON public.eco_user_profiles TO authenticated;
GRANT SELECT ON public.eco_source_imports TO authenticated;
GRANT SELECT ON public.eco_source_files TO authenticated;
REVOKE SELECT ON public.eco_import_rows FROM authenticated; -- Denied explicitly
GRANT SELECT ON public.eco_normalized_records TO authenticated;
GRANT SELECT ON public.eco_import_issues TO authenticated;
GRANT SELECT ON public.eco_review_actions TO authenticated;
GRANT SELECT ON public.eco_audit_events TO authenticated;

-- 2. DROP BOOTSTRAP POLICIES THAT ARE NO LONGER NEEDED (PREVENT PERMISSIVE OVERLAP)
DROP POLICY IF EXISTS "Audit events viewable by org" ON public.eco_audit_events;
DROP POLICY IF EXISTS "Audit events insertable by org" ON public.eco_audit_events;

-- Drop previous bad 008 iterations just in case
DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;
DROP POLICY IF EXISTS "Profiles viewable by user and admin" ON public.eco_user_profiles;
DROP POLICY IF EXISTS "Imports viewable by org" ON public.eco_source_imports;
DROP POLICY IF EXISTS "Files viewable by org" ON public.eco_source_files;
DROP POLICY IF EXISTS "Rows viewable by org" ON public.eco_import_rows;
DROP POLICY IF EXISTS "Records viewable by org" ON public.eco_normalized_records;
DROP POLICY IF EXISTS "Issues viewable by org" ON public.eco_import_issues;
DROP POLICY IF EXISTS "Review actions viewable by org" ON public.eco_review_actions;
DROP POLICY IF EXISTS "Audit events viewable by admin" ON public.eco_audit_events;


-- 3. CREATE PRIVATE HELPERS FOR RLS
-- These helpers bypass RLS and row-level grants because they run as SECURITY DEFINER.
-- They prevent the caller from needing direct SELECT access to eco_import_rows.

CREATE OR REPLACE FUNCTION private.has_record_access(p_record_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eco_normalized_records nr
    JOIN public.eco_import_rows ir ON nr.row_id = ir.id
    JOIN public.eco_source_files sf ON ir.file_id = sf.id
    JOIN public.eco_source_imports si ON sf.import_id = si.id
    WHERE nr.id = p_record_id AND si.organization_id = private.org_id()
  );
$$;
REVOKE ALL ON FUNCTION private.has_record_access(UUID) FROM PUBLIC;
-- Granted to authenticated because PostgreSQL evaluates RLS as the calling user.
GRANT EXECUTE ON FUNCTION private.has_record_access(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION private.has_issue_access(p_issue_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER STABLE
SET search_path = ''
AS $$
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
REVOKE ALL ON FUNCTION private.has_issue_access(UUID) FROM PUBLIC;
-- Granted to authenticated because PostgreSQL evaluates RLS as the calling user.
GRANT EXECUTE ON FUNCTION private.has_issue_access(UUID) TO authenticated;


-- 4. CREATE NEW STRICT SELECT POLICIES

CREATE POLICY "Organizations viewable by own users" ON public.eco_organizations
FOR SELECT TO authenticated USING (id = private.org_id());

CREATE POLICY "Profiles viewable by user and admin" ON public.eco_user_profiles
FOR SELECT TO authenticated USING (
  (firebase_uid = auth.jwt()->>'sub' AND is_active = true) OR
  (private.func_role() = 'ADMIN' AND organization_id = private.org_id())
);

CREATE POLICY "Imports viewable by org" ON public.eco_source_imports
FOR SELECT TO authenticated USING (organization_id = private.org_id());

CREATE POLICY "Files viewable by org" ON public.eco_source_files
FOR SELECT TO authenticated USING (
  import_id IN (SELECT id FROM public.eco_source_imports WHERE organization_id = private.org_id())
);

-- Note: No policy for eco_import_rows, remains locked by default for authenticated

CREATE POLICY "Records viewable by org" ON public.eco_normalized_records
FOR SELECT TO authenticated USING (private.has_record_access(id));

CREATE POLICY "Issues viewable by org" ON public.eco_import_issues
FOR SELECT TO authenticated USING (private.has_issue_access(id));

CREATE POLICY "Review actions viewable by org" ON public.eco_review_actions
FOR SELECT TO authenticated USING (private.has_issue_access(issue_id));

CREATE POLICY "Audit events viewable by admin" ON public.eco_audit_events
FOR SELECT TO authenticated USING (
  organization_id = private.org_id() AND private.func_role() = 'ADMIN'
);

-- 5. CREATE MUTATION RPCS

CREATE OR REPLACE FUNCTION public.change_user_role(target_user_id UUID, new_role TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_org_id UUID;
    v_caller_role TEXT;
    v_caller_id UUID;
BEGIN
    v_org_id := private.org_id();
    v_caller_role := private.func_role();

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Invalid organization';
    END IF;

    IF v_caller_role != 'ADMIN' THEN
        RAISE EXCEPTION 'Unauthorized: Requires ADMIN role';
    END IF;

    IF new_role NOT IN ('USER', 'UPLOADER', 'REVIEWER', 'ADMIN') THEN
        RAISE EXCEPTION 'Invalid role specified';
    END IF;

    SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE firebase_uid = auth.jwt()->>'sub' AND is_active = TRUE;

    IF target_user_id = v_caller_id THEN
        RAISE EXCEPTION 'Cannot change your own role';
    END IF;

    UPDATE public.eco_user_profiles
    SET role = new_role
    WHERE id = target_user_id AND organization_id = v_org_id AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user not found, inactive, or not in your organization';
    END IF;

    INSERT INTO public.eco_audit_events (organization_id, action_type, entity_name, entity_id, actor_id, payload)
    VALUES (v_org_id, 'ROLE_CHANGE', 'eco_user_profiles', target_user_id, v_caller_id, jsonb_build_object('new_role', new_role));
END;
$$;
REVOKE ALL ON FUNCTION public.change_user_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_user_role(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_user_active(target_user_id UUID, new_active BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_org_id UUID;
    v_caller_role TEXT;
    v_caller_id UUID;
    v_target_active BOOLEAN;
BEGIN
    v_org_id := private.org_id();
    v_caller_role := private.func_role();

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Invalid organization';
    END IF;

    IF v_caller_role != 'ADMIN' THEN
        RAISE EXCEPTION 'Unauthorized: Requires ADMIN role';
    END IF;

    SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE firebase_uid = auth.jwt()->>'sub' AND is_active = TRUE;

    IF target_user_id = v_caller_id THEN
        RAISE EXCEPTION 'Cannot deactivate yourself';
    END IF;

    SELECT is_active INTO v_target_active
    FROM public.eco_user_profiles
    WHERE id = target_user_id AND organization_id = v_org_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user not found or not in your organization';
    END IF;

    IF v_target_active = new_active THEN
        -- Idempotent return without auditing if the state didn't change
        RETURN;
    END IF;

    UPDATE public.eco_user_profiles
    SET is_active = new_active
    WHERE id = target_user_id;

    INSERT INTO public.eco_audit_events (organization_id, action_type, entity_name, entity_id, actor_id, payload)
    VALUES (v_org_id, 'STATUS_CHANGE', 'eco_user_profiles', target_user_id, v_caller_id, jsonb_build_object('is_active', new_active));
END;
$$;
REVOKE ALL ON FUNCTION public.set_user_active(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_active(UUID, BOOLEAN) TO authenticated;

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

    SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE firebase_uid = auth.jwt()->>'sub' AND is_active = TRUE;

    INSERT INTO public.eco_source_imports (organization_id, status)
    VALUES (v_org_id, 'PENDING')
    RETURNING id INTO v_import_id;

    INSERT INTO public.eco_audit_events (organization_id, action_type, entity_name, entity_id, actor_id, payload)
    VALUES (v_org_id, 'IMPORT_CREATED', 'eco_source_imports', v_import_id, v_caller_id, '{}'::jsonb);

    RETURN v_import_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_import() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_import() TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_issue(target_issue_id UUID, res_note TEXT)
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

    SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE firebase_uid = auth.jwt()->>'sub' AND is_active = TRUE;

    SELECT i.organization_id INTO v_issue_org_id
    FROM public.eco_import_issues iss
    JOIN public.eco_normalized_records nr ON iss.record_id = nr.id
    JOIN public.eco_import_rows ir ON nr.row_id = ir.id
    JOIN public.eco_source_files sf ON ir.file_id = sf.id
    JOIN public.eco_source_imports i ON sf.import_id = i.id
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
    WHERE id = target_issue_id AND status = 'OPEN';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Issue is already resolved or no longer OPEN';
    END IF;

    INSERT INTO public.eco_review_actions (issue_id, actor_id, action_type, notes)
    VALUES (target_issue_id, v_caller_id, 'ISSUE_RESOLVED', res_note);

    INSERT INTO public.eco_audit_events (organization_id, action_type, entity_name, entity_id, actor_id, payload)
    VALUES (v_org_id, 'ISSUE_RESOLVED', 'eco_import_issues', target_issue_id, v_caller_id, jsonb_build_object('resolution', res_note));
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_issue(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_issue(UUID, TEXT) TO authenticated;
