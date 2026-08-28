# Data Platform Decisions

## 1. Analytics Warehouse Technology Selection
**Decision:** Separate PostgreSQL / Supabase project (Option A).
**Status:** RECOMMENDED for V1.

### Rationale:
*   **Operating Cost:** Supabase/PostgreSQL is cost-effective at low-to-medium data volumes. We can use standard relational database tiering. ClickHouse and BigQuery introduce potentially high operational overhead or unexpected per-query costs.
*   **Complexity & Maintenance:** The team is already deeply familiar with PostgreSQL and Supabase. Using another PostgreSQL instance requires zero new specialized skills for database administration, RLS configuration, and general querying.
*   **SQL Compatibility:** PostgreSQL has full ANSI SQL compatibility, meaning transformations can be written using standard CTEs, window functions, and triggers, exactly as the team currently does in OLTP.
*   **Analytical Performance:** While Columnar stores (ClickHouse/BigQuery) easily beat Row stores (PostgreSQL) for petabyte-scale aggregation, MICA's initial analytical volume (likely gigabytes, maybe low terabytes eventually) can be handled effortlessly by PostgreSQL with proper indexing (e.g., BRIN, B-Tree) and perhaps materialized views.
*   **Vendor Lock-In:** PostgreSQL is open-source. Supabase is portable.
*   **Future:** If performance degrades substantially after reaching massive scale, transitioning to ClickHouse later via logical replication or CDC remains an option.

---

## 2. Ingestion Strategy
**Decision:** BATCH ELT (Incremental via timestamps)
**Status:** RECOMMENDED for V1.

### Rationale:
*   **CDC (Change Data Capture)** using tools like Debezium or Supabase Realtime introduces complex streaming infrastructure (Kafka/Wal2Json, robust dead-letter queues) which is over-engineered for V1 reporting needs.
*   **Incremental ELT:** We can extract data using high-watermarks on `updated_at` (or `deleted_at`) in OLTP tables.
*   **Idempotency & Restartability:** Batch processing is trivial to make idempotent by using `UPSERT` (e.g. `ON CONFLICT (source_record_id) DO UPDATE`). If a sync fails, it just runs again from the last successful watermark.
*   **Asynchronous:** Application writes only to OLTP. A scheduled cron (e.g. every hour or every night) pulls the delta. No dual writes.
*   **Late-Arriving Updates:** Safely handled because updates will bump the `updated_at` column in OLTP, causing the ELT job to pull the record in the next run and UPSERT it into analytics.

---

## 3. Historical Changes & Soft Deletes
**Decision:** UPSERT with Dimensional SCD. Soft Deletes mapped to Tombstones/Status.

### Soft Deletes:
The OLTP system uses `deleted_at` for operational records (Decision 001).
*   **Raw Layer:** Soft deletes are fetched via ELT. The RAW layer stores `source_deleted_at`.
*   **Dimensional Layer:** The fact table marks the record as `is_deleted = TRUE` or removes it from aggregates. We do NOT hard-delete in Analytics, preserving the lineage of what was deleted and when.

### Categorization & Dimensions:
If an invoice is categorized as 'A', and later changed to 'B', how is this handled?
*   **SCD Type 1 (Overwrite):** The fact record is simply updated to point to the new category. This reflects the "current true state" of the business, which is usually what reporting needs (e.g. "show me all expenses currently categorized as 'B'"). We will use **SCD Type 1 by default** for most dimensions to prioritize simplicity and current-truth alignment.
*   **SCD Type 2 (History):** If business requires knowing the *history* of classification (e.g. "how often do users correct 'A' to 'B'"), we track the `updated_at` in the fact lineage, or we use an audit table (like `eco_audit_events`). We will avoid full SCD Type 2 dimension versioning in V1 unless a specific ML or compliance use case absolutely demands it.