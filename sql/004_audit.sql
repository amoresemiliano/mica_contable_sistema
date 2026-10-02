-- sql/004_audit.sql
-- Audit table and policies

CREATE TABLE public.eco_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger defensivo para garantizar append-only independiente de RLS
CREATE OR REPLACE FUNCTION private.prevent_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION 'Audit events are immutable and append-only';
END;
$$;

REVOKE ALL ON FUNCTION private.prevent_audit_mutation() FROM PUBLIC;

CREATE TRIGGER enforce_append_only_audit
BEFORE UPDATE OR DELETE ON public.eco_audit_events
FOR EACH ROW
EXECUTE FUNCTION private.prevent_audit_mutation();

ALTER TABLE public.eco_audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Audit events viewable by org"
ON public.eco_audit_events
FOR SELECT
TO authenticated
USING (organization_id = private.org_id());

CREATE POLICY "Audit events insertable by org"
ON public.eco_audit_events
FOR INSERT
TO authenticated
WITH CHECK (organization_id = private.org_id());
