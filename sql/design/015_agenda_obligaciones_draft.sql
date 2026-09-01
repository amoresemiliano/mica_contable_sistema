-- DESIGN ONLY — DO NOT APPLY
-- DRAFT: 015_agenda_obligaciones_draft.sql
-- Proposed architecture for Agenda / Obligaciones (HARDENED)

BEGIN;

-- ============================================================
-- 1. JURISDICTIONS (GLOBAL CATALOG)
-- ============================================================
-- Stores national, provincial, and local authorities.
CREATE TABLE IF NOT EXISTS public.eco_jurisdictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE, -- e.g., 'AFIP', 'AGIP', 'ARBA', 'MUNI_CBA'
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('NATIONAL', 'PROVINCIAL', 'MUNICIPAL', 'UNION', 'OTHER')),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 2. OBLIGATION DEFINITIONS (GLOBAL CATALOG)
-- ============================================================
-- Generic catalog of possible obligations (Taxes, Unions, etc.)
CREATE TABLE IF NOT EXISTS public.eco_obligation_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE, -- e.g., 'IVA', 'IIBB', 'SEC', 'FAECYS'
  name TEXT NOT NULL,
  description TEXT,
  obligation_type TEXT NOT NULL CHECK (obligation_type IN ('TAX', 'UNION', 'PAYROLL', 'MANUAL', 'OTHER')),
  default_jurisdiction_id UUID REFERENCES public.eco_jurisdictions(id) ON DELETE RESTRICT,
  default_frequency TEXT NOT NULL CHECK (default_frequency IN ('MONTHLY', 'QUARTERLY', 'ANNUAL', 'ONCE', 'MANUAL')),
  source_type TEXT NOT NULL CHECK (source_type IN ('MANUAL', 'PAYROLL', 'TAX_CALCULATION')),
  is_configurable BOOLEAN DEFAULT TRUE,
  is_active BOOLEAN DEFAULT TRUE,
  metadata JSONB DEFAULT '{}'::jsonb, -- Store dynamic rules or future mappings
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- 3. ORGANIZATION OBLIGATIONS (ASSIGNMENT)
-- ============================================================
-- Links a client (organization) with an obligation definition.
CREATE TABLE IF NOT EXISTS public.eco_org_obligations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
  obligation_definition_id UUID NOT NULL REFERENCES public.eco_obligation_definitions(id) ON DELETE RESTRICT,
  jurisdiction_id UUID REFERENCES public.eco_jurisdictions(id) ON DELETE RESTRICT, -- Override default jurisdiction if needed
  custom_label TEXT,
  frequency TEXT NOT NULL CHECK (frequency IN ('MONTHLY', 'QUARTERLY', 'ANNUAL', 'ONCE', 'MANUAL')),
  account_reference TEXT, -- Useful for tax ID or specific account number
  source_mapping_config JSONB DEFAULT '{}'::jsonb, -- How this obligation maps from sources (e.g. Sueldos rules)
  is_active BOOLEAN DEFAULT TRUE,
  active_from DATE,
  active_to DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(organization_id, obligation_definition_id, jurisdiction_id)
);

-- ============================================================
-- 4. OBLIGATION INSTANCES
-- ============================================================
-- The actual "Client X must pay Y for period Z".
CREATE TABLE IF NOT EXISTS public.eco_obligation_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
  org_obligation_id UUID NOT NULL REFERENCES public.eco_org_obligations(id) ON DELETE RESTRICT,

  period TEXT NOT NULL, -- e.g., '2023-10'
  due_date DATE,
  amount NUMERIC(15,2) NOT NULL,

  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID', 'CANCELLED')), -- OVERDUE is computed

  -- Tracking origin for idempotency and audit
  source TEXT NOT NULL CHECK (source IN ('MANUAL', 'PAYROLL', 'TAX_CALCULATION')),
  source_record_id UUID, -- E.g., reference to eco_financial_movements for salary
  identity_key TEXT NOT NULL, -- Deterministic extensible key: hash(org_id, org_obligation_id, period, context)

  requires_review BOOLEAN DEFAULT FALSE,
  notes TEXT,
  created_by UUID, -- Could be a user or a system process
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE (organization_id, identity_key) -- Idempotency constraint using extensible key
);

-- ============================================================
-- 5. OBLIGATION PAYMENTS
-- ============================================================
-- Supports partial or full payments.
CREATE TABLE IF NOT EXISTS public.eco_obligation_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
  instance_id UUID NOT NULL REFERENCES public.eco_obligation_instances(id) ON DELETE RESTRICT,

  payment_date DATE NOT NULL,
  amount NUMERIC(15,2) NOT NULL,
  payment_method TEXT,
  reference_number TEXT,

  supporting_evidence_path TEXT, -- E.g., link to a receipt in storage (Optional)
  requires_review BOOLEAN DEFAULT FALSE,
  notes TEXT,

  created_by UUID,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Note: We reuse public.eco_audit_events for obligation audit trail.

-- ============================================================
-- 6. RLS STUBS
-- ============================================================
-- RLS should use `private.org_id()` similar to existing policies
ALTER TABLE public.eco_jurisdictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_obligation_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_org_obligations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_obligation_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eco_obligation_payments ENABLE ROW LEVEL SECURITY;

COMMIT;
