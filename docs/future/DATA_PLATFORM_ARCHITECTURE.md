# Data Platform Architecture

## Environment Separation

MICA's data lifecycle is logically separated into four main environments. Application instances (dev, staging, prod) write ONLY to their respective OLTP database.

### A. DEV OLTP
*   **Responsibility:** Disposable development environment. Used for local/branch development, unit tests, and CI/CD runs.
*   **Allowed Data:** Synthetic, mock, and anonymized data ONLY. No real client accounting data.
*   **Migration Behavior:** Destroyed and recreated constantly. Schema changes tested here first.
*   **Backup Policy:** None.
*   **Access Pattern:** Write-heavy, full permissions for developers/CI.
*   **Failure Isolation:** Complete isolation. Dropping the database has zero impact.

### B. STAGING OLTP
*   **Responsibility:** Pre-production validation, E2E testing, QA, and migration dry-runs.
*   **Allowed Data:** Mix of synthetic data and heavily anonymized production snapshots (if explicitly authorized for complex debugging).
*   **Migration Behavior:** Migrations are applied here exactly as they will be in PROD. Used to validate `UP` and `DOWN` scripts.
*   **Backup Policy:** Periodic snapshots (e.g., daily) before large schema deployments.
*   **Access Pattern:** Replicates PROD application access patterns.
*   **Failure Isolation:** Separate infrastructure from PROD. A bad migration here stops the release pipeline but does not affect users.

### C. PROD OLTP
*   **Responsibility:** The single operational source of truth. Serves the MICA application traffic, user authentication, and real-time conciliation workflows.
*   **Allowed Data:** Real client accounting data, PII, auth secrets.
*   **Migration Behavior:** Strict, forward-only, non-destructive migrations. Handled by release automation with human gates.
*   **Backup Policy:** Continuous WAL archiving (PITR) + Daily snapshots.
*   **Access Pattern:** Read/Write from the application via API/RPC. Strict RLS enforcement. No direct external BI connections allowed.
*   **Failure Isolation:** Highest priority. The OLAP platform MUST NOT be able to degrade PROD OLTP performance (e.g., via heavy analytical queries).

### D. ANALYTICS / OLAP (Warehouse)
*   **Responsibility:** Independent analytical database for reporting, dashboards, and future ML workloads.
*   **Allowed Data:** Curated analytical data, de-identified where possible. Minimal PII. NO Auth secrets or credentials replicated.
*   **Migration Behavior:** Independent from OLTP. The ELT pipeline translates OLTP schema changes to OLAP schema gracefully.
*   **Backup Policy:** Daily snapshots. Data can always be reconstructed from the PROD OLTP source of truth if completely lost, but backups prevent expensive total re-syncs.
*   **Access Pattern:** Read-heavy. Used by BI tools (Metabase, Looker, Superset), Data Scientists, and reporting dashboards. Asynchronous batch writes from the ELT pipeline.
*   **Failure Isolation:** Completely isolated compute and storage from PROD OLTP. If Analytics goes down, MICA application continues working normally.

---

## Security & Privacy
*   **Tenant Isolation:** Analytics data retains the `organization_id`. BI roles (e.g., a reporting service account) must still enforce tenant-level RLS if serving dashboards back to MICA application users.
*   **Least Privilege:** The ELT extractor has read-only access to PROD OLTP. The BI tools have read-only access to ANALYTICS.
*   **PII Minimization:** The ELT process does not extract user passwords, session tokens, or unnecessary personal contact information not relevant for accounting analysis.

---

## AI / ML Readiness
This architecture supports future ML pipelines (cash flow forecasting, anomaly detection, classification recommendations) by:
1.  **Providing a clean Dimensional Model:** ML models train on the curated facts and dimensions, not raw JSON blobs.
2.  **Preserving History:** Lineage and timestamps allow for point-in-time training (avoiding data leakage).
3.  **Decoupled Compute:** Model training and inference queries hit the Analytics database, ensuring PROD OLTP is not impacted by heavy tensor computations or large data scans.