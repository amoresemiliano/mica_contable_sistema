# MICA RLS Architecture & Target Pattern Decision (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: FROZEN ARCHITECTURAL DECISION  
> **Verdict**: `WRAPPER_PATTERN_REQUIRED` / `AUTHORIZATION_JOIN_PATTERN_REQUIRED` for High-Volume Tables.

---

## 1. Architectural Decision Statement

Direct invocation of `private.can_org(organization_id, 'CAPABILITY')` per-row inside Row Level Security (`USING` / `WITH CHECK`) policies is **PROHIBITED** on high-volume operational tables due to **nested-loop subquery amplification**.

Instead, MICA adopts a **Two-Tier RLS Policy Architecture**:

```
+-----------------------------------------------------------------------------------+
|                        MICA TWO-TIER RLS POLICY PATTERN                           |
+-----------------------------------------------------------------------------------+
| 1. LOW-VOLUME DOMAIN PATTERN (<500 rows):                                         |
|    USING (private.can_org(organization_id, 'CAPABILITY_CODE'))                    |
|                                                                                   |
| 2. HIGH-VOLUME DOMAIN PATTERN (>10,000 rows):                                     |
|    USING (                                                                        |
|        organization_id IN (                                                       |
|            SELECT organization_id                                                 |
|            FROM private.authorized_orgs_for_capability('CAPABILITY_CODE')         |
|        )                                                                          |
|    )                                                                              |
+-----------------------------------------------------------------------------------+
```

---

## 2. Table-by-Table Pattern Assignments for WP-A3.2.x

| Domain & Table Name | Estimated Row Volume | Assigned Pattern Class | RLS Policy Target Definition |
| :--- | :--- | :--- | :--- |
| `eco_organizations` | `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(id, 'ORG_VIEW'))` |
| `eco_user_profiles` | `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (id = self OR private.can_org(organization_id, 'ORG_MEMBER_VIEW'))` |
| `eco_source_imports` | `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(organization_id, 'IMPORT_VIEW'))` |
| `eco_source_files` | `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(import_org_id, 'IMPORT_VIEW'))` |
| `eco_import_issues` | `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(organization_id, 'IMPORT_REVIEW'))` |
| `eco_tax_categories` (Org)| `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(organization_id, 'CATALOG_ORG_VIEW'))` |
| `eco_economic_activities`| `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(organization_id, 'CATALOG_ORG_VIEW'))` |
| `eco_org_activity_iibb_rates`| `LOW_VOLUME_PATTERN` | `DIRECT_CAN_ORG` | `USING (private.can_org(organization_id, 'CATALOG_ORG_VIEW'))` |
| `eco_normalized_records` | `HIGH_VOLUME_PATTERN` | `AUTH_JOIN_SET` | `USING (organization_id IN (SELECT organization_id FROM private.authorized_orgs_for_capability('RECORD_VIEW')))` |
| `eco_financial_movements` | `HIGH_VOLUME_PATTERN` | `AUTH_JOIN_SET` | `USING (organization_id IN (SELECT organization_id FROM private.authorized_orgs_for_capability('RECORD_VIEW')))` |
| `eco_audit_events` | `HIGH_VOLUME_PATTERN` | `AUTH_JOIN_SET` | `USING (organization_id IN (SELECT organization_id FROM private.authorized_orgs_for_capability('AUDIT_VIEW_ORG')))` |

---

## 3. Rationale & Scaling Evidence

1. **Planner Optimization**: The `AUTH_JOIN_SET` pattern evaluates `private.authorized_orgs_for_capability` exactly once per query execution (as an InitPlan), reducing row evaluation cost from $O(N \cdot K)$ (where $K$ is the internal 4-table lookup) to a single set lookup matched against candidate table B-Tree indexes ($O(\log N)$).
2. **Zero JWT Session Coupling**: This pattern avoids fragile JWT claim size bloat or client token invalidation latency while achieving near-instant execution profiles inside pure PostgreSQL.
3. **Fail-Closed Guarantees**: If a user loses a capability or membership, `private.authorized_orgs_for_capability` excludes that organization immediately on the very next query without requiring cache purging.
