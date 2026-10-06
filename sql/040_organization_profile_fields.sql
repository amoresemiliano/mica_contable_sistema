-- sql/040_organization_profile_fields.sql
-- Additive migration: Organization profile fields (phone, email, contact_person, website, address)

ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS contact_person TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS website TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS address TEXT;
