-- DESIGN / PROTOTYPE ONLY — DO NOT APPLY TO PROD
-- sql/design/analytics_schema.sql

BEGIN;

CREATE SCHEMA IF NOT EXISTS analytics;

-- ============================================================
-- DIMENSIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS analytics.dim_date (
    date_key INT PRIMARY KEY, -- e.g., 20231024
    full_date DATE UNIQUE NOT NULL,
    year INT NOT NULL,
    month INT NOT NULL,
    day INT NOT NULL,
    quarter INT NOT NULL,
    day_of_week INT NOT NULL
);

CREATE TABLE IF NOT EXISTS analytics.dim_organization (
    organization_id UUID PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMPTZ,

    transformed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytics.dim_tax_category (
    category_id UUID PRIMARY KEY,
    code TEXT,
    name TEXT,
    tax_type TEXT,

    transformed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analytics.dim_counterparty (
    counterparty_key TEXT PRIMARY KEY, -- org_id + cuit
    organization_id UUID NOT NULL REFERENCES analytics.dim_organization(organization_id),
    cuit TEXT,
    name TEXT,

    transformed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- FACTS
-- ============================================================

CREATE TABLE IF NOT EXISTS analytics.fact_invoices (
    -- Lineage
    source_record_id UUID PRIMARY KEY,
    sync_batch_id UUID,
    is_deleted BOOLEAN DEFAULT FALSE,
    transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Dimensions
    date_key INT REFERENCES analytics.dim_date(date_key),
    organization_id UUID REFERENCES analytics.dim_organization(organization_id),
    category_id UUID, -- Optional foreign key, might be null
    counterparty_key TEXT,

    -- Measures
    net_taxable_amount NUMERIC(15,2) DEFAULT 0,
    exempt_amount NUMERIC(15,2) DEFAULT 0,
    non_taxable_amount NUMERIC(15,2) DEFAULT 0,
    vat_amount NUMERIC(15,2) DEFAULT 0,
    vat_perception_amount NUMERIC(15,2) DEFAULT 0,
    iibb_perception_amount NUMERIC(15,2) DEFAULT 0,
    other_tax_amount NUMERIC(15,2) DEFAULT 0,
    total_amount NUMERIC(15,2) DEFAULT 0
);

CREATE TABLE IF NOT EXISTS analytics.fact_bank_movements (
    -- Lineage
    source_record_id UUID PRIMARY KEY,
    sync_batch_id UUID,
    is_deleted BOOLEAN DEFAULT FALSE,
    transformed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Dimensions
    date_key INT REFERENCES analytics.dim_date(date_key),
    organization_id UUID REFERENCES analytics.dim_organization(organization_id),
    category_id UUID,

    -- Measures
    amount NUMERIC(15,2),
    balance NUMERIC(15,2)
);

COMMIT;