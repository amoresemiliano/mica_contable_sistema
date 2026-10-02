# 039b — Permisos aprobados y disponibilidad

La aprobación funcional queda incorporada en `micaPermissionContract.js`. La [matriz generada](039b_PERMISSION_MATRIX.md) define los seis presets y el [inventario generado de runtime](039b_RUNTIME_STATUS.md) separa permiso asignable de función operativa. No se consultó LIVE.

Las siete capabilities de compras/proveedores/ventas/personal/integraciones y las cuatro manuales son `PREPARED_039B`, ORGANIZATION_DELEGABLE, activas en el catálogo SQL preparado y seleccionables en el editor. Sus operaciones específicas permanecen `DISABLED_PENDING_BACKEND`. El aviso del editor no deshabilita la asignación del permiso. Las vistas compartidas existentes siguen dependiendo de RECORD_VIEW.

Root y administración general reciben todas las capabilities ORGANIZATION aprobadas. Los cuatro permisos manuales también integran administrador/contador; los otros siete no tienen defaults tenant. Se pueden asignar por preset custom u override autorizado. Ninguna capability nueva reactiva simulaciones, importación fiscal ni OCR.

## Restauración cerrada en esta fase

DATA_RESTORE_ANY_ORG es PLATFORM_DELEGABLE, default de root y ACCOUNTING_SUPERADMIN. Ambos RPC de restauración exigen esa capability efectiva, alcance de plataforma, contexto tenant confirmado, organización activa y RECORD_RESTORE contextual efectivo. Se conserva además RECORD_VIEW. DENY de cualquiera de los permisos bloquea la operación.

RECORD_RESTORE histórico no se elimina; por sí solo ya no restaura. Los presets tenant y sus nuevas asignaciones no reciben restauración. ACCESS_ANY_ORG sólo aporta alcance. HARD_DELETE_EXCEPTIONAL permanece OWNER_RESERVED.

El DOWN restaura las definiciones anteriores de ambos RPC: revierte también esta restricción nueva. Aborta ante cambios posteriores de funciones o filas propias. Los grants históricos y capabilities adoptadas no son filas propias que pueda eliminar.

## Identidades existentes y preflight

Las [consultas read-only](../sql/039b_preflight_live_readonly.sql) muestran filas completas, definiciones/ACL/hashes de funciones, grants y overrides históricos, presets root/accounting y scopes.

`sql/039b_live_adoption_manifest.json` registra expectativas de adopción. `null` significa que el UP exige que el código no exista; no constituye evidencia de ausencia LIVE. Si existe, revisar su UUID, fila completa, scope, clase, estado y grants. Sólo con esa evidencia incorporar la fila JSON exacta al manifest y regenerar artefactos. El UP exige igualdad completa más scope/clase/actividad aprobados. Una incompatibilidad aborta; no se corrige automáticamente ni se cambia HORECA.

Adoptar conserva UUID y metadata. El seed inserta únicamente entradas faltantes y grants explícitos derivados de los presets MICA; no copia grants de otro producto. DOWN sólo elimina entradas efectivamente creadas por esta fase. Las capacidades nuevas permanecen en el UP principal: se retiró la propuesta manual separada e inactiva.

## Pendientes que continúan cerrados

FISCAL_DOCUMENT_IMPORT, DOCUMENTS_OCR_CONFIRM, RECONCILIATION_VIEW, RECONCILIATION_CONFIRM y DATA_SOFT_DELETE siguen como propuestas no asignables. OCR aprobado permanece sin backend real. No se abren módulos nuevos de reporting/analytics.

La paginación visual es cliente; los readers existentes no ofrecen filtros funcionales y conteo suficientes para paginación remota equivalente. La carga por demanda evita descargar movimientos al abrir Configuración, pero cada familia solicitada se descarga completa.
