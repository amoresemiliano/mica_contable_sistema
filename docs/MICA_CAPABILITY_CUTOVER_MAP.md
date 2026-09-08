# MICA Capability Cutover Map (WP-A3.1)

> **Document Status**: DISCOVERY COMPLETE & FROZEN  
> **Baseline Commit**: `7aae65c9029822d120339670b962b596bae94cd7`  
> **Purpose**: Definitive mapping from legacy roles, helpers, and RPC permissions to M019 fine-grained capabilities.

---

## 1. Executive Summary & Mapping Principles

WP-A3.1 establishes the bridge between legacy coarse roles (`SUPERADMIN`, `ADMIN`, `UPLOADER`, `REVIEWER`, `USER`) and M019 capability primitives. 

### Core Mapping Rules
1. **Use M019 Capabilities Only**: No new capabilities may be created in WP-A3.1 or WP-A3.2.
2. **Support 1-to-N Expansion**: Coarse legacy roles (e.g. `UPLOADER`) split into multiple granular capability checks depending on the operation domain (e.g., invoice import vs. bank import vs. payroll import).
3. **Strict Equivalence Taxonomy**:
   - `EXACT`: Target capability matches legacy functional boundary byte-for-byte.
   - `NARROWER`: Target capability is more restrictive than legacy check (Desirable security tightening).
   - `BROADER`: Target capability is wider than legacy check (**BLOCKED** from automatic cutover without explicit approval).
   - `NO_EQUIVALENT`: Legacy check has no capability equivalent (**BLOCKED** from cutover until mapped).

---

## 2. Legacy Role to Capability Translation Map

| Legacy Role | Discovered Usage Context | Mapped M019 Role Template | Target Capabilities Granted | Equivalence | Cutover Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`SUPERADMIN` (Platform)** | Cross-tenant administration, global catalog management, multi-org context switching | `PLATFORM_SUPERADMIN` | `PLATFORM_MANAGE`, `ORGANIZATION_CREATE`, `ORGANIZATION_UPDATE`, `ORGANIZATION_ARCHIVE`, `GLOBAL_USER_MANAGE`, `PLAN_MANAGE`, `GLOBAL_CATALOG_VIEW`, `GLOBAL_CATALOG_MANAGE`, `CATALOG_ASSIGN_ANY_ORG`, `RATE_MANAGE_ANY_ORG`, `ACCESS_ANY_ORG`, `REPORT_COMPARE_SCOPED_ORGS`, `REPORT_CONSOLIDATED_SCOPED_ORGS`, `SAAS_ANALYTICS_VIEW`, `SUPPORT_IMPERSONATE`, `HARD_DELETE_EXCEPTIONAL`, `AUDIT_PLATFORM_VIEW` | `EXACT` | Ready for Cutover |
| **`SUPERADMIN` (Bridge)** | Accounting superadmin acting across assigned client organizations | `ACCOUNTING_SUPERADMIN` | Platform: `GLOBAL_CATALOG_VIEW`, `CATALOG_ASSIGN_ANY_ORG`, `RATE_MANAGE_ANY_ORG`, `REPORT_COMPARE_SCOPED_ORGS`, `REPORT_CONSOLIDATED_SCOPED_ORGS`<br>Org Bridge: `ORG_VIEW`, `ORG_SETTINGS_VIEW`, `IMPORT_VIEW`, `IMPORT_CREATE`, `IMPORT_RETRY`, `IMPORT_REVIEW`, `RECORD_VIEW`, `RECORD_CLASSIFY`, `RECORD_SOFT_DELETE`, `RECORD_RESTORE`, `PERCEPTION_IMPORT`, `BANK_IMPORT`, `PAYROLL_IMPORT`, `ISSUE_RESOLVE`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE`, `TICKET_VIEW_ORG`, `AUDIT_VIEW_ORG` | `EXACT` | Ready for Cutover (Requires Org Membership) |
| **`ADMIN`** | Tenant administrative authority | `TENANT_ADMIN` | `ORG_VIEW`, `ORG_SETTINGS_VIEW`, `ORG_SETTINGS_MANAGE`, `ORG_MEMBER_VIEW`, `ORG_MEMBER_INVITE`, `ORG_MEMBER_MANAGE`, `ORG_MEMBER_PERMISSION_MANAGE`, `IMPORT_VIEW`, `IMPORT_CREATE`, `IMPORT_RETRY`, `IMPORT_REVIEW`, `RECORD_VIEW`, `RECORD_CLASSIFY`, `RECORD_SOFT_DELETE`, `PERCEPTION_IMPORT`, `BANK_IMPORT`, `PAYROLL_IMPORT`, `ISSUE_RESOLVE`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE`, `TICKET_VIEW_ORG`, `AUDIT_VIEW_ORG` | `EXACT` | Ready for Cutover |
| **`UPLOADER`** | Data import and file upload operations | `UPLOADER` | `ORG_VIEW`, `IMPORT_VIEW`, `IMPORT_CREATE`, `IMPORT_RETRY`, `RECORD_VIEW`, `PERCEPTION_IMPORT`, `BANK_IMPORT`, `PAYROLL_IMPORT`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE` | `NARROWER` | Tightening (No member management) |
| **`REVIEWER`** | Data classification and issue resolution | `REVIEWER` | `ORG_VIEW`, `IMPORT_VIEW`, `IMPORT_REVIEW`, `RECORD_VIEW`, `RECORD_CLASSIFY`, `ISSUE_RESOLVE`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE` | `NARROWER` | Tightening (No upload or member management) |
| **`USER`** | Read-only / standard user access | `READ_ONLY` / `USER` | `ORG_VIEW`, `ORG_SETTINGS_VIEW`, `IMPORT_VIEW`, `IMPORT_REVIEW`, `RECORD_VIEW`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE` | `EXACT` | Ready for Cutover |

---

## 3. RPC-by-RPC Capability Mapping & Equivalence Matrix

| RPC Name | Legacy Authorization Predicate | Target Capability Check | Equivalence Class | Cutover Classification |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | `private.func_role() = 'ADMIN'` | `private.can_org(v_org_id, 'ORG_MEMBER_PERMISSION_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.set_user_active` | `private.func_role() = 'ADMIN'` | `private.can_org(v_org_id, 'ORG_MEMBER_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.create_import` | `private.func_role() IN ('ADMIN','UPLOADER','SUPERADMIN')` | `private.can_org(v_org_id, 'IMPORT_CREATE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.persist_import_batch` | `private.func_role() IN ('ADMIN','UPLOADER','SUPERADMIN')` | `private.can_org(v_org_id, 'IMPORT_CREATE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.persist_perceptions_batch` | `private.func_role() IN ('ADMIN','UPLOADER','SUPERADMIN')` | `private.can_org(v_org_id, 'PERCEPTION_IMPORT')` | `NARROWER` | `CAPABILITY_NARROWER` (Security Tightening) |
| `public.persist_financial_movements_batch` | `private.func_role() IN ('ADMIN','UPLOADER','SUPERADMIN')` | `private.can_org(v_org_id, 'BANK_IMPORT')` / `'PAYROLL_IMPORT'` | `NARROWER` | `CAPABILITY_NARROWER` (Security Tightening) |
| `public.request_failed_import_retry` | `private.func_role() IN ('ADMIN','UPLOADER','SUPERADMIN')` | `private.can_org(v_org_id, 'IMPORT_RETRY')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.resolve_issue` | `private.func_role() IN ('ADMIN','REVIEWER','SUPERADMIN')` | `private.can_org(v_org_id, 'ISSUE_RESOLVE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.soft_delete_normalized_record` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_SOFT_DELETE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.restore_normalized_record` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_RESTORE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.soft_delete_financial_movement` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_SOFT_DELETE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.restore_financial_movement` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_RESTORE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.update_record_classification` | `private.func_role() IN ('ADMIN','REVIEWER','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_CLASSIFY')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.update_movement_classification` | `private.func_role() IN ('ADMIN','REVIEWER','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_CLASSIFY')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.bulk_update_record_classification` | `private.func_role() IN ('ADMIN','REVIEWER','SUPERADMIN')` | `private.can_org(v_org_id, 'RECORD_CLASSIFY')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.create_global_tax_category` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_platform('GLOBAL_CATALOG_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.update_global_tax_category` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_platform('GLOBAL_CATALOG_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.create_global_economic_activity` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_platform('GLOBAL_CATALOG_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.update_global_economic_activity` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_platform('GLOBAL_CATALOG_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.upsert_arca_activity_catalog` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_platform('GLOBAL_CATALOG_MANAGE')` | `EXACT` | `CAPABILITY_EXACT` |
| `public.create_org_activity_iibb_rate` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(p_org_id, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('RATE_MANAGE_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |
| `public.update_org_activity_iibb_rate` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(v_org_id, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('RATE_MANAGE_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |
| `public.switch_superadmin_org_context` | `private.func_role() = 'SUPERADMIN'` | `private.can_platform('SUPPORT_IMPERSONATE')` / `ACCESS_ANY_ORG` | `BROADER` | `CAPABILITY_BROADER` (BLOCKED from auto-cutover) |
| `public.assign_tax_category_to_org` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(target_org, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('CATALOG_ASSIGN_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |
| `public.unassign_tax_category_from_org` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(target_org, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('CATALOG_ASSIGN_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |
| `public.assign_economic_activity_to_org` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(target_org, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('CATALOG_ASSIGN_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |
| `public.unassign_economic_activity_from_org` | `private.func_role() IN ('ADMIN','SUPERADMIN')` | `private.can_org(target_org, 'ORG_SETTINGS_MANAGE')` OR `private.can_platform('CATALOG_ASSIGN_ANY_ORG')` | `NARROWER` | `CAPABILITY_NARROWER` |

---

## 4. Summary of Equivalence Counts

- **CAPABILITY_EXACT**: 19 RPCs
- **CAPABILITY_NARROWER**: 7 RPCs
- **CAPABILITY_BROADER**: 1 RPC (`switch_superadmin_org_context` — BLOCKED from automatic cutover)
- **CAPABILITY_NO_EQUIVALENT**: 0 RPCs (All RPCs successfully mapped to M019 primitives)
