# 039g revisada — Administración operativa MICA

Estado: preparada y verificada con tests locales. **No aplicada ni validada en PostgreSQL/LIVE.** Proyecto exclusivo: `ourzapkjykzlwsjunzmd`.

## Entrega y orden

Hotfix de propagación: `ORG_MEMBER_PRESET_ASSIGN` se copia desde grants directos únicamente a templates `ORGANIZATION`, y desde bridges únicamente a templates `PLATFORM`. El preflight clasifica los destinatarios históricos y aborta ante combinaciones no contempladas. `OWNER` y todos los templates con scope NULL quedan excluidos; sus filas y grants se capturan para verificar que no cambien. `guard_036_grant` permanece activo. El harness de ida y vuelta comprueba también la conservación de esos snapshots tras DOWN. Estas comprobaciones SQL están preparadas, no ejecutadas.

Se conserva 039g para la reclasificación de `ORGANIZATION_CREATE` y se agrega 039h para el nuevo perfil operativo. Ambas partes integran esta revisión; 039g sola no cumple el nuevo alcance de Marianela.

| Parte | UP | DOWN | Preflight | Harness preparado |
|---|---|---|---|---|
| 039g | `sql/039g_delegate_organization_create.sql` | `sql/039g_delegate_organization_create_down.sql` | `sql/039g_preflight_readonly.sql` | `tests/db/039g_delegate_organization_create.sql` |
| 039h | `sql/039h_operational_administration.sql` | `sql/039h_operational_administration_down.sql` | `sql/039h_preflight_readonly.sql` | `tests/db/039h_operational_administration.sql` |

Preflight humano primero, sin aplicar migraciones todavía. El preflight identifica a `drcmarianela@gmail.com`, devuelve todas sus organizaciones activas/scopes, overrides y el snapshot exacto de perfil/asignación. También comprueba la identidad estructural solicitada para `vegendigital@gmail.com`. **Los scopes LIVE no están confirmados en esta entrega.**

El manifiesto `sql/039h_live_target_manifest.json` contiene el snapshot aportado del UUID `f922be9a-449d-417f-8003-2143fcbeef02`. La migración aborta si falta ese snapshot o si el estado difiere. Para regenerar tras un preflight revisado: **localmente, sin SQL** `node scripts/generate039hOperational.mjs`. No sustituirlo por búsquedas de email dentro de la migración.

Con preflight revisado y autorización de ejecución futura, usar `sql/039g_revised_release.sql`: combina ambos UP en una única transacción, de modo que un rechazo de 039h también revierte 039g. No ejecutar además los UP individuales. Después: harness 039h → frontend. Para volver atrás: DOWN 039h → DOWN 039g y restaurar el frontend correspondiente. Los DOWN abortan ante cambios posteriores en funciones, asignaciones, grants o nuevas referencias. No borran empresas, usuarios ni scopes creados durante la operación. El rollback de 039h devuelve a Marianela su preset anterior y, por tanto, sus facultades anteriores; debe revisarse como tal.

## Perfil operativo

`ADMINISTRACION_OPERATIVA_MICA` es un preset nuevo. Se reasigna únicamente el UUID revisado y después se desactiva `ACCOUNTING_SUPERADMIN`, sin eliminarlo ni cambiar sus grants históricos. El preflight y el control posterior abortan si queda otro destinatario activo, incluyendo memberships. No hay autorización por email ni por nombre del preset en los evaluadores.

El preflight LIVE informado por el usuario confirmó que Marianela es su único destinatario activo y que el nuevo preset aún no existe. El agente no ejecutó SQL para obtener esa evidencia. El preset deprecado queda excluido de los controles normales, incluso ante una respuesta antigua que lo marque activo; el RPC rechaza nuevas asignaciones y su reactivación/edición. El DOWN compara el snapshot instalado, restaura primero el estado activo anterior y luego la asignación exacta. Sus grants y bridge deben permanecer idénticos o el rollback aborta. El DOWN de 039g posterior retira únicamente sus grants añadidos, recuperando el estado anterior al release completo.

Sus nueve permisos de plataforma son: crear/editar organizaciones, ver/gestionar catálogos generales, asignar catálogos, gestionar tasas, restaurar datos autorizados, comparar y consolidar organizaciones dentro del alcance. No incluye `MICA_ADMIN_MANAGE`, auditoría de plataforma, métricas SaaS ni capacidades estructurales. `ORGANIZATION_ARCHIVE` sigue reservada.

El bridge incluye el catálogo organizacional aprobado para operación y `ORG_MEMBER_PRESET_ASSIGN`; excluye `ORG_MEMBER_PERMISSION_MANAGE`. Los endpoints siguen comprobando permiso efectivo y contexto. Se mantiene `DENY > ALLOW > base > denegado`.

Los scopes existentes se conservan exactamente. El nuevo preset se registra en el mecanismo existente que inserta scopes explícitos para empresas nuevas; no usa `ACCESS_ANY_ORG`, no crea memberships artificiales ni reactiva scopes revocados. El UP aborta si al objetivo le faltan scopes activos sobre empresas activas.

### Normalización de memberships históricas

La revisión LIVE informada por el usuario identificó tres memberships CONSULTANT activas en DEMO NORTE/OESTE/SUR. `sql/039h_reviewed_memberships.json` fija sus IDs, organizaciones, preset y estado revisados; los UUID de las organizaciones coinciden con los contratos históricos 020/035a. El manifiesto del perfil/asignación de Marianela permanece byte por byte intacto.

El preflight admite exactamente esas tres asociaciones y rechaza filas adicionales, cambios de organización/preset/estado y cualquier override asociado, incluyendo la tabla legacy. Exige siete scopes explícitos activos. `private.migration_039h_state` captura con `to_jsonb` todas las columnas de las memberships antes y después de la normalización. Antes de reasignar el preset de plataforma, sólo pone `is_active=false`; no borra las filas ni modifica sus presets CONSULTANT. Comprueba cero memberships activas y la igualdad exacta de todos los scopes.

El DOWN rechaza drift de las filas instaladas y overrides posteriores. Restaura las filas existentes completas desde el snapshot, con sus flags y metadatos originales; no inserta memberships ni scopes y aborta si la restauración exacta falla. Las protecciones de root, la deprecación/restauración de ACCOUNTING_SUPERADMIN y los grants anteriores conservan sus controles.

`tests/db/039h_membership_roundtrip.sql` es el harness adicional **preparado, no ejecutado** para correr antes del release: toma el estado mixto revisado como fixture BEFORE, ejecuta los UP reales, verifica operación por scope en las siete empresas, ejecuta los DOWN reales y compara memberships/scopes/asignación/preset/grants/funciones con sus snapshots iniciales. Las operaciones de prueba se revierten mediante savepoint antes de probar el DOWN; termina con ROLLBACK de toda la transacción. No sustituye una ejecución PostgreSQL efectiva ni afirma validación LIVE.

## Usuarios de empresa

Asignar un perfil existente requiere `ORG_MEMBER_PRESET_ASSIGN` y `ORG_MEMBER_MANAGE`; incorporar un nuevo miembro requiere además `ORG_MEMBER_INVITE`. Sigue prohibido delegar facultades superiores a las propias. Por eso los perfiles con administración de permisos no se ofrecen al operador. Los gestores anteriores que ya tenían grants base de administración de permisos reciben el nuevo permiso de asignación para conservar esa función; se excluye el preset deprecado para preservar sus grants exactos. No se copian overrides individuales.

La invitación es una preautorización, sin envío de email: el usuario se registra y confirma su dirección. Después se confirma su asignación y se activa inicialmente mediante `tenant_activate`, limitado a una cuenta pendiente, confirmada, invitada y asignada únicamente a esa empresa, sin rol de plataforma. No permite reactivar cuentas globales suspendidas. Los cambios posteriores de estado afectan a la membresía de la empresa; no al perfil global.

Crear/editar presets, overrides, roles y scopes de plataforma conservan controles independientes que el perfil operativo no satisface.

## Root y frontend

Root conserva `VEGEN_PLATFORM_ADMIN`, el registro estructural y las protecciones 036. Los RPC rechazan objetivos root y edición de sus presets; los triggers protegen perfil, rol, registro owner y capacidades reservadas. 039h no modifica esos evaluadores ni triggers y compara el estado root antes/después. 039g suspende únicamente los dos guards necesarios para reclasificar la capacidad, bajo bloqueo exclusivo y transacción, y los restaura antes de terminar.

La configuración operativa presenta Empresas como sección inicial, Usuarios de empresas con selector, Categorías y actividades e Impuestos. Los formularios de empresa editan nombre, razón social, nombre comercial y CUIT; no presentan archivado. Catálogos e impuestos abren la pantalla operativa existente. Se ocultan las herramientas estructurales. Root mantiene su configuración completa. Los permisos efectivos separan plataforma/organización y solicitan seleccionar empresa en contexto plataforma.

## Evidencia y límites

Los tests locales verifican contrato, restricciones, interfaz y preservación de SQL histórico. Los harness SQL están preparados, **no ejecutados**. El de 039h usa el UUID revisado real y revierte su transacción: creación/edición de empresa, scope nuevo, seis importadores, invitación/asignación/cambio/desactivación tenant, rechazos de operaciones estructurales, DENY y conservación del root.

El perfil concede permisos aprobados; no implementa backends ausentes. OCR, proveedores/compras/personal/integraciones y reportes comparativos/consolidados conservan sus estados pendientes donde el contrato existente así lo indica. La clasificación/imputación disponible no equivale a incorporar un nuevo módulo de conciliación; sus propuestas siguen sin concederse. Esta fase no puede certificarse como disponibilidad runtime de esas funciones.

Comprobaciones de aceptación posteriores, agrupadas:

1. Preflight: UUID/asignación revisados, root estructural correcto, scopes activos completos, hashes coincidentes y ausencia de overrides incompatibles.
2. Harness 039h tras UP: termina sin excepción y hace ROLLBACK de sus fixtures.
3. Marianela: crear empresa, editar sus cuatro datos, seleccionar la nueva empresa y cargar un import autorizado.
4. Usuarios de empresa: invitar/confirmar/activar, cambiar perfil y desactivar membresía; ninguna herramienta de permisos estructurales visible.
5. Root: configuración completa, facultades reservadas y protección contra cambios por el operador.

No se ejecutó SQL. No hubo commit, push ni deploy. No se tocó HORECA.
