-- Rollback contracts/schema only. Keep all org rate rows and all access/audit history.
-- Existing tenant RPC bodies/owners/grants were never replaced.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $$ BEGIN IF current_user<>'postgres' THEN RAISE EXCEPTION '041 rollback requires postgres'; END IF; END $$;
-- Keep global versions and assignment provenance recoverable, including unassigned definitions.
CREATE TABLE IF NOT EXISTS private.migration_041_rollback_archive(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), archived_at TIMESTAMPTZ NOT NULL DEFAULT now(), payload JSONB NOT NULL
);
ALTER TABLE private.migration_041_rollback_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_041_rollback_archive FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_041_rollback_archive(payload) SELECT jsonb_build_object(
 'definitions',COALESCE((SELECT jsonb_agg(to_jsonb(d)) FROM private.eco_iibb_rate_definitions d),'[]'),
 'assignments',COALESCE((SELECT jsonb_agg(to_jsonb(r)) FROM public.eco_org_activity_iibb_rates r WHERE r.definition_id IS NOT NULL),'[]'));
DROP FUNCTION public.mica_platform_iibb(TEXT,UUID,JSONB);
DROP FUNCTION public.mica_platform_access(TEXT,UUID,JSONB);
DROP TRIGGER guard_041_iibb_assignment ON public.eco_org_activity_iibb_rates;
DROP FUNCTION private.guard_041_iibb_assignment();
DROP FUNCTION private.admin_041_role(UUID,UUID);
DROP FUNCTION private.admin_041_platform_role(UUID);
DROP FUNCTION private.admin_041_bridge(UUID,TEXT);
DROP FUNCTION private.admin_041_platform(TEXT,UUID);
ALTER TABLE public.eco_org_activity_iibb_rates DROP COLUMN definition_id;
DROP TABLE private.eco_iibb_rate_definitions;
NOTIFY pgrst,'reload schema';
COMMIT;
