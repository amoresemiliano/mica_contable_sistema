# Current Work Package: WP-A3.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.1 — AUTHORIZATION DEPENDENCY MAPPING + COMPATIBILITY CONTRACT  
**MODE**: DISCOVERY / DOCUMENTATION ONLY  
**STATUS**: `WP_A3_1_DISCOVERY_COMPLETE`  
**BASELINE SHA**: `7aae65c9029822d120339670b962b596bae94cd7`  
**READY FOR**: `READY_FOR_ADVERSARIAL_REVIEW`  

---

## Deliverables Summary

1. `docs/MICA_AUTHORIZATION_DEPENDENCY_MATRIX.md` (45 Total Discovered Dependencies)
2. `docs/MICA_CAPABILITY_CUTOVER_MAP.md` (Legacy to M019 Capabilities Translation Map)
3. `docs/MICA_AUTHORIZATION_COMPATIBILITY_CONTRACT.md` (Frozen Security Invariants & Authorization Change Freeze Contract)
4. `docs/MICA_AUTHORIZATION_CUTOVER_SEQUENCE.md` (Vertical Domain-Driven Cutover Plan A3.2.0 through A3.2.8)
5. `docs/MICA_AUTHORIZATION_RISK_REGISTER.md` (Security Definer, RLS Performance, Storage, & Stale UI State Risks)

---

## Core Invariants & Governance

- `ACTIVE CONTEXT != AUTHORIZATION` (Active context indicates selected organization only; never grants authority).
- Zero runtime code or database schema changes executed in WP-A3.1.
- All 20 existing unit/integration test suites (264 tests) pass cleanly.
