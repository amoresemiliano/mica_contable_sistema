# MICA Authorization Performance Test Plan & Benchmark Specification (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: BENCHMARK SPECIFICATION & DEV REPRODUCIBILITY HARNESS  
> **Evidence Taxonomy**: Explicitly segmented into `UNVERIFIED_PREVIOUS_DESIGN_CLAIM`, `REPRODUCIBLE_DEV_BENCHMARK`, and `ARCHITECTURAL_PRINCIPLE`.

---

## 1. Evidence Classification & Taxonomy

| Classification | Target Context | Row Count Range | Status & Purpose |
| :--- | :--- | :--- | :--- |
| **`REPRODUCIBLE_DEV_BENCHMARK`** | Isolated Test Fixtures in Supabase DEV | **10,000 synthetic rows** | Executable script [`tests/db/021_authorization_performance_benchmark.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_authorization_performance_benchmark.sql) comparing query plan shapes and buffer usage under `EXPLAIN (ANALYZE, BUFFERS)` |
| **`UNVERIFIED_PREVIOUS_DESIGN_CLAIM`** | Prior Theoretical / Design Estimations | N/A | Previously recorded metrics (e.g. 14.8x speedup, sub-millisecond execution estimates) prior to manual DEV benchmark reproduction |
| **`ARCHITECTURAL_PRINCIPLE`** | System Design Invariants | All volumes | Per-row authorization function evaluation vs set-based indexable filtering |

---

## 2. Architectural Analysis: Per-Row Evaluation vs Set-Based Filtering

### Architectural Principle
1. **Per-Row Scalar Evaluation (`private.can_org(organization_id, ...)` in RLS)**:
   - Evaluates the authorization subqueries repeatedly across table rows being scanned.
   - Even when the function is marked `STABLE`, row-by-row filtering on heterogeneous data forces repeated evaluation, leading to $O(N)$ execution overhead.
   - Cannot leverage standard b-tree index lookups on the target table's `organization_id` for set reduction.

2. **Set-Based Predicate Resolution (`private.authorized_orgs_for_capability(...)`)**:
   - Resolves the complete set of organizations where the caller holds the required capability **once** per query ($O(1)$ authorization resolution).
   - Converts table-level tenant isolation into an indexable `IN (SELECT ...)` or `JOIN` predicate, allowing PostgreSQL to perform index scans / bitmap index scans ($O(\log N)$) on target tables.

---

## 3. High-Volume Synthetic Benchmark Specification

The benchmark is implemented in [`tests/db/021_authorization_performance_benchmark.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_authorization_performance_benchmark.sql). It creates 10,000 synthetic records in a temporary table partitioned across 3 organizations (`NORTE` authorized, `SUR` unauthorized, `OESTE` unauthorized) inside an isolated `BEGIN ... ROLLBACK` block.

### Pattern A: Direct Per-Row `can_org` Invocation
```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*), SUM(amount)
FROM temp_bench_financial_records
WHERE private.can_org(organization_id, 'RECORD_VIEW');
```
- **Expected Plan Shape**: Sequential scan (`Seq Scan`) with per-row filter predicate invoking `private.can_org`.
- **Characteristics**: CPU and buffer amplification proportional to the total number of rows scanned.

### Pattern B: Set-Based IN Subquery via `authorized_orgs_for_capability`
```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*), SUM(amount)
FROM temp_bench_financial_records
WHERE organization_id IN (
    SELECT organization_id
    FROM private.authorized_orgs_for_capability('RECORD_VIEW')
);
```
- **Expected Plan Shape**: Single `InitPlan` execution of `private.authorized_orgs_for_capability`, followed by a `Bitmap Index Scan` or `Index Scan` on `idx_temp_bench_records_org`.
- **Characteristics**: Constant authorization overhead; data filtering driven entirely by index scan.

### Pattern C: Set-Based Join via `authorized_orgs_for_capability`
```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*), SUM(r.amount)
FROM temp_bench_financial_records r
JOIN private.authorized_orgs_for_capability('RECORD_VIEW') a
  ON r.organization_id = a.organization_id;
```
- **Expected Plan Shape**: `Nested Loop` or `Hash Join` between the authorized organization set and the target table index.

---

## 4. Index Evaluation & Observations

Migration 021 introduced two covering indexes:
1. `idx_eco_org_members_covering` on `public.eco_organization_members (user_profile_id, is_active) INCLUDE (organization_id, role_template_id)`:
   - **Expected Value**: Supports index-only scans when `private.authorized_orgs_for_capability` fetches all active memberships for a profile without reading table heap blocks.
2. `idx_eco_user_platform_role_covering` on `public.eco_user_platform_role (user_profile_id, is_active) INCLUDE (role_template_id)`:
   - **Observation**: `eco_user_platform_role` already has `PRIMARY KEY (user_profile_id)`. Because each user has at most one platform role row, the primary key index already provides direct point lookups. The covering index should be observed under DEV workload before declaring proven performance benefit over the PK index.

---

## 5. Architectural Guidance for Future Work Packages (A3.2.1+)

- **Low-Cardinality Tables & Configuration Entities**: Direct scalar helper calls or simple tenant matching may be evaluated where table size is structurally bounded.
- **High-Volume Tables (e.g. `eco_normalized_records`, `eco_financial_movements`, `eco_audit_events`)**: MUST adopt set-based authorization patterns (`private.authorized_orgs_for_capability` in joins or `IN` clauses) to ensure indexable scan paths and prevent $O(N)$ function evaluation overhead.
