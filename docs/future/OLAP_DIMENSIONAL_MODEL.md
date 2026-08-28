# OLAP Dimensional Model

This document outlines the Star Schema design for the MICA Analytics platform. It transforms the highly normalized and tenant-isolated OLTP data into a structure optimized for fast aggregation and time-series reporting.

## Dimensions

### `dim_date`
*   **Purpose:** Standard calendar dimension.
*   **Columns:** `date_key` (YYYYMMDD), `full_date`, `year`, `month`, `day`, `quarter`, `day_of_week`, `is_weekend`, `is_holiday`.

### `dim_organization`
*   **Purpose:** The central tenant dimension. All facts must link here to ensure isolation.
*   **Columns:** `organization_id` (PK, UUID), `name`, `created_at`.

### `dim_tax_category`
*   **Purpose:** Standardized global and custom tax categories.
*   **Columns:** `category_id` (PK, UUID), `organization_id` (Nullable for global), `code`, `name`, `tax_type`.

### `dim_activity`
*   **Purpose:** Economic activities.
*   **Columns:** `activity_id` (PK, UUID), `organization_id`, `code`, `name`.

### `dim_jurisdiction`
*   **Purpose:** Taxing authorities (from Agenda domain).
*   **Columns:** `jurisdiction_id` (PK, UUID), `code`, `name`, `type`.

### `dim_counterparty` (Supplier / Client)
*   **Purpose:** The entity issuing or receiving an invoice. (Derived from `cuit_emisor` / `razon_social`).
*   **Columns:** `counterparty_key` (Surrogate or hash of CUIT + Org), `cuit`, `name`.

---

## Facts

### `fact_invoices`
*   **Source:** `raw_eco_normalized_records`
*   **Grain:** One row per invoice/receipt (Comprobante).
*   **Dimensions:** `date_key` (fecha), `organization_id`, `counterparty_key`, `category_id`, `activity_id`.
*   **Measures:**
    *   `net_taxable_amount` (Gravado)
    *   `exempt_amount` (Exento)
    *   `non_taxable_amount` (No Gravado)
    *   `vat_amount` (IVA)
    *   `vat_perception_amount` (Percepción IVA)
    *   `iibb_perception_amount` (Percepción IIBB)
    *   `other_tax_amount` (Otros Tributos)
    *   `total_amount` (Total)
*   **Lineage:** `source_record_id` (UUID), `sync_batch_id`, `is_deleted`.

### `fact_bank_movements`
*   **Source:** `raw_eco_financial_movements` (where source_type = 'BBVA' or similar).
*   **Grain:** One row per bank transaction.
*   **Dimensions:** `date_key`, `organization_id`, `category_id`.
*   **Measures:**
    *   `amount` (Monto - signed)
    *   `balance` (Saldo)
*   **Lineage:** `source_record_id`, `sync_batch_id`, `is_deleted`.

### `fact_obligations` (Future Integration)
*   **Source:** `raw_eco_obligation_instances`
*   **Grain:** One row per obligation period.
*   **Dimensions:** `date_key` (due_date), `organization_id`, `jurisdiction_id`.
*   **Measures:** `amount`.
*   **Lineage:** `source_record_id`, `status` (PENDING, PAID).

## Lineage & Data Quality

Every fact table includes:
*   `source_system`: Always 'MICA_PROD'.
*   `source_table`: The OLTP table name.
*   `source_record_id`: The UUID of the original row.
*   `sync_batch_id`: Link to `analytics_sync_runs` for auditability.
*   `transformed_at`: Timestamp of ELT completion.

**Data Quality Checks (Post-Transform):**
*   **Orphan Check:** Ensure no `organization_id` in facts is missing from `dim_organization`.
*   **Duplicate Check:** Assert `COUNT(*) = COUNT(DISTINCT source_record_id)` for facts.
*   **Lineage Check:** Verify `total_amount` matches the sum of sub-amounts (net + taxes) where mathematically expected.

## Reporting Use Cases Supported
*   **Monthly expense evolution:** `SUM(fact_invoices.total_amount) GROUP BY dim_date.month, dim_tax_category.name`
*   **Supplier concentration:** `SUM(fact_invoices.total_amount) GROUP BY dim_counterparty.name ORDER BY amount DESC`
*   **VAT evolution:** `SUM(fact_invoices.vat_amount) GROUP BY dim_date.month`