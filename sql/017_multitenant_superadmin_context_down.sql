BEGIN;

-- Restablecer políticas RLS a la versión 014
DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories FOR SELECT TO authenticated USING (organization_id = private.org_id());

DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities FOR SELECT TO authenticated USING (organization_id = private.org_id());

DROP POLICY IF EXISTS "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates;
CREATE POLICY "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates FOR SELECT TO authenticated USING (organization_id = private.org_id());

DROP FUNCTION IF EXISTS public.switch_superadmin_org_context(UUID);

COMMIT;
