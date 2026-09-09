# Current Work Package: WP-A3.2.0

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.0 — AUTHORIZATION PRIMITIVES SAFETY & PERFORMANCE VALIDATION  
**MODE**: VALIDATION & MIGRATION PREPARATION  
**STATUS**: `WP_A3_2_0_VALIDATION_COMPLETE`  
**BASELINE SHA**: `a96cc5a0a07190f1c1f61b4c9255b56dfb4f2dfc`  
**READY_FOR**: `READY_FOR_MANUAL_DEV_DB_VALIDATION`  

---

## Deliverables Summary

1. `sql/021_preflight_check.sql` (Preflight verification for M021)
2. `sql/021_authorization_primitives.sql` (Covering indexes + `private.authorized_orgs_for_capability`)
3. `sql/021_postcheck.sql` (Post-migration attribute and index assertions)
4. `sql/021_authorization_primitives_down.sql` (Targeted rollback strictly isolated to M021)
5. `tests/db/021_authorization_primitives.sql` (Transactional behavioral, synthetic override & set helper test suite)
6. `docs/MICA_A3_2_0_PRIMITIVES_DESIGN.md` (Structural, security, volatility, and non-recursion analysis)
7. `docs/MICA_A3_2_0_PERFORMANCE_TEST_PLAN.md` (Micro-benchmarks & 10k-row query plan evaluation)
8. `docs/MICA_A3_2_0_SECURITY_ACCEPTANCE_MATRIX.md` (Real user baseline truth table & synthetic fixtures)
9. `docs/MICA_A3_2_0_RLS_PATTERN_DECISION.md` (Two-Tier RLS policy decision: Direct vs Auth Join Set)
10. `tests/services/authorizationPrimitivesValidation.test.js` (Automated Jest test suite)

---

## Core Invariants & Governance

- `ACTIVE CONTEXT != AUTHORIZATION` (Active context indicates selected organization only; never grants authority).
- Zero business domain authorization cutovers performed in WP-A3.2.0.
- All test suites (21 suites, 267 tests) pass cleanly.
