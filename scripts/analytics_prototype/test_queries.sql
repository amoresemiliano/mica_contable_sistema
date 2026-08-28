-- scripts/analytics_prototype/test_queries.sql
-- Verifies the analytical data

\echo '=== DIMENSIONS ==='
SELECT * FROM analytics.dim_organization;
SELECT * FROM analytics.dim_tax_category;
SELECT * FROM analytics.dim_counterparty;

\echo '=== FACTS (Invoices) ==='
SELECT source_record_id, is_deleted, date_key, net_taxable_amount, vat_amount, total_amount FROM analytics.fact_invoices;

\echo '=== FACTS (Bank Movements) ==='
SELECT source_record_id, is_deleted, date_key, amount, balance FROM analytics.fact_bank_movements;

\echo '=== ANALYTICAL QUERY: Total Expenses by Category (Active Only) ==='
SELECT
    c.name as category,
    SUM(f.total_amount) as total_expenses
FROM analytics.fact_invoices f
JOIN analytics.dim_tax_category c ON f.category_id = c.category_id
WHERE f.is_deleted = FALSE
GROUP BY c.name;