BEGIN;

-- ============================================================
-- MIGRATION 022 DOWN: WP-A3.2.1 ROLLBACK
-- ============================================================
-- Restores pre-M022 definitions for RPCs and RLS policies
-- using legacy private.func_role() and private.org_id() checks.
-- Does NOT modify M019/M020/M021 tables or helpers.
-- ============================================================

DROP FUNCTION IF EXISTS public.change_user_role(UUID, TEXT);
DROP FUNCTION IF EXISTS public.change_user_role(UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.set_user_active(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS public.set_user_active(UUID, BOOLEAN, UUID);

-- 1. Restore change_user_role to 009 definition
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

REVOKE ALL ON FUNCTION public.change_user_role(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_user_role(UUID, TEXT) TO authenticated;


-- 2. Restore set_user_active to 009 definition
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

REVOKE ALL ON FUNCTION public.set_user_active(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_active(UUID, BOOLEAN) TO authenticated;


-- 3. Restore switch_superadmin_org_context to 017 definition
CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context(
  p_org_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_caller_id UUID;
BEGIN
  v_caller_role := private.func_role();
  IF v_caller_role != 'SUPERADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: Only SUPERADMIN can switch organization context';
  END IF;

  IF p_org_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id) THEN
      RAISE EXCEPTION 'Invalid organization ID';
    END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found or inactive';
  END IF;

  UPDATE public.eco_user_profiles
  SET organization_id = p_org_id
  WHERE id = v_caller_id;

  IF p_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (p_org_id, 'SUPERADMIN_ORG_CONTEXT_SWITCHED');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.switch_superadmin_org_context(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.switch_superadmin_org_context(UUID) TO authenticated;


-- 4. Restore RLS policies to pre-M022 definitions

-- A. eco_organizations
ALTER TABLE public.eco_organizations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Organizations viewable by own users" ON public.eco_organizations;

CREATE POLICY "Organizations viewable by own users"
ON public.eco_organizations
FOR SELECT
TO authenticated
USING (id = private.org_id());

-- B. eco_user_profiles
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
  (
    private.func_role() = 'ADMIN'
    AND organization_id = private.org_id()
  )
);

-- C. eco_audit_events
ALTER TABLE public.eco_audit_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Audit events viewable by admin" ON public.eco_audit_events;

CREATE POLICY "Audit events viewable by admin"
ON public.eco_audit_events
FOR SELECT
TO authenticated
USING (
  organization_id = private.org_id() AND private.func_role() = 'ADMIN'
);

COMMIT;
