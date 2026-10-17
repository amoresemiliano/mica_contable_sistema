-- Minimal local PostgreSQL fixture; no external connections or production credentials.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA private;
GRANT USAGE ON SCHEMA public TO authenticated;
CREATE TABLE public.eco_organizations(id UUID PRIMARY KEY,name TEXT NOT NULL);
CREATE TABLE public.eco_tax_categories(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),name TEXT NOT NULL,description TEXT,
 category_type TEXT NOT NULL CHECK(category_type IN ('INCOME','EXPENSE')),
 is_active BOOLEAN DEFAULT TRUE,created_at TIMESTAMPTZ DEFAULT now(),updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE public.eco_org_tax_categories(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),organization_id UUID NOT NULL REFERENCES public.eco_organizations,
 category_id UUID NOT NULL REFERENCES public.eco_tax_categories,custom_name TEXT,
 is_assigned BOOLEAN NOT NULL DEFAULT TRUE,is_active BOOLEAN DEFAULT TRUE,
 created_at TIMESTAMPTZ DEFAULT now(),updated_at TIMESTAMPTZ DEFAULT now(),UNIQUE(organization_id,category_id)
);
CREATE TABLE public.eco_normalized_records(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),organization_id UUID NOT NULL REFERENCES public.eco_organizations,
 category_id UUID REFERENCES public.eco_tax_categories,total NUMERIC,normalized_payload JSONB,
 deleted_at TIMESTAMPTZ,updated_at TIMESTAMPTZ DEFAULT now(),updated_by UUID
);
CREATE TABLE public.eco_financial_movements(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),organization_id UUID NOT NULL REFERENCES public.eco_organizations,
 category_id UUID REFERENCES public.eco_tax_categories,amount NUMERIC,normalized_payload JSONB,
 updated_at TIMESTAMPTZ DEFAULT now()
);
-- Additional FKs confirmed by the manual DEV inventory. They are never mutated by 048.
CREATE TABLE public.eco_classification_rules(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),target_category_id UUID REFERENCES public.eco_tax_categories,
 name TEXT
);
CREATE TABLE public.eco_movement_allocations(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),category_id UUID REFERENCES public.eco_tax_categories,
 amount NUMERIC
);
CREATE TABLE public.eco_tax_subcategories(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),category_id UUID REFERENCES public.eco_tax_categories ON DELETE CASCADE,
 name TEXT
);
CREATE TABLE public.eco_audit_events(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),organization_id UUID,event_type TEXT);
ALTER TABLE public.eco_tax_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_org_tax_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_normalized_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_financial_movements ENABLE ROW LEVEL SECURITY;
CREATE POLICY category_read ON public.eco_tax_categories FOR SELECT TO authenticated USING(TRUE);
CREATE POLICY assignment_read ON public.eco_org_tax_categories FOR SELECT TO authenticated USING(organization_id=NULLIF(current_setting('mica.test_org',TRUE),'')::UUID);
CREATE POLICY record_read ON public.eco_normalized_records FOR SELECT TO authenticated USING(organization_id=NULLIF(current_setting('mica.test_org',TRUE),'')::UUID);
CREATE POLICY financial_read ON public.eco_financial_movements FOR SELECT TO authenticated USING(organization_id=NULLIF(current_setting('mica.test_org',TRUE),'')::UUID);
GRANT SELECT ON public.eco_tax_categories,public.eco_org_tax_categories,public.eco_normalized_records,public.eco_financial_movements TO authenticated;
CREATE FUNCTION private.func_role() RETURNS TEXT LANGUAGE sql AS $$SELECT 'SUPERADMIN'::TEXT$$;
CREATE FUNCTION private.org_id() RETURNS UUID LANGUAGE sql AS $$SELECT NULLIF(current_setting('mica.test_org',TRUE),'')::UUID$$;
CREATE FUNCTION private.require_global_catalog_manager() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
 IF current_setting('mica.test_manage',TRUE) IS DISTINCT FROM 'yes' OR private.org_id() IS NOT NULL THEN
   RAISE EXCEPTION 'Unauthorized' USING ERRCODE='42501';
 END IF;
END;$$;

INSERT INTO public.eco_organizations VALUES
 ('00000000-0000-0000-0000-000000000001','BAIGORRIA S.A.'),
 ('00000000-0000-0000-0000-000000000002','DEMO OESTE'),
 ('00000000-0000-0000-0000-000000000003','DEMO NORTE'),
 ('00000000-0000-0000-0000-000000000004','MICA');
INSERT INTO public.eco_tax_categories(id,name,description,category_type,created_at,updated_at) VALUES
 ('c15675d7-be33-4400-84c3-9985e1a59579','Honorarios Profesionales','BAIGORRIA original','EXPENSE','2026-01-01','2026-01-02'),
 ('326eaed3-d6cb-4d63-8adb-47116ad94bf5','Honorarios Profesionales','Oeste original','EXPENSE','2026-01-03','2026-01-04'),
 ('3c86c6f9-aea0-4dc3-98e0-e30836daf0e5','Honorarios Profesionales','Norte original','EXPENSE','2026-01-05','2026-01-06'),
 ('46200cf5-c488-47b8-b946-e637885c7c82','Honorarios Profesionales','MICA original','EXPENSE','2026-01-07','2026-01-08'),
 ('e26570a7-6e09-40a4-8901-62b835df145e','Honorarios Profesionales','Unassigned original','EXPENSE','2026-01-09','2026-01-10'),
 ('02768384-f366-4fd9-aa0c-a437866cfeb4','Telefonía','BAIGORRIA original','EXPENSE','2026-01-11','2026-01-12'),
 ('a209c838-d3e3-4e3c-9b4f-4619c83cc336','Telefonía','Norte original','EXPENSE','2026-01-13','2026-01-14'),
 ('00000000-0000-0000-0000-000000000010','Otra categoría','Unrelated','EXPENSE','2026-01-15','2026-01-16');
INSERT INTO public.eco_org_tax_categories(organization_id,category_id,custom_name,is_assigned,is_active) VALUES
 ('00000000-0000-0000-0000-000000000001','c15675d7-be33-4400-84c3-9985e1a59579','Honorarios BAIGORRIA',TRUE,TRUE),
 ('00000000-0000-0000-0000-000000000002','326eaed3-d6cb-4d63-8adb-47116ad94bf5','Honorarios Oeste',TRUE,FALSE),
 ('00000000-0000-0000-0000-000000000003','3c86c6f9-aea0-4dc3-98e0-e30836daf0e5','Honorarios Norte',TRUE,TRUE),
 ('00000000-0000-0000-0000-000000000004','46200cf5-c488-47b8-b946-e637885c7c82',NULL,TRUE,TRUE),
 ('00000000-0000-0000-0000-000000000001','02768384-f366-4fd9-aa0c-a437866cfeb4',NULL,TRUE,TRUE),
 ('00000000-0000-0000-0000-000000000004','02768384-f366-4fd9-aa0c-a437866cfeb4',NULL,TRUE,TRUE),
 ('00000000-0000-0000-0000-000000000003','a209c838-d3e3-4e3c-9b4f-4619c83cc336','Telefonía Norte',TRUE,TRUE);
INSERT INTO public.eco_normalized_records(id,organization_id,category_id,total,normalized_payload)
SELECT md5('honorarios-'||n)::UUID,'00000000-0000-0000-0000-000000000001','c15675d7-be33-4400-84c3-9985e1a59579',n*100,jsonb_build_object('moneda','PES','fuente','fixture') FROM generate_series(1,15) n;
INSERT INTO public.eco_normalized_records(id,organization_id,category_id,total,normalized_payload) VALUES
 ('00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000003','a209c838-d3e3-4e3c-9b4f-4619c83cc336',-123.45,'{"moneda":"USD","tipo_cbte":3}'),
 ('00000000-0000-0000-0000-000000000098','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000010',9,'{"moneda":"PES"}');
INSERT INTO public.eco_classification_rules(target_category_id,name) VALUES ('c15675d7-be33-4400-84c3-9985e1a59579','Keep survivor rule');
INSERT INTO public.eco_movement_allocations(category_id,amount) VALUES ('02768384-f366-4fd9-aa0c-a437866cfeb4',123.45);
INSERT INTO public.eco_tax_subcategories(category_id,name) VALUES ('00000000-0000-0000-0000-000000000010','Keep unrelated subcategory');
