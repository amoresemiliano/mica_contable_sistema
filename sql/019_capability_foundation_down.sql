BEGIN;

-- ============================================================
-- MIGRATION 019 DOWN: ROLLBACK WP-A1 CAPABILITY FOUNDATION
-- ============================================================
-- Removes ONLY WP-A1 additions.
-- Does NOT touch legacy tables, profiles, RLS, or RPCs.
-- ============================================================

-- 1. Drop Helper Functions
DROP FUNCTION IF EXISTS private.can_org(UUID, TEXT);
DROP FUNCTION IF EXISTS private.can_platform(TEXT);
DROP FUNCTION IF EXISTS private.active_org_id();
DROP FUNCTION IF EXISTS private.current_profile_id();

-- 2. Drop Evolved Column from eco_organization_members
ALTER TABLE public.eco_organization_members
DROP COLUMN IF EXISTS role_template_id;

-- 3. Drop WP-A1 Indexes
DROP INDEX IF EXISTS public.idx_platform_cap_overrides_user;
DROP INDEX IF EXISTS public.idx_membership_cap_overrides_membership;
DROP INDEX IF EXISTS public.idx_eco_org_members_org_active;
DROP INDEX IF EXISTS public.idx_eco_org_members_user_active;

-- 4. Drop WP-A1 Tables in Reverse Dependency Order
DROP TABLE IF EXISTS public.eco_user_active_context;
DROP TABLE IF EXISTS public.eco_user_platform_capability_overrides;
DROP TABLE IF EXISTS public.eco_user_platform_role;
DROP TABLE IF EXISTS public.eco_membership_capability_overrides;
DROP TABLE IF EXISTS public.eco_platform_role_org_capabilities;
DROP TABLE IF EXISTS public.eco_role_template_capabilities;
DROP TABLE IF EXISTS public.eco_role_templates;
DROP TABLE IF EXISTS public.eco_capabilities;

COMMIT;
