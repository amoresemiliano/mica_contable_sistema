-- HISTORICAL RECORD: already applied manually in LIVE, as confirmed by the owner.
-- DO NOT EXECUTE AGAIN. This file versions that change; it is not a pending migration.
-- Original state: exactly four organizations with the complete Spanish baseline.
BEGIN;
LOCK TABLE public.eco_organizations IN ACCESS EXCLUSIVE MODE;
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.eco_organizations) <> 4
    OR (SELECT count(*) FROM public.eco_organizations
        WHERE tax_id_type='CIF' AND country_code='ES'
          AND currency='EUR' AND timezone='Europe/Madrid') <> 4 THEN
    RAISE EXCEPTION '035a: historical four-organization Spanish baseline absent; do not replay on normalized LIVE';
  END IF;
END;
$preflight$;
ALTER TABLE public.eco_organizations
  ALTER COLUMN tax_id_type SET DEFAULT 'CUIT',
  ALTER COLUMN country_code SET DEFAULT 'AR',
  ALTER COLUMN currency SET DEFAULT 'ARS',
  ALTER COLUMN timezone SET DEFAULT 'America/Argentina/Buenos_Aires';
UPDATE public.eco_organizations
SET tax_id_type='CUIT', country_code='AR', currency='ARS',
    timezone='America/Argentina/Buenos_Aires'
WHERE tax_id_type='CIF' AND country_code='ES'
  AND currency='EUR' AND timezone='Europe/Madrid';
-- No assignment to IDs, names, legal_name, trade_name, tax_id or is_active.
COMMIT;
