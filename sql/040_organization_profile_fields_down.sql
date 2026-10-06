-- sql/040_organization_profile_fields_down.sql
-- Rollback organization profile fields

ALTER TABLE public.eco_organizations DROP COLUMN IF EXISTS phone;
ALTER TABLE public.eco_organizations DROP COLUMN IF EXISTS email;
ALTER TABLE public.eco_organizations DROP COLUMN IF EXISTS contact_person;
ALTER TABLE public.eco_organizations DROP COLUMN IF EXISTS website;
ALTER TABLE public.eco_organizations DROP COLUMN IF EXISTS address;
