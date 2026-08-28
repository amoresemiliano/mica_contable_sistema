-- DESIGN / PROTOTYPE ONLY — DO NOT APPLY TO PROD
-- sql/design/analytics_raw_schema.sql

BEGIN;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS ops;

-- ============================================================
-- OPERATIONS / OBSERVABILITY
-- ============================================================
CREATE TABLE IF NOT EXISTS ops.analytics_sync_runs (
    batch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    watermark_start TIMESTAMPTZ,
    watermark_end TIMESTAMPTZ,
    rows_read INT DEFAULT 0,
    rows_inserted INT DEFAULT 0,
    rows_updated INT DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'RUNNING',
    error_details TEXT
);

-- ============================================================
-- RAW LAYER (Landing zone, 1:1 with OLTP but with lineage)
-- ============================================================

CREATE TABLE IF NOT EXISTS raw.eco_organizations (
    -- Source Columns
    id UUID PRIMARY KEY,
    name TEXT,
    created_at TIMESTAMPTZ,

    -- Analytics Lineage
    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_batch_id UUID REFERENCES ops.analytics_sync_runs(batch_id)
);

CREATE TABLE IF NOT EXISTS raw.eco_tax_categories (
    id UUID PRIMARY KEY,
    code TEXT,
    name TEXT,
    tax_type TEXT,
    created_at TIMESTAMPTZ,

    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_batch_id UUID REFERENCES ops.analytics_sync_runs(batch_id)
);

CREATE TABLE IF NOT EXISTS raw.eco_normalized_records (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL,
    import_id UUID,
    row_id UUID,

    fecha DATE,
    tipo_comprobante TEXT,
    punto_venta TEXT,
    numero_comprobante TEXT,

    cuit_emisor TEXT,
    denominacion_emisor TEXT,

    neto_gravado NUMERIC,
    no_gravado NUMERIC,
    exento NUMERIC,
    iva NUMERIC,
    percepcion_iva NUMERIC,
    percepcion_iibb NUMERIC,
    otros_tributos NUMERIC,
    total NUMERIC,

    category_id UUID,
    activity_id UUID,

    source_created_at TIMESTAMPTZ,
    source_updated_at TIMESTAMPTZ,
    source_deleted_at TIMESTAMPTZ, -- To support soft-deletes

    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_batch_id UUID REFERENCES ops.analytics_sync_runs(batch_id)
);

CREATE TABLE IF NOT EXISTS raw.eco_financial_movements (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL,

    source_type TEXT,
    operation_type TEXT,
    fecha DATE,
    descripcion TEXT,
    monto NUMERIC,
    saldo NUMERIC,

    category_id UUID,
    activity_id UUID,

    source_created_at TIMESTAMPTZ,
    source_updated_at TIMESTAMPTZ,
    source_deleted_at TIMESTAMPTZ,

    extracted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sync_batch_id UUID REFERENCES ops.analytics_sync_runs(batch_id)
);

COMMIT;