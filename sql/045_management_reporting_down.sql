-- Disable this WP while preserving all accounting/report history. No CASCADE, no data deletion.
BEGIN;
DO $preflight$
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.eco_report_snapshots') IS NULL THEN RAISE EXCEPTION '045 not installed or wrong owner'; END IF;
END; $preflight$;
DROP FUNCTION public.mica_reporting_service(UUID,UUID,TEXT,JSONB);
DROP FUNCTION public.mica_reporting_input(UUID,TEXT,TEXT,JSONB,TEXT,INTEGER);
DROP FUNCTION public.mica_reporting_history(UUID,DATE,DATE,TEXT,UUID);
DROP FUNCTION public.mica_reporting_detail(UUID,DATE,DATE,JSONB,INTEGER,INTEGER,UUID);
DROP FUNCTION public.mica_reporting_data(UUID,DATE,DATE,BOOLEAN);
DROP FUNCTION private.reporting_045_context(UUID,DATE,DATE);
DROP VIEW private.reporting_045_facts;
DROP FUNCTION private.reporting_045_number(TEXT);
-- Append-only tables and their immutable trigger remain as retained history.
COMMIT;
