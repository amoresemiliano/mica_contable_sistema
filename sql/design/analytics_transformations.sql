-- DESIGN / PROTOTYPE ONLY — DO NOT APPLY TO PROD
-- sql/design/analytics_transformations.sql

BEGIN;

-- ============================================================
-- 1. TRANSFORM DIMENSIONS
-- ============================================================

-- UPSERT Organizations
INSERT INTO analytics.dim_organization (organization_id, name, created_at, transformed_at)
SELECT
    id,
    name,
    created_at,
    now()
FROM raw.eco_organizations
ON CONFLICT (organization_id) DO UPDATE
SET name = EXCLUDED.name, transformed_at = now();


-- UPSERT Categories
INSERT INTO analytics.dim_tax_category (category_id, code, name, tax_type, transformed_at)
SELECT
    id,
    code,
    name,
    tax_type,
    now()
FROM raw.eco_tax_categories
ON CONFLICT (category_id) DO UPDATE
SET code = EXCLUDED.code, name = EXCLUDED.name, tax_type = EXCLUDED.tax_type, transformed_at = now();


-- UPSERT Counterparties (SCD Type 1)
INSERT INTO analytics.dim_counterparty (counterparty_key, organization_id, cuit, name, transformed_at)
SELECT DISTINCT
    organization_id::text || '_' || cuit_emisor as counterparty_key,
    organization_id,
    cuit_emisor,
    denominacion_emisor,
    now()
FROM raw.eco_normalized_records
WHERE cuit_emisor IS NOT NULL
ON CONFLICT (counterparty_key) DO UPDATE
SET name = EXCLUDED.name, transformed_at = now();


-- ============================================================
-- 2. TRANSFORM FACTS
-- ============================================================

-- UPSERT Invoices (Soft-deletes map to is_deleted)
INSERT INTO analytics.fact_invoices (
    source_record_id,
    sync_batch_id,
    is_deleted,
    transformed_at,
    date_key,
    organization_id,
    category_id,
    counterparty_key,
    net_taxable_amount,
    exempt_amount,
    non_taxable_amount,
    vat_amount,
    vat_perception_amount,
    iibb_perception_amount,
    other_tax_amount,
    total_amount
)
SELECT
    r.id,
    r.sync_batch_id,
    CASE WHEN r.source_deleted_at IS NOT NULL THEN TRUE ELSE FALSE END as is_deleted,
    now(),
    CAST(TO_CHAR(r.fecha, 'YYYYMMDD') AS INT),
    r.organization_id,
    r.category_id,
    r.organization_id::text || '_' || r.cuit_emisor,
    COALESCE(r.neto_gravado, 0),
    COALESCE(r.exento, 0),
    COALESCE(r.no_gravado, 0),
    COALESCE(r.iva, 0),
    COALESCE(r.percepcion_iva, 0),
    COALESCE(r.percepcion_iibb, 0),
    COALESCE(r.otros_tributos, 0),
    COALESCE(r.total, 0)
FROM raw.eco_normalized_records r
ON CONFLICT (source_record_id) DO UPDATE SET
    is_deleted = EXCLUDED.is_deleted,
    transformed_at = EXCLUDED.transformed_at,
    category_id = EXCLUDED.category_id,
    net_taxable_amount = EXCLUDED.net_taxable_amount,
    total_amount = EXCLUDED.total_amount;


-- UPSERT Bank Movements
INSERT INTO analytics.fact_bank_movements (
    source_record_id,
    sync_batch_id,
    is_deleted,
    transformed_at,
    date_key,
    organization_id,
    category_id,
    amount,
    balance
)
SELECT
    r.id,
    r.sync_batch_id,
    CASE WHEN r.source_deleted_at IS NOT NULL THEN TRUE ELSE FALSE END as is_deleted,
    now(),
    CAST(TO_CHAR(r.fecha, 'YYYYMMDD') AS INT),
    r.organization_id,
    r.category_id,
    r.monto,
    r.saldo
FROM raw.eco_financial_movements r
ON CONFLICT (source_record_id) DO UPDATE SET
    is_deleted = EXCLUDED.is_deleted,
    transformed_at = EXCLUDED.transformed_at,
    category_id = EXCLUDED.category_id;

COMMIT;