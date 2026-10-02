# 035 — revisión previa a aplicación

Estado: IMPLEMENTED / STATICALLY_VERIFIED. No se ejecutó SQL (ni up, ni down, ni tests DB).
La definición LIVE del switch fue confirmada por el usuario; esta revisión no consultó LIVE.

## Decisión y evidencia de autoridad

| Dataset | Autoridad tenant aplicada por 035 | Evidencia repo |
| --- | --- | --- |
| Comprobantes/percepciones | `RECORD_VIEW` | `docs/MICA_AUTHORIZATION_DEPENDENCY_MATRIX.md`, DEP-RLS-005; capability en `sql/019_capability_foundation.sql` y `023` |
| Bancos/sueldos | `RECORD_VIEW` | Misma matriz, DEP-RLS-009. `BANK_IMPORT` / `PAYROLL_IMPORT` son permisos de importación, no lectura |
| Categorías/actividades asignadas | `ORG_VIEW` | Policies `Org categories viewable by org` / `Org activities viewable by org` en `sql/033_catalog_capability_core.sql` |
| Tasas IIBB | `CATALOG_ORG_VIEW` | Matriz DEP-RLS-014. `033` no reemplaza la policy de tasas. No se usa `ORG_VIEW` ni el permiso de escritura `RATE_MANAGE_ANY_ORG` como permiso de lectura |

La matriz antigua también proponía `CATALOG_ORG_VIEW` para categorías/actividades; las policies
ejecutables posteriores de 033 usan `ORG_VIEW`, y prevalecen para esos dos datasets.
Para tasas, el repo aún contiene el reader legado de 014 y la policy de 017 basados en
`private.org_id()` / rol legado; la matriz documenta el permiso objetivo. **No se afirma que
el reader legado ya aplique `CATALOG_ORG_VIEW` en LIVE.** 035 lo exige explícitamente.

En todos los datasets se permite lectura al owner con `ACCESS_ANY_ORG`, sólo cuando el UUID
solicitado coincide con `private.active_org_id()` y la organización está activa. Se exige
`auth.uid()` y perfil activo. No se cambian `can_org()` ni `can_platform()`. Sin permiso del
dataset se devuelve un conjunto vacío; un contexto inválido produce error 42501.

Los readers `get_active_normalized_records()` / `get_active_financial_movements()` de 014
devuelven `SETOF` de la tabla completa, usan `private.org_id()` y no reciben el contexto esperado.
Reutilizarlos trasladaría la exposición de columnas y el contexto implícito a otra RPC.
Por eso se añaden sólo dos readers explícitos; los readers legados no se modifican ni se
declaran endurecidos por esta migración.

## Contratos de datos exactos

`get_operational_snapshot(p_org_id uuid) -> jsonb` devuelve estas cuatro claves:

- `organization_id`.
- `categories[]`: `id`, `org_assignment_id`, `organization_id`, `name`, `description`,
  `category_type`, `is_active`, `is_assigned`.
- `activities[]`: `id`, `organization_id`, `name`, `arca_code`, `description`, `is_active`, `is_assigned`.
- `rates[]`: `id`, `organization_id`, `activity_id`, `jurisdiction`, `rate`, `valid_from`, `valid_to`, `is_active`.

Los históricos desaparecen completamente de ese JSON. Los catálogos asignados incluyen las
asignaciones activas e inactivas, y las tasas sólo las activas, como antes.

`get_operational_records_page(p_org_id uuid, p_after_id uuid DEFAULT NULL,
p_limit integer DEFAULT 500) -> SETOF jsonb`:

- Claves de fila: `id`, `organization_id`, `record_type`, `tipo_operacion`, `fecha`, `cuit`,
  `razon_social`, `comprobante`, `total`, `categoria`, `confirmada`, `normalized_payload`.
- Claves permitidas de `normalized_payload`: `fecha`, `cuit`, `razonSocial`, `tipo_cbte`, `pdv`,
  `nroDesde`, `nroHasta`, `moneda`, `tipoCambio`, `total`, `totalIva`, `otrosTributos`, `exento`,
  `netoNoGravado`, `netoGravado`, `alicuotas`, `period`, `periodo`, `regimen`, `sucursal`,
  `comprobante`, `monto`, `amount`, `jurisdiction`, `fuente`.

Evidencia de consumo: `loadActiveFiscalRecords(rows)` y `loadActivePerceptions(rows)` en
`src/js/core/services/persistenceService.js`. El período se obtiene del payload; no se inventa
una columna `eco_normalized_records.periodo` que las migraciones del repo no definen.
`alicuotas` conserva su valor JSON utilizado por el mapeo fiscal; el resto de claves del payload
no se expone por propagación automática.

`get_operational_financials_page(p_org_id uuid, p_after_id uuid DEFAULT NULL,
p_limit integer DEFAULT 500) -> SETOF jsonb`:

- Claves de fila: `id`, `organization_id`, `operation_type`, `fecha`, `periodo`, `normalized_payload`.
- Claves permitidas de `normalized_payload`: `fecha`, `fechaValor`, `periodo`, `descripcion`,
  `tipo`, `monto`, `cuentaSugerida`, `confirmada`, `sueldoBruto`, `sueldoBrutoCalculado`,
  `remunerativo`, `noRemunerativo`, `anticipos`, `anticipoSueldo`, `sindicatoAporte`,
  `aporteSindicalCalculado`, `aporteSindicalObligatorio`, `sueldoNeto`, `sacProporcional`,
  `faecys`, `costoLaboralReal`, `concepto`, `amount`, `categoria`, `category_id`.

Evidencia: separación BANCO/SUELDO y normalización en `loadOperationalSnapshot`, consumos de
`renderBancos`, `renderSueldos`, `renderClientDashboard` y `updateSalaryFormFields` en `ui.js`,
y clasificación/exportación de bancos en `store.js`. El mapper financiero legado reconoce más
columnas, pero este flujo no consume sus fingerprints, IDs de importación, autoría ni metadatos
de auditoría: quedan fuera del reader nuevo. Los nulos de los payloads se omiten para mantener
los fallbacks existentes (p.ej. `costoLaboralReal !== undefined`).

## Carga acotada y cambios frontend

Cada reader excluye borrados, ordena por la PK UUID y usa `id > p_after_id`, con límite validado
entre 1 y 500. No agrega históricos en JSON, no introduce tablas/índices de paginación ni modifica
los readers anteriores. `p_org_id` nunca es una autorización por sí mismo.

`persistenceService.loadOperationalSnapshot()` conserva su contrato JS para el store, pero
ahora orquesta el snapshot pequeño y los dos readers. `loadOperationalPages()` continúa hasta
una página vacía, incluso si el límite de PostgREST entrega menos de 500 filas; valida organización,
tamaño y progreso del cursor. Después ordena los históricos por fecha descendente, separa bancos
y todos los períodos de sueldos, y devuelve el resultado temporal completo. Cualquier error aborta
la publicación. El store comprueba nuevamente el contexto antes de publicar los arrays.
`refreshOperationalCatalogs()` solicita `catalogOnly: true` y no descarga históricos.

Límite deliberado: se acota cada respuesta, pero el frontend conserva todos los registros en memoria,
como las grillas actuales. Las páginas son lecturas independientes; modificaciones concurrentes
dentro del mismo tenant pueden aparecer en una recarga posterior. No se promete un snapshot MVCC
entre peticiones ni coordinación multitab. Se conservan las defensas contra mezclar organizaciones.

## Preflight y rollback

Antes de cualquier `CREATE/REPLACE FUNCTION`, el preflight valida firmas/tipos de helpers,
UUID -> VOID / SECURITY DEFINER / search_path vacío del switch, columnas y tipos realmente usados,
claves únicas no diferibles, FKs de identidad/asignación, trigger append-only del audit,
NULL permitido para Plataforma y ausencia de columnas obligatorias desconocidas en los inserts.
Rechaza una reaplicación o RPC nueva preexistente: así el down sabe exactamente cuáles puede borrar.
No ejecuta DML de prueba contra tenants ni pretende predecir triggers personalizados ajenos al contrato.

035 captura `pg_get_functiondef`, propietario y ACL efectiva (rol, otorgante, EXECUTE, grant option)
en `private.migration_035_backup`, sin acceso para PUBLIC/anon/authenticated. El down restaura ese
cuerpo LIVE exacto —incluidos SUPPORT_IMPERSONATE OR ACCESS_ANY_ORG, comprobación de existencia,
update del perfil, upsert del contexto y auditoría— y reconstruye/verifica la ACL capturada.
No se sustituye por una aproximación de 022. La representación NULL/default de la ACL puede volverse
explícita; sus permisos efectivos, grantors y grant options deben coincidir o se aborta.

El down requiere un ejecutor administrativo capaz de restaurar el propietario y los grantors.
Sin backup o sin esos privilegios, aborta transaccionalmente. Sólo elimina las cinco RPCs nuevas
y su tabla privada de respaldo. Los DROP no usan CASCADE. El CASCADE de REVOKE se limita a cadenas
de concesión del switch, que luego se reconstruyen y verifican. No revierte cambios de contexto
de usuarios ni borra auditoría. Frontend y RPCs deben volver juntos a su versión previa.

## Verificación sin SQL

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand
git diff --check
```

Los tests JS cubren transición entre tenants, rechazo, fallo de página intermedia, cursor repetido,
páginas cortas, tenant ajeno, ausencia de descarga histórica al refrescar catálogos y publicación
atómica. Los tests de SQL son guardas estáticas; no prueban ejecución PostgreSQL.
`tests/db/035_owner_operational_context.sql` queda preparado para revisión manual, sin ejecutar.
