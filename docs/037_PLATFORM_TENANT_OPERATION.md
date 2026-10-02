# 037 — Operación tenant desde plataforma

036 está aplicada y validada LIVE por el usuario: identidad estructural, once OWNER_RESERVED, ausencia de grants/overrides reservados y ACL de metadata confirmadas. 037 está IMPLEMENTED / STATICALLY_VERIFIED, pendiente de aplicación y harness manual. No se ejecutó SQL, commit, push ni deploy. HORECA permanece congelado en backlog, sin cambios de datos ni auditoría adicional.

## Diseño mínimo

La autoridad tiene tres condiciones independientes: organización activa dentro del alcance, contexto confirmado del servidor y permiso ORGANIZATION concreto. ACCESS_ANY_ORG sólo resuelve la primera condición para el root técnico estructural; no concede acciones ni equivale al owner funcional Marianela.

| Actor | Alcance | Acción |
| --- | --- | --- |
| Root técnico activo | Cualquier organización activa mediante ACCESS_ANY_ORG | Grant ORGANIZATION explícito o ALLOW del destino, sin DENY |
| Plataforma no-root activa | Fila activa perfil/organización en private.eco_platform_org_scopes | Bridge explícito de su template o ALLOW del destino, sin DENY |
| Tenant con membership activo | Su membership | can_org existente, sin bypass del DENY aplicable |
| Plataforma/null, otro contexto, org/perfil/capability inactivos | No habilita operación tenant | false |

`private.can_operate_mica_org(uuid,text)` comprueba una fila de `eco_user_active_context` para el caller, nunca una organización enviada libremente ni un fallback de profile. Filtra por contrato MICA/OCR, existencia, actividad y scope ORGANIZATION. Primero aplica los DENY de membership activo y de override de plataforma aplicable; después evalúa la ruta membership existente o la ruta plataforma. Un ALLOW de plataforma no sirve sin alcance. Revocar el platform role o el alcance invalida esa ruta aunque el contexto siga almacenado. Una membership legítima puede seguir autorizando por su propia ruta.

`can_org`, `can_platform`, policies RLS generales y memberships no se modifican. La tabla legacy GRANT/REVOKE no se integra en el nuevo resolver; sigue fuera de la autoridad canónica.

## Objetos y contratos

- `private.eco_platform_org_scopes`: PK perfil/organización, actividad y fecha de creación.
- `private.eco_platform_org_overrides`: PK perfil/organización/capability, effect ALLOW/DENY y fecha. El trigger permite sólo capabilities ORGANIZATION activas del contrato aprobado.
- `private.platform_org_in_scope(uuid)`: alcance independiente de acciones y del contexto seleccionado.
- `private.has_mica_platform_role()`: asignación y template PLATFORM activos; sin comparar strings de roles legacy.
- `private.mica_capability_allowed(text,text)`: contrato cerrado por código/scope, sin otorgar permisos.
- `public.can_operate_mica_org(uuid,text)`: consulta booleana del propio caller; EXECUTE sólo authenticated. Toda nueva RPC tenant de 038–040 debe comprobar el helper privado antes de operar, no confiar en una comprobación JS previa.

Las tablas nuevas están vacías, con RLS y sin acceso de navegador. No se conceden bridges, overrides ni scopes automáticamente. Su administración autorizada y auditada corresponde a 038; 037 no expone un CRUD ni crea memberships artificiales.

## Integración necesaria ahora

Se reemplazan nueve funciones, conservando firma y ACL:

1. `list_operational_org_targets()`: lista alcance efectivo de plataforma; deja de ser exclusiva del root.
2. `switch_superadmin_org_context(uuid) -> void`: conserva nombre por compatibilidad, acepta plataforma con alcance explícito, valida destino activo, serializa por perfil y mantiene evento de auditoría SUPERADMIN_ORG_CONTEXT_SWITCHED. NULL retorna a Plataforma. Un rechazo no publica el destino.
3. `get_my_operational_context()`: acepta alcance plataforma sin membership, conserva perfil efectivo real y agrega `can_switch_platform_context`.
4. `get_my_effective_capabilities(uuid)`: filtra códigos MICA y resuelve acciones con el helper nuevo, sólo para el contexto confirmado.
5. `get_operational_snapshot(uuid)`: ORG_VIEW para categorías/actividades y CATALOG_ORG_VIEW para tasas, sin bypass ACCESS_ANY_ORG.
6. `get_operational_records_page(uuid,uuid,integer)`: RECORD_VIEW concreto.
7. `get_operational_financials_page(uuid,uuid,integer)`: RECORD_VIEW concreto, manteniendo el contrato previo de lectura financiera. Separación por datos bancarios/salariales queda para el contrato de 039; no se declara implementada aquí.
8. `private.catalog_activation_org(text)`: usa contexto confirmado y permiso de acción concreto para las RPCs de activación existentes.
9. `get_capability_delegation_contract()`: conserva ocultamiento del núcleo reservado para no-root y filtra metadata al contrato MICA/OCR.

El frontend usa el indicador confirmado para el selector, conserva el protocolo server-first, el tab actual y la limpieza de datasets. La respuesta de permisos se filtra también en el servicio JS. El flag sólo habilita navegación visual: el servidor revalida cada operación. La compatibilidad con ACCESS_ANY_ORG permite conservar clientes/fixtures previos.

El contrato local contiene 20 códigos PLATFORM y 33 ORGANIZATION, incluidos DOCUMENTS_UPLOAD, DOCUMENTS_OCR_PROCESS, DOCUMENTS_OCR_VERIFY, FINANCIAL_ALLOCATION_EDIT y las dos lecturas sensibles aprobadas. No importa automáticamente todo eco_capabilities ni usa prefijos abiertos. Para FINANCIAL_RECONCILIATION_* no se inventan sufijos: los códigos exactos aprobados deberán incorporarse al contrato cuando se conecte ese módulo. Tampoco se crean capabilities ausentes. El preflight aborta si un código existente tiene un scope distinto del esperado.

## Límites explícitos para 038–039

037 prepara y conecta el contrato, no todos los writers heredados. Importadores, CRUD administrativo de 022 y otras RPCs que todavía usan can_org conservan sus restricciones previas. No se amplía RLS indiscriminadamente para resolverlos. 038/039 deberán conectar sus operaciones concretas al nuevo helper y probarlas en DB.

El bloqueo especial de importadores por ACCESS_ANY_ORG se conserva hasta 039, como pide la secuencia. OCR/manuales permanecen sin persistencia nueva. No se promete aún el end-to-end de creación de organizaciones/usuarios/roles/importadores; requiere las siguientes fases.

Consecuencia intencional: si el root no tiene bridges/overrides ORGANIZATION, seguirá viendo organizaciones seleccionables pero los readers adaptados devolverán arrays vacíos. 038 permitirá provisionar esos permisos; ser root no implica recibirlos.

## Preflight y rollback

Antes del primer CREATE, 037 exige 036 presente, identidad root coherente, objetos nuevos ausentes, tipos de columnas consumidas, scopes de códigos aprobados y cuerpos/owner/search_path de las nueve funciones conforme a las definiciones revisadas del repo. Los hashes normalizan CR y whitespace exterior, no diferencias internas. El ejecutor debe ser propietario de las funciones reemplazadas. Si una definición LIVE difiere, aborta para revisión; esta implementación no consultó ni ejecutó SQL LIVE.

Se captura `pg_get_functiondef`, owner y ACL exactos en `private.migration_037_functions`; al terminar se captura también la definición instalada. El down restaura exactamente lo capturado y retira únicamente objetos 037, en orden, sin CASCADE. Aborta si hubo cambios posteriores de definición/owner/ACL o existen filas nuevas en scopes/overrides: no elimina datos de administración creados después. Tampoco debe ejecutarse después de fases dependientes sin revertirlas antes. La ACL original se conserva durante CREATE OR REPLACE y se verifica en rollback, incluido NULL/default ACL.

El down vuelve también al comportamiento anterior de los readers de 035; es recuperación técnica, no una forma de conservar las garantías de 037 sin el nuevo contrato. Revertir el frontend junto con el SQL es necesario para restaurar toda la versión anterior.

## Validación

- SQL completo: `sql/037_platform_tenant_operation.sql` y `_down.sql`.
- Harness SQL Editor: `tests/db/037_platform_tenant_operation.sql`, BEGIN y ROLLBACK final, JWT simulado y assertions públicas bajo authenticated. No ejecutado. Requiere los perfiles root/contadora y organizaciones NORTE/SUR confirmados, más una membership preexistente de contadora en NORTE para ejercitar el conflicto entre rutas. Su ausencia aborta con mensaje explícito; no se inventa una membership para habilitar la operación de plataforma. Todos los cambios de fixtures se revierten.
- Jest estático: `tests/services/platformTenant037.test.js`, contrato SQL/JS, precedencia DENY, ACL/rollback y SHA-256 de 16 archivos SQL 031–036, incluido 035a.
- Test JS de contexto: plataforma no-root sin ACCESS_ANY_ORG cambia de organización, conserva datos previos ante rechazo, limpia al volver a Plataforma y descarta permisos ajenos al producto.
- Jest completo: 36 suites / 450 tests pasan. Esto no acredita ejecución del SQL ni del harness DB.

Revisión manual pendiente: revisar los nueve reemplazos y su baseline; aplicar 037 cuando se autorice; ejecutar el harness completo en DEV y exigir NOTICE final/ROLLBACK; después provisionar permisos mediante 038 y validar importadores en 039. Ninguna de esas operaciones fue ejecutada por el agente.
