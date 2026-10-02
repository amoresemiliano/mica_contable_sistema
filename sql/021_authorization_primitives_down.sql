BEGIN;

-- ============================================================
-- ROLLBACK SCRIPT FOR MIGRATION 021 (WP-A3.2.0)
-- ============================================================
-- Removes ONLY M021 artifacts (covering indexes & authorized_orgs_for_capability helper).
-- STRICTLY PRESERVES M019 Capability Foundation & M020 Real User Assignments.
-- ============================================================

DROP FUNCTION IF EXISTS private.authorized_orgs_for_capability(TEXT);

DROP INDEX IF EXISTS public.idx_eco_user_platform_role_covering;
DROP INDEX IF EXISTS public.idx_eco_org_members_covering;

COMMIT;
