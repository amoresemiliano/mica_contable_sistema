# MICA Authorization Performance Test Plan & Benchmark Specification (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: OBSERVED DEV PERFORMANCE EVIDENCE CONSOLIDATED & HARNESS SPECIFICATION  
> **Evidence Taxonomy**: Explicitly segmented into `OBSERVED_DEV_EVIDENCE` and `ARCHITECTURAL_PRINCIPLE`.

---

## 1. Evidence Classification & Taxonomy

| Classification | Target Context | Row Count Range | Status & Purpose |
| :--- | :--- | :--- | :--- |
| **`OBSERVED_DEV_EVIDENCE`** | Supabase DEV Environment | **10,000 synthetic rows** | Empirically captured metrics from executed benchmark scripts in Supabase SQL Editor |
| **`ARCHITECTURAL_PRINCIPLE`** | System Design Invariants | All volumes | Per-row authorization function evaluation vs set-based indexable/relational filtering |

*Governance Note*: Prior theoretical design claims (e.g. hypothetical universal speedup multiples) and rigid artificial thresholds have been retired. All metrics recorded below are point-in-time observations in Supabase DEV and must not be interpreted as universal performance SLAs.

---

## 2. Supabase SQL Editor Harness Architecture

Because Supabase SQL Editor executes scripts in batch mode and displays only the output of the final statement in a multi-statement transaction before `ROLLBACK`, the benchmark harness is structured into **three self-contained, independent SQL files**:

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

## 3. Benchmark Execution Patterns & Observed DEV Evidence

### Pattern A: Direct Per-Row `can_org` Invocation
- **File**: [`tests/db/021_benchmark_a_direct_can_org.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_a_direct_can_org.sql)
- **Status**: `OBSERVED_DEV_EVIDENCE` (Empirically verified in Supabase DEV)
- **Query**:
  ```sql
  EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
  SELECT COUNT(*), SUM(amount)
  FROM temp_bench_financial_records
  WHERE private.can_org(organization_id, 'RECORD_VIEW');
  ```
- **Observed Execution Metrics (Supabase DEV)**:
  - **Plan Type**: `Seq Scan on temp_bench_financial_records`
  - **Filter Predicate**: `private.can_org(organization_id, 'RECORD_VIEW'::text)`
  - **Authorized Rows Returned**: 5,000
  - **Rows Removed by Filter**: 5,000
  - **Buffers**: `shared hit=90348`, `local hit=121`
  - **Planning Time**: `0.118 ms`
  - **Execution Time**: `507.199 ms`
  - **Observation**: Per-row evaluation forces 10,000 PL/pgSQL function evaluations, generating 90,348 buffer hits and excessive execution latency.

---

### Pattern B: Set-Based IN Subquery via `authorized_orgs_for_capability`
- **File**: [`tests/db/021_benchmark_b_set_based_in.sql`](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/tests/db/021_benchmark_b_set_based_in.sql)
- **Status**: `OBSERVED_DEV_EVIDENCE` (Empirically verified in Supabase DEV)
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
- **Observed Execution Metrics (Supabase DEV)**:
  - **Plan Type**: `Hash Join` (Seq Scan over 10,000 target rows hashed with Function Scan)
  - **Helper Function Scan**: `private.authorized_orgs_for_capability` executed with `rows=1`, `loops=1`
  - **Authorized Rows Returned**: 5,000
  - **Buffers**: `shared hit=353`, `local hit=121`
  - **Planning Time**: `0.223 ms`
  - **Execution Time**: `4.574 ms`
  - **Planner Autonomy Note**: `idx_temp_bench_records_org` was **not** selected by the query planner for Pattern B. Given the selectivity (50% of the table matching), the planner determined that a `Seq Scan` + `Hash Join` was more efficient than index traversal. Despite not using an index, execution time dropped from 507.2 ms to 4.574 ms due to single helper invocation (`loops=1`).

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
  - **Helper Function Scan**: `private.authorized_orgs_for_capability` executed with `rows=1`, `loops=1`
  - **Target Index Scan**: `idx_temp_bench_records_org` utilized
  - **Authorized Rows Returned**: 5,000
  - **Planning Time**: `0.065 ms`
  - **Execution Time**: `3.661 ms`
  - **Observation**: Demonstrates that an indexed Merge Join plan is selected when expressed as an explicit relational join, executing in 3.661 ms.

---

## 4. Empirical Interpretation & Findings

Point-in-time DEV comparison across 10,000 synthetic records:
- **Pattern A (Per-Row `can_org`)**: `507.199 ms` (`shared hit=90348`)
- **Pattern B (Set-Based `IN`)**: `4.574 ms` (`shared hit=353`)
- **Pattern C (Set-Based `JOIN`)**: `3.661 ms` (`loops=1`, Merge Join with Index)

### Key Conclusions:
1. **Per-Row Evaluation Bottleneck**: Direct per-row `private.can_org` calls cause repeated authorization resolution on every row scanned, producing massive buffer churn and severe execution penalties on large tables.
2. **Set-Based Efficiency**: Both Pattern B and Pattern C resolve authorized organizations exactly once (`loops=1`), reducing shared buffer hits by over 99.6% (from 90,348 to 353).
3. **Planner Autonomy Validation**: Pattern B proves that set-based authorization yields dramatic performance improvements even when the PostgreSQL planner chooses `Seq Scan` + `Hash Join` over an index scan based on data distribution. Pattern C proves that indexed join paths remain available and fast.

---

## 5. Index Evaluation & Status

Migration 021 introduced two covering indexes:
1. `idx_eco_org_members_covering` on `public.eco_organization_members (user_profile_id, is_active) INCLUDE (organization_id, role_template_id)`:
   - **Evidence Status**: `EVALUATION_DEFERRED`. The top-level benchmark encapsulates membership lookups inside `private.authorized_orgs_for_capability` (reported as `Function Scan`), making internal index usage invisible to top-level `EXPLAIN`. Its value is structurally sound for index-only scans, but unproven at top level without function-internal instrumentation.
2. `idx_eco_user_platform_role_covering` on `public.eco_user_platform_role (user_profile_id, is_active) INCLUDE (role_template_id)`:
   - **Evidence Status**: `UNPROVEN_OVER_PK`. Because `eco_user_platform_role` has `PRIMARY KEY (user_profile_id)` and cardinality is at most 1 row per user, the covering index provides negligible benefit over the primary key index.

*Governance Decision*: Neither index will be modified or dropped during WP-A3.2.0. Their status is documented for ongoing observation in subsequent phases.

---

## 6. Architectural Rules Frozen for Future Work Packages (A3.2.1+)

For subsequent vertical slices and RLS policy implementations:

1. **No Per-Row Scalar Authorization on High-Volume Tables**: Tables with high or unbounded volume (e.g. `eco_normalized_records`, `eco_financial_movements`, `eco_audit_events`, `eco_invoices`) MUST NOT use direct `private.can_org(organization_id, capability)` in per-row RLS predicates.
2. **Set-Based Authorization Standard**: High-volume policies MUST adopt set-based filtering via `private.authorized_orgs_for_capability(capability)` (using `IN` subqueries or `JOIN` expressions).
3. **Preserve Query Planner Autonomy**: The query planner is free to select `Hash Join`, `Merge Join`, `Nested Loop`, `Bitmap Scan`, `Index Scan`, or `Seq Scan` based on actual data volume, selectivity, and distribution. Work package acceptance criteria MUST NOT mandate a specific physical scan type (e.g. "must use index").
4. **Low-Cardinality & Configuration Entities**: Direct scalar helpers or simpler tenant matching may be considered only for bounded, low-cardinality configuration tables when explicitly justified during slice review.
