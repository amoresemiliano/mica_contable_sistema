# MICA Authorization Performance Test Plan & Benchmark Specification (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: BENCHMARK SPECIFICATION & DEV REPRODUCIBILITY HARNESS  
> **Evidence Taxonomy**: Explicitly segmented into `OBSERVED_DEV_EVIDENCE`, `NOT_YET_OBSERVED_DEV`, `UNVERIFIED_PREVIOUS_DESIGN_CLAIM`, and `ARCHITECTURAL_PRINCIPLE`.

---

## 1. Evidence Classification & Taxonomy

| Classification | Target Context | Row Count Range | Status & Purpose |
| :--- | :--- | :--- | :--- |
| **`OBSERVED_DEV_EVIDENCE`** | Supabase DEV Environment | **10,000 synthetic rows** | Empirically captured metrics from executed benchmark scripts in Supabase SQL Editor |
| **`NOT_YET_OBSERVED_DEV`** | Supabase DEV Environment | **10,000 synthetic rows** | Benchmark scripts prepared and ready for individual manual execution in Supabase SQL Editor |
| **`UNVERIFIED_PREVIOUS_DESIGN_CLAIM`** | Prior Theoretical / Design Estimations | N/A | Previously recorded metrics (e.g. 14.8x speedup) prior to full three-way manual DEV benchmark reproduction |
| **`ARCHITECTURAL_PRINCIPLE`** | System Design Invariants | All volumes | Per-row authorization function evaluation vs set-based indexable filtering |

---

## 2. Supabase SQL Editor Harness Architecture

Because Supabase SQL Editor executes scripts in batch mode and only displays the output of the final statement in a multi-statement transaction before `ROLLBACK`, the benchmark harness is structured into **three self-contained, independent SQL files**:

1. [`tests/db/021_benchmark_a_direct_can_org.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_a_direct_can_org.sql) — **Pattern A** (Direct Per-Row `can_org`)
2. [`tests/db/021_benchmark_b_set_based_in.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_b_set_based_in.sql) — **Pattern B** (Set-Based `IN` Predicate)
3. [`tests/db/021_benchmark_c_set_based_join.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_c_set_based_join.sql) — **Pattern C** (Set-Based `JOIN`)

### Common Fixture Invariants Across All Three Harnesses
Each file executes atomically within `BEGIN ... ROLLBACK` and guarantees zero persistent database side effects:
- Creates an isolated synthetic identity in `auth.users` via standard Supabase auth trigger lifecycle.
- Resolves the trigger-generated `eco_user_profiles` row and sets `is_active = TRUE`.
- Assigns `ACCOUNTANT` role template in Organization `NORTE` (`RECORD_VIEW` capability).
- Sets transaction-local identity claim via `set_config('request.jwt.claim.sub', v_synth_auth_id::text, true)`.
- Populates exactly 10,000 synthetic records in a temporary table `temp_bench_financial_records` (5,000 in `NORTE` [authorized], 2,500 in `SUR` [unauthorized], 2,500 in `OESTE` [unauthorized]).
- Builds an index on `temp_bench_financial_records(organization_id)` and executes `ANALYZE`.
- Runs exactly **one** `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` statement and terminates with `ROLLBACK`.

---

## 3. Benchmark Execution Patterns & Observed Evidence

### Pattern A: Direct Per-Row `can_org` Invocation
- **File**: [`tests/db/021_benchmark_a_direct_can_org.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_a_direct_can_org.sql)
- **Status**: `NOT_YET_OBSERVED_DEV` (Pending individual run in Supabase SQL Editor)
- **Query**:
  ```sql
  EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
  SELECT COUNT(*), SUM(amount)
  FROM temp_bench_financial_records
  WHERE private.can_org(organization_id, 'RECORD_VIEW');
  ```
- **Expected Plan Shape**: Sequential scan (`Seq Scan`) with per-row filter predicate invoking `private.can_org`.

---

### Pattern B: Set-Based IN Subquery via `authorized_orgs_for_capability`
- **File**: [`tests/db/021_benchmark_b_set_based_in.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_b_set_based_in.sql)
- **Status**: `NOT_YET_OBSERVED_DEV` (Pending individual run in Supabase SQL Editor)
- **Query**:
  ```sql
  EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
  SELECT COUNT(*), SUM(amount)
  FROM temp_bench_financial_records
  WHERE organization_id IN (
      SELECT organization_id
      FROM private.authorized_orgs_for_capability('RECORD_VIEW')
  );
  ```
- **Expected Plan Shape**: Single `InitPlan` execution of `private.authorized_orgs_for_capability`, followed by index-driven filtering.

---

### Pattern C: Set-Based Join via `authorized_orgs_for_capability`
- **File**: [`tests/db/021_benchmark_c_set_based_join.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_c_set_based_join.sql)
- **Status**: `OBSERVED_DEV_EVIDENCE` (Empirically verified in Supabase DEV)
- **Query**:
  ```sql
  EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
  SELECT COUNT(*), SUM(r.amount)
  FROM temp_bench_financial_records r
  JOIN private.authorized_orgs_for_capability('RECORD_VIEW') a
    ON r.organization_id = a.organization_id;
  ```
- **Observed Execution Metrics (Supabase DEV)**:
  - **Plan Type**: `Merge Join`
  - **Authorized Rows Returned**: 5,000 (out of 10,000 total scanned)
  - **Helper Function Scan**: `private.authorized_orgs_for_capability` executed with `loops=1` (constant single execution)
  - **Index Scan**: `idx_temp_bench_records_org` utilized
  - **Planning Time**: `0.065 ms`
  - **Execution Time**: `3.661 ms`
  - *Note*: This point measurement reflects the indexed join plan shape in DEV. It is documented as observed empirical evidence and not as an inflexible system-wide SLA.

---

## 4. Index Evaluation & Observations

Migration 021 introduced two covering indexes:
1. `idx_eco_org_members_covering` on `public.eco_organization_members (user_profile_id, is_active) INCLUDE (organization_id, role_template_id)`:
   - **Expected Value**: Supports index-only scans when `private.authorized_orgs_for_capability` fetches active memberships for a profile without reading table heap blocks.
2. `idx_eco_user_platform_role_covering` on `public.eco_user_platform_role (user_profile_id, is_active) INCLUDE (role_template_id)`:
   - **Observation**: `eco_user_platform_role` already has `PRIMARY KEY (user_profile_id)`. Because each user has at most one platform role row, the primary key index already provides direct point lookups. The covering index should be observed under DEV workload before declaring proven performance benefit over the PK index.

---

## 5. Architectural Guidance for Future Work Packages (A3.2.1+)

- **Low-Cardinality Tables & Configuration Entities**: Direct scalar helper calls or simple tenant matching may be evaluated where table size is structurally bounded.
- **High-Volume Tables (e.g. `eco_normalized_records`, `eco_financial_movements`, `eco_audit_events`)**: MUST adopt set-based authorization patterns (`private.authorized_orgs_for_capability` in joins or `IN` clauses) to ensure indexable scan paths and prevent $O(N)$ function evaluation overhead.
