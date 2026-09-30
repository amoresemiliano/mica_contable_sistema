# 039b — Contrato, presets, UX y validación MICA

Proyecto canónico: `ourzapkjykzlwsjunzmd`. Base declarada: 036/037/037a/038/039 LIVE, frontend 039 desplegado. Implementación local preparada; **cero SQL ejecutado, commit, push o deploy**. Evidencia DB LIVE manual aportada por el usuario cotejada localmente; aplicación de 039b y navegador pendientes. HORECA y nuevos módulos/reportes quedan fuera de alcance.

## Diagnóstico del root

039 consulta capabilities efectivas ORGANIZATION en contexto TENANT_READY. RECORD_VIEW abre comprobantes, percepciones, bancos y sueldos; REPORT_VIEW abre reportes. Configuración acepta administración PLATFORM.

037 separa alcance y acción: `platform_org_in_scope()` admite al owner con ACCESS_ANY_ORG, pero `can_operate_mica_org()` exige además grants en `eco_platform_role_org_capabilities` u overrides válidos. 031 normalizó VEGEN_PLATFORM_ADMIN y su alcance; no completó el bridge operativo. 036 confirma ese preset como el del owner estructural. El seed 019 incluía un bridge para ACCOUNTING_SUPERADMIN, no para el root confirmado de 036. Al quitar bypass legacy, 039 expone ese faltante.

La corrección prepara grants ORGANIZATION MICA explícitos en el preset resuelto desde `private.eco_platform_owner`, sin depender de email, nombre de rol ni membership artificial. No cambia los predicados de autorización ni la precedencia DENY. **La evidencia LIVE manual aportada confirma bridge_grants = NULL para el preset del root y cero scopes para ACCOUNTING_SUPERADMIN. No se infieren otros grants, contextos u overrides.**

## Contrato y matrices

`src/js/core/micaPermissionContract.js` contiene códigos, etiquetas castellanas, descripciones funcionales, grupos, scopes, asignabilidad, reserva OWNER, orden, visibilidad, presets por defecto y estado vigente/preparado/propuesto y runtimeStatus (ACTIVE / DISABLED_PENDING_BACKEND). También declara módulos, funciones compartidas, requisitos de importación, acciones operativas y capacidades OCR. La allowlist frontend, presets, presentación y editor se derivan de él. El servidor conserva la autoridad; una propuesta nunca concede acceso.

- [Matriz completa en castellano y presets × capability](039b_PERMISSION_MATRIX.md): PLATFORM/ORGANIZATION, seis perfiles y marcas grant/no grant.
- [Propuestas y compatibilidad](039b_PERMISSION_GAPS.md): bajas/restauración, manuales, fiscal, conciliación y funciones aprobadas con backend pendiente.
- [Plan end-to-end por perfil](039b_MANUAL_VALIDATION.md): aceptación posterior, no evidencia de ejecución.

Generación reproducible: `node scripts/generate039bContract.mjs`. Verificación sin escribir: `node scripts/generate039bContract.mjs --check`. Estos comandos sólo leen/escriben artefactos; nunca ejecutan SQL. No editar las tablas ni las listas de seed generadas a mano.

## Presets y alcance

Root: owner estructural + ACCESS_ANY_ORG + las capacidades ORGANIZATION MICA aprobadas de la matriz generada + capacidades PLATFORM del contrato. El UP completa grants delegables de plataforma; OWNER_RESERVED continúa en el registro exclusivo de 036.

Marianela: ACCOUNTING_SUPERADMIN, todas las capacidades ORGANIZATION por bridge y todas las PLATFORM_DELEGABLE del contrato. MICA_ADMIN_MANAGE habilita usuarios/presets/asignaciones sin GLOBAL_USER_MANAGE ni PLATFORM_MANAGE, reservados. ORGANIZATION_UPDATE permite editar organizaciones del alcance; creación/archivo siguen reservados en 036. Sin hard delete ni migraciones.

El UP provisiona scopes explícitos para titulares activos de ACCOUNTING_SUPERADMIN en todas las organizaciones activas del proyecto MICA. Triggers cubren altas, asignaciones y reactivación de organizaciones/presets. Un scope inactivo es una revocación deliberada: ON CONFLICT DO NOTHING no lo reactiva. No se crean memberships artificiales ni se reasignan usuarios por email.

Cuatro presets tenant reutilizables, sin asignación automática a usuarios: administrador de organización, contador/operador, operador de importaciones, consulta/auditor. El importador incluye revisión; el auditor incluye reportes/exportación/auditoría. Restauración queda fuera de nuevos presets tenant. Preset = base, no límite: ALLOW amplía y DENY restringe dentro del scope; nunca entregan OWNER_RESERVED.

Auditoría limitada al repo: 019 contiene templates históricos TENANT_ADMIN/ACCOUNTANT/UPLOADER/REVIEWER. Un rol legacy ADMIN no demuestra membership/grants. No se reutilizan templates HORECA; UP aborta si ACCOUNTING_SUPERADMIN es incompatible o tiene grants ajenos a MICA.

## UX, datos y paginación

Configuración: Organizaciones, Usuarios, Roles y permisos, Asignaciones; una sección visible, teclado y responsive. Tablas compactas, editores por selección y búsqueda de usuarios. Roles distingue Plataforma/Empresa, muestra etiquetas de negocio, códigos secundarios, descripciones, grupos, buscador, expandir/contraer y contador. Los VIEW compartidos se explican sin ofrecer toggles independientes que el servidor no puede hacer cumplir.

Asignaciones muestra preset/memberships/scopes/excepciones y estado efectivo calculado. Heredado/Permitido/Denegado/Efectivo describe el snapshot y el contexto activo del usuario seleccionado, no reemplaza al servidor. Presets desconocidos se marcan no calculados; Actualizar refresca cambios de otra sesión.

OCR está dentro de carga manual, sin módulo/menú propio. Manuales y OCR siguen inhabilitados hasta backend real. Importación fiscal cerrada; los otros tres importadores requieren RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + capability específica. Clasificación, baja y exportación existentes tienen guards frontend concretos.

Comprobantes/percepciones/bancos: default 50, opciones 25/50/100, anterior/siguiente, página/total. Filtro y orden preceden a paginación; cambios de filtro vuelven a página 1. Totales reflejan el conjunto filtrado; cambiar página limpia selección. Cambiar tenant limpia datos y estado; clasificación conserva IDs.

**Límite técnico:** readers 037 devuelven SETOF JSONB con cursor UUID/límite, sin filtros funcionales ni total filtrado. Paginar esos fragmentos como resultados filtrados rompería búsquedas/totales. Se conserva paginación cliente. La app carga por demanda/familia: Configuración/catálogos no descargan movimientos; bancos/sueldos no descargan comprobantes, y viceversa. Caché sólo dentro del contexto, sin páginas adicionales ni publicación tardía tras cambiar tenant. Cada familia solicitada todavía se descarga completa: **no es paginación remota ni descarga máxima de 50 filas**. Un reader filtrado con conteo es el requisito pendiente para reducir ese volumen manteniendo resultados.

## SQL, pruebas y diff

UP/DOWN principal: `sql/039b_operational_access_and_ux*.sql`, con hashes de nueve funciones previas, grants/presets/scopes, administración delegable, IMPORT_VIEW y restauración exclusiva de plataforma MICA. Ambos RPC exigen DATA_RESTORE_ANY_ORG, alcance, contexto confirmado, organización activa, RECORD_VIEW y RECORD_RESTORE efectivos. El permiso contextual histórico de un tenant ya no basta; DENY prevalece.

Las once capabilities aprobadas se incorporan al UP principal. El editor permite asignarlas y muestra backend pendiente. Ninguna habilita operaciones inexistentes. Se retiró la propuesta manual aislada. [Disponibilidad exacta generada](039b_RUNTIME_STATUS.md).

[Preflight read-only](../sql/039b_preflight_live_readonly.sql) preparado, no ejecutado. El manifest `sql/039b_live_adoption_manifest.json` espera ausencia con null; cualquier colisión aborta hasta cotejar e incorporar el snapshot LIVE exacto. No se duplican UUID ni se copian grants de HORECA. [Procedimiento de adopción](039b_PERMISSION_GAPS.md).

DOWN verifica drift y revierte filas propias intactas; no borra datos operativos ni capabilities adoptadas ni usa CASCADE. Restaura las nueve definiciones previas, incluyendo el contrato anterior de restore.

DB preparado: `tests/db/039b_operational_access_and_ux.sql`, transacción con ROLLBACK **no ejecutada**. Incluye filas aisladas y ambos RPC reales: root/MICA restauran, tenant histórico no, DENY plataforma/contextual, scope revocado, organización inactiva, contexto nulo y aislamiento entre organizaciones. JS/UI prueba contrato, presets, componentes DOM, paginación y carga por demanda con servicios simulados; no equivale a RLS/navegador LIVE.

98 archivos SQL del baseline intactos por SHA-256, incluidas 036/037/037a/038/039. Los nueve hashes del UP coinciden exactamente con los body_md5 LIVE aportados; no se modificaron. Los harness históricos mantienen sus contratos; 039b añade IMPORT_VIEW y presets nuevos.

`docs/039b_REVIEW.diff` reúne los archivos de la fase contra HEAD y los nuevos artefactos, incluyendo el borrador previo completado. Excluye archivos ajenos; no aplicar ciegamente sobre otro baseline. No se declara DEV_RUNTIME_VERIFIED ni CLOSED. Resultado de pruebas locales al final de este documento.

## Resultado local

`STATICALLY_VERIFIED` / `READY_FOR_MANUAL_CHECK`: **43 suites, 545 pruebas aprobadas** con `node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --silent`. Log: `scratch/039b-live-closure-jest.log`. Se verifican también sintaxis JS con `node --check`, `git diff --check` y `node scripts/generate039bContract.mjs --check`.

Sin test SQL ejecutado ni navegador LIVE. El resultado local no se presenta como validación end-to-end de producción.

Estado de entrega: **039b LISTA PARA APLICAR**. El preflight y el harness permanecen preparados, sin ejecutar.

## Cotejo con evidencia LIVE manual — 2026-09-30

Fuente: evidencia aportada por el usuario desde Supabase SQL Editor, proyecto `ourzapkjykzlwsjunzmd`. No se ejecutó SQL. Los siete snapshots ya eran exactos y se conservaron; las seis ausencias se mantienen como null. Artefactos regenerados.

- Creará seis capabilities: `DATA_RESTORE_ANY_ORG`, `MICA_ADMIN_MANAGE`, `MANUAL_MOVEMENT_VIEW`, `MANUAL_MOVEMENT_CREATE`, `MANUAL_MOVEMENT_EDIT`, `MANUAL_MOVEMENT_SOFT_DELETE`.
- Adoptará siete capabilities sin cambiar UUID, metadata ni grants históricos: `INTEGRATIONS_CONFIG_MANAGE`, `INTEGRATIONS_SYNC_TRIGGER`, `PERSONNEL_EMPLOYEES_MANAGE`, `PURCHASES_INVOICES_MANAGE`, `SALES_VIEW`, `SUPPLIERS_MANAGE`, `SUPPLIERS_VIEW`.
- Root: agregará 44 grants ORGANIZATION al bridge actualmente vacío. Completará sólo los grants PLATFORM delegables faltantes de la lista siguiente; la evidencia no permite contar esos faltantes. OWNER_RESERVED no se altera.
- ACCOUNTING_SUPERADMIN: completará el bridge hasta las 44 capabilities ORGANIZATION MICA y los 11 grants PLATFORM siguientes, con ON CONFLICT DO NOTHING. RECORD_RESTORE ya existe en su bridge y se conserva. No se conoce el número exacto de los demás grants faltantes.
- PLATFORM delegables para ambos presets: `DATA_RESTORE_ANY_ORG`, `MICA_ADMIN_MANAGE`, `ORGANIZATION_UPDATE`, `GLOBAL_CATALOG_VIEW`, `GLOBAL_CATALOG_MANAGE`, `CATALOG_ASSIGN_ANY_ORG`, `RATE_MANAGE_ANY_ORG`, `REPORT_COMPARE_SCOPED_ORGS`, `REPORT_CONSOLIDATED_SCOPED_ORGS`, `SAAS_ANALYTICS_VIEW`, `AUDIT_PLATFORM_VIEW`.
- Scopes: provisionará pares de cada titular activo del preset ACCOUNTING_SUPERADMIN con cada organización activa. La evidencia identifica al destinatario `f922be9a-449d-417f-8003-2143fcbeef02` con cero scopes; no informa cantidad de organizaciones activas, por lo que no se inventa un total. Triggers cubren altas y reactivaciones; scopes existentes inactivos se preservan.
- Los grants de templates históricos y el grant RECORD_RESTORE de OWNER se preservan. No se convierten esos templates en presets MICA.

Funciones que reemplazará (expected = LIVE en las nueve):

| Función | body_md5 |
|---|---|
| `public.mica_admin_apply(text,jsonb)` | `14ea590d5f6c276b1e094da9fcc69021` |
| `public.mica_admin_read(uuid,text)` | `d097bf71b410c3f5daa45a449cbd6e32` |
| `private.admin_038_authorize(uuid,text,text)` | `97b909ec8fe5ec13fd6710b0fb8e6520` |
| `private.admin_038_cap(text,text,uuid)` | `7cdf262ee4799662e5875c69686aa920` |
| `private.admin_038_target(uuid)` | `80359e81c6a37691e95a3c9400a1278e` |
| `private.mica_capability_allowed(text,text)` | `aae7df3af4b1674a42f22495097030e7` |
| `private.require_039_import(text,text)` | `4997ae332c276418b0a2df735b822298` |
| `public.restore_financial_movement(uuid)` | `55216b62904f97af171f78c3147a490a` |
| `public.restore_normalized_record(uuid)` | `64134c70e927d1c20119a62a447d20a8` |

Seguridad declarada en evidencia: owner postgres, SECURITY DEFINER, search_path vacío. ACL privadas: sólo postgres; públicas: postgres y authenticated. CREATE OR REPLACE conserva owner/ACL. No se requieren nuevamente las definiciones completas para cotejar el contrato de hashes.

SHA-256 036–039 cotejados con el baseline, además de los 98 archivos históricos:

| Archivo | SHA-256 |
|---|---|
| `sql/036_owner_core_and_delegation_guard.sql` | `6fba0e969a90152dc5511670f82c63c34a8ff195626f0a244437e6513faf8d3f` |
| `sql/036_owner_core_and_delegation_guard_down.sql` | `9a28ea8c9b5efecc0b1de14f7664c8250d973157a6b2d7f06ffba83ec4436007` |
| `sql/037a_fix_guard_036_grant.sql` | `7d4d76ca695b513b473b9d58d2b9f9121cf2be60c7191ab2115f52d829b252fc` |
| `sql/037a_fix_guard_036_grant_down.sql` | `c18a0d4a4836b4dc4c885fe5f1df7516f3e411b31b655803d9c716b0d24a0786` |
| `sql/037_platform_tenant_operation.sql` | `1e0cb142d4265ead083e2c9ada934aa02c5d8e618b20acf99022aee14bee8273` |
| `sql/037_platform_tenant_operation_down.sql` | `8dba6697778aeb5eff05e6dcf54f388f9b9c0628aade34133aa93db710852856` |
| `sql/038_mica_administration.sql` | `57536b44148b2bb4ce9405ba4cbe3216eed7c2f450898b811cc726a5b2bbdf77` |
| `sql/038_mica_administration_down.sql` | `95d921e93a7736143310924324199da94d6d1e1dbaa3efb950172c452845eac7` |
| `sql/039_module_and_import_capabilities.sql` | `50d57ca58fc60628c1b9d32f043d641268276819af808f7207ae5e71044b5eba` |
| `sql/039_module_and_import_capabilities_down.sql` | `a357ce56cedadf31d92a78e98fdfb7a1ec45b62bebd6b4fae2e7d5efdeb91e34` |
| `sql/039_preflight_readonly.sql` | `369c4013fa7ffb332b78dc27c1b08d5e918642d532fb62d27ee07bfe42c7c09b` |

Harness DB posterior: `tests/db/039b_operational_access_and_ux.sql`, para ejecutar manualmente después del UP en el proyecto indicado. Usa fixtures aislados y ROLLBACK; verifica importación, delegación, restauración por ambos RPC, DENY, alcance y aislamiento. Sigue sin ejecutar. Estado local: STATICALLY_VERIFIED / READY_FOR_MANUAL_CHECK; no DEV_RUNTIME_VERIFIED ni CLOSED.
