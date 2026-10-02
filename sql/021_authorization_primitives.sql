BEGIN;

-- ============================================================
-- MIGRATION 021: WP-A3.2.0 AUTHORIZATION PRIMITIVES OPTIMIZATION
-- ============================================================
-- 1. Adds covering indexes for high-concurrency membership & platform role resolution.
-- 2. Introduces set-based helper function private.authorized_orgs_for_capability
--    to support the Authorization Join Pattern in high-volume RLS policies.
-- ============================================================

-- 1. Covering Index on eco_organization_members
CREATE INDEX IF NOT EXISTS idx_eco_org_members_covering
ON public.eco_organization_members (organization_id, user_profile_id, is_active, role_template_id);

-- 2. Covering Index on eco_user_platform_role
CREATE INDEX IF NOT EXISTS idx_eco_user_platform_role_covering
ON public.eco_user_platform_role (user_profile_id, is_active, role_template_id);

-- 3. Set-based Authorization Helper for High-Volume RLS Join Pattern
CREATE OR REPLACE FUNCTION private.authorized_orgs_for_capability(p_capability_code TEXT)
RETURNS TABLE (organization_id UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_cap_id UUID;
    v_platform_role_template_id UUID;
    v_platform_has_bridge BOOLEAN := FALSE;
BEGIN
    IF p_capability_code IS NULL THEN
        RETURN;
    END IF;

    -- 1. Resolve active caller profile
    v_profile_id := private.current_profile_id();
    IF v_profile_id IS NULL THEN
        RETURN;
    END IF;

    -- 2. Resolve capability ID
    SELECT id INTO v_cap_id
    FROM public.eco_capabilities
    WHERE code = p_capability_code
      AND scope = 'ORGANIZATION'
      AND is_active = TRUE;

    IF v_cap_id IS NULL THEN
        RETURN;
    END IF;

    -- 3. Check if user possesses eligible platform-role bridge grant
    SELECT upr.role_template_id INTO v_platform_role_template_id
    FROM public.eco_user_platform_role upr
    JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
    WHERE upr.user_profile_id = v_profile_id
      AND upr.is_active = TRUE
      AND rt.scope = 'PLATFORM'
      AND rt.is_active = TRUE;

    IF v_platform_role_template_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.eco_platform_role_org_capabilities
            WHERE role_template_id = v_platform_role_template_id
              AND capability_id = v_cap_id
        ) INTO v_platform_has_bridge;
    END IF;

    -- 4. Return authorized organization IDs considering base template, platform bridge, and overrides
    RETURN QUERY
    SELECT m.organization_id
    FROM public.eco_organization_members m
    JOIN public.eco_organizations o ON o.id = m.organization_id
    LEFT JOIN public.eco_membership_capability_overrides mco 
        ON mco.membership_id = m.id AND mco.capability_id = v_cap_id
    WHERE m.user_profile_id = v_profile_id
      AND m.is_active = TRUE
      AND (
          -- Explicit ALLOW override grants capability
          mco.effect = 'ALLOW'
          OR (
              -- No explicit DENY override
              (mco.effect IS NULL OR mco.effect <> 'DENY')
              AND (
                  -- Base template grant
                  (
                      m.role_template_id IS NOT NULL AND EXISTS (
                          SELECT 1 
                          FROM public.eco_role_template_capabilities rtc
                          JOIN public.eco_role_templates rt ON rt.id = rtc.role_template_id
                          WHERE rtc.role_template_id = m.role_template_id
                            AND rtc.capability_id = v_cap_id
                            AND rt.scope = 'ORGANIZATION'
                            AND rt.is_active = TRUE
                      )
                  )
                  -- OR Platform-role organization bridge grant
                  OR v_platform_has_bridge = TRUE
              )
          )
      );
END;
$$;

REVOKE ALL ON FUNCTION private.authorized_orgs_for_capability(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.authorized_orgs_for_capability(TEXT) TO authenticated;

COMMIT;
