BEGIN;

-- ============================================================
-- MIGRATION 022: WP-A3.2.1 IDENTITY, PROFILES & ORG ADMIN CUTOVER
-- ============================================================
-- Cuts over user role modification, user activation, superadmin
-- context switching, and organization/profile/audit RLS policies
-- to the frozen M019/M021 capability foundation.
-- ============================================================

-- ============================================================
-- 1. RPC: change_user_role
-- ============================================================
-- Governed by ORG_MEMBER_PERMISSION_MANAGE capability.
-- Enforces same-org authorization, fail-closed inactive checks,
-- and prevents self-role modification.

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
  v_target_org_id UUID;
BEGIN
  -- 1. Resolve caller profile ID via canonical helper (requires is_active = TRUE)
  v_caller_id := private.current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- 2. Prevent self-role modification
  IF target_user_id = v_caller_id THEN
    RAISE EXCEPTION 'SELF_ROLE_CHANGE_NOT_ALLOWED';
  END IF;

  -- 3. Validate requested role string
  IF new_role NOT IN ('USER', 'UPLOADER', 'REVIEWER', 'ADMIN') THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  -- 4. Lookup active target profile and target organization
  SELECT organization_id
  INTO v_target_org_id
  FROM public.eco_user_profiles
  WHERE id = target_user_id
    AND is_active = TRUE;

  IF v_target_org_id IS NULL THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  -- 5. Enforce capability in target organization
  IF NOT private.can_org(v_target_org_id, 'ORG_MEMBER_PERMISSION_MANAGE') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- 6. Atomic role update
  UPDATE public.eco_user_profiles
  SET role = new_role
  WHERE id = target_user_id
    AND organization_id = v_target_org_id
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  -- 7. Audit log event
  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_target_org_id,
    'USER_ROLE_CHANGED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.change_user_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_user_role(UUID, TEXT) TO authenticated;


-- ============================================================
-- 2. RPC: set_user_active
-- ============================================================
-- Governed by ORG_MEMBER_MANAGE capability.
-- Enforces same-org authorization, fail-closed inactive checks,
-- and prevents self-deactivation.

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
  v_target_org_id UUID;
  v_current_state BOOLEAN;
BEGIN
  -- 1. Resolve caller profile ID via canonical helper (requires is_active = TRUE)
  v_caller_id := private.current_profile_id();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  -- 2. Prevent self-deactivation
  IF target_user_id = v_caller_id AND new_active = FALSE THEN
    RAISE EXCEPTION 'SELF_DEACTIVATION_NOT_ALLOWED';
  END IF;

  -- 3. Lookup target profile state and organization
  SELECT is_active, organization_id
  INTO v_current_state, v_target_org_id
  FROM public.eco_user_profiles
  WHERE id = target_user_id;

  IF v_current_state IS NULL THEN
    RAISE EXCEPTION 'TARGET_NOT_FOUND';
  END IF;

  -- 4. Enforce capability in target organization
  IF v_target_org_id IS NULL OR NOT private.can_org(v_target_org_id, 'ORG_MEMBER_MANAGE') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- 5. Idempotent short-circuit
  IF v_current_state = new_active THEN
    RETURN;
  END IF;

  -- 6. Atomic status update
  UPDATE public.eco_user_profiles
  SET is_active = new_active
  WHERE id = target_user_id;

  -- 7. Audit log event
  INSERT INTO public.eco_audit_events (
    organization_id,
    event_type
  )
  VALUES (
    v_target_org_id,
    'USER_ACTIVE_CHANGED'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_active(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_active(UUID, BOOLEAN) TO authenticated;


-- ============================================================
-- 3. RPC: switch_superadmin_org_context
-- ============================================================
-- Governed by SUPPORT_IMPERSONATE / ACCESS_ANY_ORG platform capabilities.
-- Syncs both legacy eco_user_profiles.organization_id and canonical
-- eco_user_active_context.

CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context(
  p_org_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id UUID;
BEGIN
  -- 1. Enforce platform capabilities
  IF NOT (private.can_platform('SUPPORT_IMPERSONATE') OR private.can_platform('ACCESS_ANY_ORG')) THEN
    RAISE EXCEPTION 'Unauthorized: Only SUPERADMIN can switch organization context';
  END IF;

  -- 2. Verify target organization exists if not NULL
  IF p_org_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id) THEN
      RAISE EXCEPTION 'Invalid organization ID';
    END IF;
  END IF;

  -- 3. Resolve caller profile
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found or inactive';
  END IF;

  -- 4. Maintain legacy column for frontend session compatibility until A3.3
  UPDATE public.eco_user_profiles
  SET organization_id = p_org_id
  WHERE id = v_caller_id;

  -- 5. Upsert canonical active context
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_caller_id, p_org_id, now())
  ON CONFLICT (user_profile_id)
  DO UPDATE SET organization_id = EXCLUDED.organization_id, updated_at = now();

  -- 6. Audit log event
  IF p_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (p_org_id, 'SUPERADMIN_ORG_CONTEXT_SWITCHED');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.switch_superadmin_org_context(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.switch_superadmin_org_context(UUID) TO authenticated;


-- ============================================================
-- 4. RLS POLICIES
-- ============================================================

-- A. eco_organizations: Governed by ORG_VIEW capability (set-based)
ALTER TABLE public.eco_organizations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;

CREATE POLICY "Organizations viewable by own users"
ON public.eco_organizations
FOR SELECT
TO authenticated
USING (
  id IN (
    SELECT private.authorized_orgs_for_capability('ORG_VIEW')
  )
);

-- B. eco_user_profiles: Self-read + canonical membership ORG_MEMBER_VIEW
ALTER TABLE public.eco_user_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Profiles viewable by user and admin" ON public.eco_user_profiles;

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
  EXISTS (
    SELECT 1
    FROM public.eco_organization_members m
    WHERE m.user_profile_id = eco_user_profiles.id
      AND m.is_active = TRUE
      AND m.organization_id IN (
        SELECT private.authorized_orgs_for_capability('ORG_MEMBER_VIEW')
      )
  )
);

-- C. eco_audit_events: Governed by AUDIT_VIEW_ORG capability (set-based)
ALTER TABLE public.eco_audit_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Audit events viewable by admin" ON public.eco_audit_events;

CREATE POLICY "Audit events viewable by admin"
ON public.eco_audit_events
FOR SELECT
TO authenticated
USING (
  organization_id IN (
    SELECT private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')
  )
);

COMMIT;
