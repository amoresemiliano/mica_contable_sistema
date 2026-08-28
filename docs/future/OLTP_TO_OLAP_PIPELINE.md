# OLTP to OLAP Pipeline & Incremental Load

## Pipeline Architecture
The MICA Data Platform follows an ELT (Extract, Load, Transform) paradigm:

`PROD OLTP  --->  RAW ANALYTICS  --->  DIMENSIONAL MODEL`

1.  **Extract:** A scheduled batch job queries PROD OLTP for data changed since the last successful sync.
2.  **Load (Landing):** The extracted data is blindly inserted/upserted into the RAW Analytics layer. No business logic is applied here.
3.  **Transform:** SQL transformations in the Analytics warehouse convert the RAW data into the Star Schema (Facts and Dimensions).

## Incremental Sync Strategy (Watermarking)
To avoid dual-writes from the application, the Analytics platform pulls data asynchronously.

*   **Watermark Column:** `updated_at` (or `created_at` if immutable). If soft deletes are implemented, they must update `updated_at` or we check `deleted_at`.
*   **Checkpointing:** The Analytics DB maintains a table `analytics_sync_runs` which records the highest `updated_at` successfully processed. The next run queries: `WHERE updated_at > last_watermark`.

## Idempotency & Late Arrivals
*   **Upserts:** The pipeline uses the stable source Primary Keys (UUIDs). If the pipeline runs twice for the same time window, it performs an `UPSERT`, overwriting the existing RAW record.
*   **Late-Arriving Updates:** If a user modifies an old financial movement in OLTP, its `updated_at` becomes `now()`. The next sync run picks it up and UPSERTs the new values into Analytics, correcting the historical record.

## Observability
The `analytics_sync_runs` table tracks operational metadata:
*   `batch_id`
*   `table_name`
*   `started_at` / `finished_at`
*   `watermark_start` / `watermark_end`
*   `rows_read` / `rows_inserted` / `rows_updated`
*   `status` (SUCCESS / FAILED)
*   `error_details`

Monitoring alerts will trigger if a sync fails or if the lag exceeds 24 hours.

---

## Implementation Work Packages Roadmap

### WP-DATA-1: Analytics Infrastructure Foundation
*   **Objective:** Provision the separate Analytics PostgreSQL instance and base roles.
*   **Scope:** Set up the DB, create read-only service account in PROD, create base schemas (`raw`, `analytics`, `ops`).

### WP-DATA-2: Incremental OLTP → RAW Analytics Sync
*   **Objective:** Build the ELT extraction script/process.
*   **Scope:** Implement the watermarking logic, `analytics_sync_runs` tracking, and UPSERT logic into `raw_eco_normalized_records` and `raw_eco_financial_movements`.

### WP-DATA-3: Dimensional Transformations
*   **Objective:** Convert RAW to Star Schema.
*   **Scope:** SQL Scripts/Views to build `dim_date`, `dim_organization`, `dim_tax_category`, `fact_invoices`, `fact_bank_movements`. Handle SCD Type 1 mapping.

### WP-DATA-4: Reporting / BI
*   **Objective:** Connect BI tool (e.g. Metabase/Superset) and build initial dashboards.
*   **Scope:** VAT evolution, Expense by Category, Cash flow trends. Apply Tenant RLS to dashboards.

### WP-DATA-5: Advanced Analytics / AI (Future)
*   **Objective:** Leverage historical data for prediction.
*   **Scope:** Implement models for anomaly detection or automatic categorization based on the dimensional model.