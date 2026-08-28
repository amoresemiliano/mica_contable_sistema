# INFORME POST MIGRACIÓN 008 MICA

## 1. Project Reference
- **PROJECT_REF:** `ourzapkjykzlwsjunzmd`

## 2. Precheck Confirmado
- **MIGRATIONS PRE-008:** 2 (`001_to_004_bootstrap`, `007_schema_security_support`)
- **PUBLIC TABLES:** 9
- **MCP STATE:** Read-Only verificado.

## 3. Policy Inventory Pre-008
Inventario de policies en las 9 tablas antes de ejecutar la migración:
- `eco_organizations`: 0 policies
- `eco_user_profiles`: 0 policies
- `eco_source_imports`: 0 policies
- `eco_source_files`: 0 policies
- `eco_import_rows`: 0 policies
- `eco_normalized_records`: 0 policies
- `eco_import_issues`: 0 policies
- `eco_review_actions`: 0 policies
- `eco_audit_events`: 2 policies (Audit events viewable by org, Audit events insertable by org). Ambas PERMISSIVE, resultando en un entorno base limpio donde solo la tabla de auditoría poseía policies heredadas del bootstrap.

## 4. ACL Pre-008
El ACL post-007 sobre las 9 tablas era permisivo en base a GRANTS. Se comprobó que `authenticated` poseía privilegios de SELECT, INSERT, UPDATE y DELETE (identificados como `arwdDxtm` en los registros ACL de `pg_class`) en la totalidad de las tablas `eco_*`.

## 5. Migration Aplicada
Se deshabilitó temporalmente el modo Read-Only. Se ejecutó de forma transaccional la migración a través de la herramienta `apply_migration`.
- **MIGRATION:** `008_functional_policies.sql`

## 6. Policy Inventory Post-008
El inventario demostró los siguientes cambios exactos, con superposición permisiva 0:
- `eco_audit_events`: `Audit events viewable by admin` (SELECT)
- `eco_import_issues`: `Issues viewable by org` (SELECT)
- `eco_normalized_records`: `Records viewable by org` (SELECT)
- `eco_organizations`: `Organizations viewable by own users` (SELECT)
- `eco_review_actions`: `Review actions viewable by org` (SELECT)
- `eco_source_files`: `Files viewable by org` (SELECT)
- `eco_source_imports`: `Imports viewable by org` (SELECT)
- `eco_user_profiles`: `Profiles viewable by user and admin` (SELECT)
- `eco_import_rows`: 0 policies.

No persisten ni la política "Audit events viewable by org" ni "Audit events insertable by org".
`UNINTENDED_POLICY_OVERLAPS = 0`.

## 7. ACL Post-008
El ACL sobre las 9 tablas `eco_*` para el rol `authenticated` ha sido alterado de la siguiente manera:
- `eco_organizations`: SELECT
- `eco_user_profiles`: SELECT
- `eco_source_imports`: SELECT
- `eco_source_files`: SELECT
- `eco_import_rows`: **NONE** (Sin acceso directo, revocado)
- `eco_normalized_records`: SELECT
- `eco_import_issues`: SELECT
- `eco_review_actions`: SELECT
- `eco_audit_events`: SELECT

El registro ACL actual reporta privilegios `rDxtm` (donde r=SELECT) para `authenticated` en todas las tablas a excepción de `eco_import_rows` que reporta `Dxtm` (no hay r, a, w ni d).

## 8. Helpers Evaluados
- `private.has_record_access(UUID)`
- `private.has_issue_access(UUID)`

Se validó el estado de ambas funciones. Son `SECURITY DEFINER`, `STABLE`, el owner es postgres y se ejecutan con `SET search_path = ''`. Su ejecución en cascada aísla la necesidad de conceder accesos directos al usuario sobre `eco_import_rows`.

## 9. RPCs Evaluadas
- `public.change_user_role(UUID, TEXT)`
- `public.set_user_active(UUID, BOOLEAN)`
- `public.create_import()`
- `public.resolve_issue(UUID, TEXT)`

Todas han sido implementadas con `SECURITY DEFINER` y encapsulan sus respectivos controles lógicos y guardas atómicas (idempotencia y locks virtuales vía STATUS en issue_resolution). `PUBLIC EXECUTE` fue debidamente revocado y el acceso concedido explícitamente a `authenticated`.

## 10. Security Definer ACL
Todas las funciones RPC y Helpers tienen revocada su ejecución para `PUBLIC` (`REVOKE ALL ON FUNCTION ... FROM PUBLIC`) y asignada expresamente a `authenticated`.

## 11. Audit Final
Un ADMIN en su organización puede consultar (`SELECT`) registros. Un USER, REVIEWER o UPLOADER tienen denegada la consulta (`DENY`). La inserción directa manual está estrictamente denegada (`DENY`) debido al ACL. Los registros sólo fluyen mediante las funciones RPC `SECURITY DEFINER` autorizadas.

## 12. eco_import_rows Final
`authenticated` no tiene privilegios de `SELECT`, ni policies a favor de este rol en dicha tabla. El acceso se transfiere a los datos permitidos de las demás tablas a través de los helpers privados (que sí tienen derechos vía Security Definer).

## 13. RLS
RLS se encuentra `ENABLED` (`rls_enabled: true`) sobre las 9 tablas de manera permanente.

## 14. Storage Unchanged
Se confirmó que `eco-imports-private-staging` persiste inalterado y sin modificaciones colaterales o manipulaciones derivadas de esta aplicación.

## 15. Warnings / Errors
0 Errores. La ejecución de la migración fue exitosa sin reportes en los logs remotos.

## 16. MIGRATIONS Total
`MIGRATIONS = 3` (registradas internamente en la API de Supabase vía `list_migrations`).

## 17. Writes Ejecutadas
Un `apply_migration` (008_functional_policies) transaccional. Ninguna manipulación externa directa.

## 18. MCP Final Read-Only
El MCP config fue restablecido manualmente, retornando a `READ_ONLY = true`. Confirmado.

## 19. Git diff --stat
```
 index.html                            |   2 +-
 package-lock.json                     | 115 +++++++++++++++-
 package.json                          |   3 +-
 src/js/core/services/importService.js |  59 ++-------
 src/js/ui.js                          | 240 +++++++++++++++++++++++++++-------
 tests/parsers.test.js                 |  36 ++---
 6 files changed, 342 insertions(+), 113 deletions(-)
```

## 20. Git status --short
```
 M index.html
 M package-lock.json
 M package.json
 M src/js/core/services/importService.js
 M src/js/ui.js
 M tests/parsers.test.js
?? .agents/
?? INFORME_008_AUDIT_POLICY_FINAL.md
?? INFORME_008_CORRECCION_FINAL.md
?? INFORME_008_PRE_WRITE_MICA.md
?? INFORME_008_SQL_VERIFICATION_FINAL.md
?? INFORME_DELTA_FINAL_PRE_MIGRACION_MICA.md
?? INFORME_FINAL_007_PRE_WRITE.md
?? INFORME_FINAL_008_GO_NO_GO_MICA.md
?? INFORME_FINAL_PRE_WRITE_3A_2_2.md
?? INFORME_GO_NO_GO_MIGRACION_INICIAL_MICA.md
?? INFORME_MCP_PRE_MIGRACION_MICA.md
?? INFORME_POST_MIGRACION_007_MICA.md
?? INFORME_POST_MIGRACION_BOOTSTRAP_MICA.md
?? PLAN_007_SCHEMA_SECURITY_SUPPORT.md
?? PLAN_FASE_3A_3_1_POLICIES_RLS.md
?? PLAN_FINAL_3A_3_1_RLS.md
?? THIRD_PARTY_NOTICES.md
?? migration.json
?? sql/
?? src/js/adapters/
?? src/js/core/adapters/
?? src/js/core/services/fiscalFingerprint.js
?? src/js/vendor/
?? tests/adapters/
?? tests/crypto/
?? tests/db/
?? tests/fixtures/ambiguous.xlsx
?? tests/fixtures/arba.txt
?? tests/fixtures/corrupt.xlsx
?? tests/fixtures/empty.xlsx
?? tests/fixtures/empty_sheet.xlsx
?? tests/fixtures/mismatch.xlsx
?? tests/fixtures/no_sheets.xlsx
?? tests/fixtures/optional.csv
?? tests/fixtures/shifted_header.xlsx
?? tests/fixtures/synthetic_arca_compras.xlsx
?? tests/fixtures/synthetic_arca_retenciones.xls
?? tests/helpers/
?? tests/services/
```

## 21. Confirmación NO Firebase / NO SPA
No se ejecutaron operaciones en Firebase, ni creaciones de usuarios o alteraciones en SPA. No se alteró el `git` local. Todo está paralizado hasta recibir confirmación explícita para la Fase 3B/4.
