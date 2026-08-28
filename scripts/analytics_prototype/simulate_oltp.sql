-- scripts/analytics_prototype/simulate_oltp.sql
-- Simulates the OLTP extraction inserting into the RAW analytics layer.
-- Run this AFTER init_db.sh

BEGIN;

-- Insert a batch run record
INSERT INTO ops.analytics_sync_runs (batch_id, table_name, status)
VALUES ('11111111-1111-1111-1111-111111111111', 'initial_load', 'SUCCESS');

-- Mock Organizations
INSERT INTO raw.eco_organizations (id, name, created_at, sync_batch_id)
VALUES
('22222222-2222-2222-2222-222222222222', 'Acme Corp', '2023-01-01', '11111111-1111-1111-1111-111111111111');

-- Mock Tax Categories
INSERT INTO raw.eco_tax_categories (id, code, name, tax_type, sync_batch_id)
VALUES
('33333333-3333-3333-3333-333333333333', 'CAT-A', 'General Expenses', 'EXPENSE', '11111111-1111-1111-1111-111111111111');

-- Mock Normalized Records (Invoices)
INSERT INTO raw.eco_normalized_records (id, organization_id, fecha, tipo_comprobante, cuit_emisor, denominacion_emisor, neto_gravado, iva, total, category_id, sync_batch_id)
VALUES
('44444444-4444-4444-4444-444444444441', '22222222-2222-2222-2222-222222222222', '2023-10-01', 'Factura A', '20123456789', 'Supplier X', 1000.00, 210.00, 1210.00, '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111'),
('44444444-4444-4444-4444-444444444442', '22222222-2222-2222-2222-222222222222', '2023-10-05', 'Factura C', '20987654321', 'Supplier Y', 500.00, 0, 500.00, '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');

-- Mock Financial Movements (Bank)
INSERT INTO raw.eco_financial_movements (id, organization_id, source_type, fecha, monto, saldo, category_id, sync_batch_id)
VALUES
('55555555-5555-5555-5555-555555555551', '22222222-2222-2222-2222-222222222222', 'BBVA', '2023-10-02', -1210.00, 5000.00, '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111');

-- Mock dim_date entries for the required dates to satisfy foreign keys
INSERT INTO analytics.dim_date (date_key, full_date, year, month, day, quarter, day_of_week) VALUES
(20231001, '2023-10-01', 2023, 10, 1, 4, 1),
(20231002, '2023-10-02', 2023, 10, 2, 4, 2),
(20231005, '2023-10-05', 2023, 10, 5, 4, 5);

COMMIT;