-- HISTORICAL INVERSE ONLY: DO NOT EXECUTE. No rollback was requested for LIVE.
-- Confirmed historical IDs: DEMO NORTE, DEMO OESTE, DEMO SUR and MICA.
-- Only these four rows in the exact normalized state may be restored.
-- Later organizations are excluded; Spanish defaults are restored only as the
-- historical rollback of 035a, not as a new localization policy.
BEGIN;
LOCK TABLE public.eco_organizations IN ACCESS EXCLUSIVE MODE;
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.eco_organizations
        WHERE id IN (
          '38419581-8163-482c-9813-616fa6214d71'::UUID, -- DEMO NORTE
          '1f5d071f-a09e-4825-9f12-88533383599e'::UUID, -- DEMO OESTE
          'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID, -- DEMO SUR
          '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID  -- MICA
        ) AND tax_id_type='CUIT' AND country_code='AR'
          AND currency='ARS' AND timezone='America/Argentina/Buenos_Aires') <> 4 THEN
    RAISE EXCEPTION '035a down: historical four-organization Argentine baseline absent; review drift';
  END IF;
END;
$preflight$;
ALTER TABLE public.eco_organizations
  ALTER COLUMN tax_id_type SET DEFAULT 'CIF',
  ALTER COLUMN country_code SET DEFAULT 'ES',
  ALTER COLUMN currency SET DEFAULT 'EUR',
  ALTER COLUMN timezone SET DEFAULT 'Europe/Madrid';
UPDATE public.eco_organizations
SET tax_id_type='CIF', country_code='ES', currency='EUR', timezone='Europe/Madrid'
WHERE tax_id_type='CUIT' AND country_code='AR'
  AND currency='ARS' AND timezone='America/Argentina/Buenos_Aires'
  AND id IN (
    '38419581-8163-482c-9813-616fa6214d71'::UUID, -- DEMO NORTE
    '1f5d071f-a09e-4825-9f12-88533383599e'::UUID, -- DEMO OESTE
    'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID, -- DEMO SUR
    '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID  -- MICA
  );
-- No assignment to IDs, names, legal_name, trade_name, tax_id or is_active.
COMMIT;
