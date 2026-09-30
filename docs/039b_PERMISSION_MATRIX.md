# 039b — Contrato de permisos y matriz de presets

Generado desde `src/js/core/micaPermissionContract.js`. No editar las tablas a mano.

CURRENT = contrato vigente; PREPARED_039B = SQL preparado, no aplicado; PROPOSED = propuesta, no asignable ni visible en el editor. Ninguna etiqueta concede autoridad.

| Preset | Grants PLATFORM | Grants ORGANIZATION |
|---|---|---|
| Root técnico MICA | 22 | 44 |
| Administración general MICA | 11 | 44 |
| Administrador de organización | 0 | 36 |
| Contador / operador contable | 0 | 31 |
| Operador de importaciones | 0 | 12 |
| Consulta / auditor | 0 | 8 |

## MICA / Plataforma

| Capability | Nombre | Función | Grupo | Estado | Runtime | Asignable | Reservada | Editor | Orden |
|---|---|---|---|---|---|---|---|---|---|
| `DATA_RESTORE_ANY_ORG` | Restaurar datos de empresas autorizadas | Restaurar con alcance, contexto confirmado y RECORD_RESTORE efectivo. | Administración MICA | PREPARED_039B | ACTIVE | Sí | No | Sí | 0 |
| `MICA_ADMIN_MANAGE` | Administrar usuarios y permisos MICA | Gestionar usuarios, presets y asignaciones dentro del alcance delegado. | Usuarios y permisos | PREPARED_039B | ACTIVE | Sí | No | Sí | 1 |
| `PLATFORM_MANAGE` | Administrar la plataforma técnica | Administración reservada del entorno técnico. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 2 |
| `GLOBAL_USER_MANAGE` | Administrar identidades globales | Control reservado de identidades de la plataforma. | Usuarios y permisos | CURRENT | ACTIVE | No | Sí | No | 3 |
| `PLAN_MANAGE` | Administrar planes | Administración técnica de planes de servicio. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 4 |
| `ACCESS_ANY_ORG` | Acceder a cualquier organización | Permite seleccionar organizaciones; no concede acciones dentro de ellas. | Organizaciones | CURRENT | ACTIVE | No | Sí | No | 5 |
| `SUPPORT_IMPERSONATE` | Asistencia técnica excepcional | Facultad reservada de soporte; no sustituye la sesión de administración MICA. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 6 |
| `HARD_DELETE_EXCEPTIONAL` | Eliminar definitivamente de forma excepcional | Eliminación irreversible, exclusiva del owner técnico. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 7 |
| `ORGANIZATION_CREATE` | Crear organizaciones | Dar de alta una organización; reservado por el contrato vigente. | Organizaciones | CURRENT | ACTIVE | No | Sí | No | 8 |
| `ORGANIZATION_UPDATE` | Editar organizaciones | Editar datos de las organizaciones del alcance asignado. | Organizaciones | CURRENT | ACTIVE | Sí | No | Sí | 9 |
| `ORGANIZATION_ARCHIVE` | Archivar organizaciones | Desactivar organizaciones; reservado por el contrato vigente. | Organizaciones | CURRENT | ACTIVE | No | Sí | No | 10 |
| `PLATFORM_MIGRATIONS_APPLY` | Aplicar migraciones técnicas | Modificar la estructura técnica de la plataforma. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 11 |
| `PLATFORM_TENANTS_PROVISION` | Provisionar entornos | Provisionar infraestructura y entornos técnicos. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 12 |
| `PLATFORM_SYSTEM_MONITOR` | Supervisar el sistema | Consultar el estado técnico del sistema. | Administración MICA | CURRENT | ACTIVE | No | Sí | No | 13 |
| `GLOBAL_CATALOG_VIEW` | Ver catálogos generales | Consultar los catálogos compartidos de MICA. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 14 |
| `GLOBAL_CATALOG_MANAGE` | Administrar catálogos generales | Mantener los catálogos compartidos de MICA. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 15 |
| `CATALOG_ASSIGN_ANY_ORG` | Asignar catálogos a empresas | Asignar elementos del catálogo a organizaciones autorizadas. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 16 |
| `RATE_MANAGE_ANY_ORG` | Administrar tasas de empresas | Administrar tasas impositivas dentro del alcance autorizado. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 17 |
| `REPORT_COMPARE_SCOPED_ORGS` | Comparar organizaciones | Consultar comparaciones entre organizaciones autorizadas; sin crear reportes nuevos. | Reportes | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 18 |
| `REPORT_CONSOLIDATED_SCOPED_ORGS` | Ver reportes consolidados | Consultar reportes consolidados del alcance autorizado. | Reportes | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 19 |
| `SAAS_ANALYTICS_VIEW` | Ver métricas de plataforma | Permiso existente de métricas; no implementa analítica nueva. | Reportes | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 20 |
| `AUDIT_PLATFORM_VIEW` | Ver auditoría de MICA | Consultar eventos de auditoría de plataforma. | Auditoría y soporte | CURRENT | ACTIVE | Sí | No | Sí | 21 |

### Presets × capability

| Capability | Root técnico MICA | Administración general MICA | Administrador de organización | Contador / operador contable | Operador de importaciones | Consulta / auditor |
|---|---|---|---|---|---|---|
| `DATA_RESTORE_ANY_ORG` | ✅ | ✅ | — | — | — | — |
| `MICA_ADMIN_MANAGE` | ✅ | ✅ | — | — | — | — |
| `PLATFORM_MANAGE` | ✅ | — | — | — | — | — |
| `GLOBAL_USER_MANAGE` | ✅ | — | — | — | — | — |
| `PLAN_MANAGE` | ✅ | — | — | — | — | — |
| `ACCESS_ANY_ORG` | ✅ | — | — | — | — | — |
| `SUPPORT_IMPERSONATE` | ✅ | — | — | — | — | — |
| `HARD_DELETE_EXCEPTIONAL` | ✅ | — | — | — | — | — |
| `ORGANIZATION_CREATE` | ✅ | — | — | — | — | — |
| `ORGANIZATION_UPDATE` | ✅ | ✅ | — | — | — | — |
| `ORGANIZATION_ARCHIVE` | ✅ | — | — | — | — | — |
| `PLATFORM_MIGRATIONS_APPLY` | ✅ | — | — | — | — | — |
| `PLATFORM_TENANTS_PROVISION` | ✅ | — | — | — | — | — |
| `PLATFORM_SYSTEM_MONITOR` | ✅ | — | — | — | — | — |
| `GLOBAL_CATALOG_VIEW` | ✅ | ✅ | — | — | — | — |
| `GLOBAL_CATALOG_MANAGE` | ✅ | ✅ | — | — | — | — |
| `CATALOG_ASSIGN_ANY_ORG` | ✅ | ✅ | — | — | — | — |
| `RATE_MANAGE_ANY_ORG` | ✅ | ✅ | — | — | — | — |
| `REPORT_COMPARE_SCOPED_ORGS` | ✅ | ✅ | — | — | — | — |
| `REPORT_CONSOLIDATED_SCOPED_ORGS` | ✅ | ✅ | — | — | — | — |
| `SAAS_ANALYTICS_VIEW` | ✅ | ✅ | — | — | — | — |
| `AUDIT_PLATFORM_VIEW` | ✅ | ✅ | — | — | — | — |

## Organización / Empresa

| Capability | Nombre | Función | Grupo | Estado | Runtime | Asignable | Reservada | Editor | Orden |
|---|---|---|---|---|---|---|---|---|---|
| `ORG_VIEW` | Ver categorías y actividades | Consultar el contexto de la empresa y sus categorías y actividades. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 100 |
| `ORG_SETTINGS_VIEW` | Ver configuración de la empresa | Consultar la configuración de la organización. | Organizaciones | CURRENT | ACTIVE | Sí | No | Sí | 101 |
| `ORG_SETTINGS_MANAGE` | Administrar configuración de la empresa | Modificar la configuración de la organización. | Organizaciones | CURRENT | ACTIVE | Sí | No | Sí | 102 |
| `ORG_MEMBER_VIEW` | Ver usuarios de la empresa | Consultar los usuarios incorporados a la organización. | Usuarios y permisos | CURRENT | ACTIVE | Sí | No | Sí | 103 |
| `ORG_MEMBER_INVITE` | Incorporar usuarios | Incorporar usuarios existentes a la organización. | Usuarios y permisos | CURRENT | ACTIVE | Sí | No | Sí | 104 |
| `ORG_MEMBER_MANAGE` | Administrar usuarios de la empresa | Activar, desactivar y asignar perfiles a miembros. | Usuarios y permisos | CURRENT | ACTIVE | Sí | No | Sí | 105 |
| `ORG_MEMBER_PERMISSION_MANAGE` | Administrar permisos de la empresa | Gestionar permisos delegables de miembros sin superar la autoridad propia. | Usuarios y permisos | CURRENT | ACTIVE | Sí | No | Sí | 106 |
| `IMPORT_VIEW` | Ver historial de cargas | Consultar cargas e incidencias; requisito común de los importadores. No sustituye la lectura de registros. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 107 |
| `IMPORT_CREATE` | Crear / importar comprobantes | Requisito común de importación. Solo no habilita importadores, ni autoriza importación fiscal. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 108 |
| `IMPORT_RETRY` | Reintentar carga | Reintentar una carga autorizada por su tipo de importación. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 109 |
| `IMPORT_REVIEW` | Revisar cargas e incidencias | Revisar la información y las incidencias de una carga. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 110 |
| `RECORD_VIEW` | Ver comprobantes | Lectura compartida de comprobantes, percepciones, bancos, sueldos y movimientos manuales en el contrato vigente. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 111 |
| `RECORD_CLASSIFY` | Clasificar comprobantes | Editar la clasificación de comprobantes y movimientos existentes. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 112 |
| `RECORD_SOFT_DELETE` | Eliminar lógicamente | Ocultar registros sin destruirlos: comprobantes, percepciones, bancos y sueldos persistidos. Manuales pendientes de backend. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 113 |
| `RECORD_RESTORE` | Restaurar registros eliminados | Restauración operativa MICA dentro del contexto de empresa; no se incluye en presets tenant nuevos. | Comprobantes | CURRENT | ACTIVE | Sí | No | Sí | 114 |
| `PERCEPTION_IMPORT` | Importar percepciones | Importar percepciones con lectura de registros y requisitos comunes de importación. | Percepciones | CURRENT | ACTIVE | Sí | No | Sí | 115 |
| `BANK_IMPORT` | Importar extractos | Importar extractos bancarios con lectura y requisitos comunes. | Bancos | CURRENT | ACTIVE | Sí | No | Sí | 116 |
| `PAYROLL_IMPORT` | Importar liquidaciones | Importar liquidaciones de sueldos con lectura y requisitos comunes. | Sueldos | CURRENT | ACTIVE | Sí | No | Sí | 117 |
| `ISSUE_RESOLVE` | Resolver incidencias | Resolver incidencias de cargas y registros. | Conciliación | CURRENT | ACTIVE | Sí | No | Sí | 118 |
| `CATALOG_ORG_VIEW` | Ver tasas y catálogos asignados | Consultar tasas y catálogos asignados a la empresa. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 119 |
| `CATALOG_ACTIVITY_MANAGE` | Administrar actividades | Gestionar actividades económicas de la organización. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 120 |
| `CATALOG_CATEGORY_MANAGE` | Administrar categorías | Gestionar categorías impositivas de la organización. | Categorización impositiva | CURRENT | ACTIVE | Sí | No | Sí | 121 |
| `REPORT_VIEW` | Ver reportes, resultados y resumen impositivo | Consultar las vistas de reportes ya existentes. | Reportes | CURRENT | ACTIVE | Sí | No | Sí | 122 |
| `REPORT_EXPORT` | Exportar reportes | Exportar reportes de la organización. | Reportes | CURRENT | ACTIVE | Sí | No | Sí | 123 |
| `TICKET_CREATE` | Crear solicitud de soporte | Solicitar asistencia para la organización. | Auditoría y soporte | CURRENT | ACTIVE | Sí | No | Sí | 124 |
| `TICKET_VIEW_ORG` | Ver solicitudes de soporte | Consultar solicitudes de la organización. | Auditoría y soporte | CURRENT | ACTIVE | Sí | No | Sí | 125 |
| `AUDIT_VIEW_ORG` | Ver auditoría de la empresa | Consultar eventos de auditoría de la organización. | Auditoría y soporte | CURRENT | ACTIVE | Sí | No | Sí | 126 |
| `FINANCIAL_ALLOCATION_EDIT` | Editar imputaciones y asignaciones | Editar imputaciones financieras; no equivale a una confirmación de conciliación. | Conciliación | CURRENT | ACTIVE | Sí | No | Sí | 127 |
| `SENSITIVEDATA_BANKING_READ` | Ver información bancaria sensible | Acceso al permiso específico de información bancaria sensible. | Datos sensibles | CURRENT | ACTIVE | Sí | No | Sí | 128 |
| `SENSITIVEDATA_SALARIES_READ` | Ver información salarial sensible | Acceso al permiso específico de información salarial sensible. | Datos sensibles | CURRENT | ACTIVE | Sí | No | Sí | 129 |
| `DOCUMENTS_UPLOAD` | Subir documentos | Vía OCR dentro de carga manual; inhabilitada hasta disponer de backend real. | Carga manual y OCR | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 130 |
| `DOCUMENTS_OCR_PROCESS` | Procesar con OCR | Procesar documentos con un backend real, todavía pendiente. | Carga manual y OCR | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 131 |
| `DOCUMENTS_OCR_VERIFY` | Verificar OCR | Revisar una extracción real; no habilita su incorporación sin backend. | Carga manual y OCR | CURRENT | DISABLED_PENDING_BACKEND | Sí | No | Sí | 132 |
| `PURCHASES_INVOICES_MANAGE` | Gestionar comprobantes de compras | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Proveedores / compras | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 150 |
| `SUPPLIERS_VIEW` | Ver proveedores | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Proveedores / compras | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 151 |
| `SUPPLIERS_MANAGE` | Administrar proveedores | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Proveedores / compras | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 152 |
| `SALES_VIEW` | Ver comprobantes de ventas | Permiso MICA aprobado; la vista compartida actual sigue requiriendo RECORD_VIEW. | Ventas | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 153 |
| `PERSONNEL_EMPLOYEES_MANAGE` | Administrar empleados | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Personal | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 154 |
| `INTEGRATIONS_CONFIG_MANAGE` | Configurar integraciones | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Integraciones | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 155 |
| `INTEGRATIONS_SYNC_TRIGGER` | Ejecutar sincronizaciones | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Integraciones | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 156 |
| `MANUAL_MOVEMENT_VIEW` | Ver movimientos manuales | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Carga manual y OCR | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 157 |
| `MANUAL_MOVEMENT_CREATE` | Crear movimientos manuales | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Carga manual y OCR | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 158 |
| `MANUAL_MOVEMENT_EDIT` | Editar movimientos manuales | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Carga manual y OCR | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 159 |
| `MANUAL_MOVEMENT_SOFT_DELETE` | Eliminar lógicamente movimientos manuales | Permiso MICA aprobado y asignable; su backend operativo sigue pendiente. | Carga manual y OCR | PREPARED_039B | DISABLED_PENDING_BACKEND | Sí | No | Sí | 160 |
| `FISCAL_DOCUMENT_IMPORT` | Importar comprobantes fiscales | Capability específica propuesta para recibidos y emitidos; endpoints siguen cerrados. | Comprobantes | PROPOSED | DISABLED_PENDING_BACKEND | No | No | No | 200 |
| `DOCUMENTS_OCR_CONFIRM` | Incorporar comprobante verificado | Confirmar la incorporación de un documento extraído; pendiente de backend. | Carga manual y OCR | PROPOSED | DISABLED_PENDING_BACKEND | No | No | No | 201 |
| `RECONCILIATION_VIEW` | Revisar conciliaciones | Propuesta de lectura específica de conciliaciones; sin módulo nuevo en esta fase. | Conciliación | PROPOSED | DISABLED_PENDING_BACKEND | No | No | No | 202 |
| `RECONCILIATION_CONFIRM` | Confirmar conciliaciones | Confirmación de conciliaciones propuesta; no se infiere de clasificar. | Conciliación | PROPOSED | DISABLED_PENDING_BACKEND | No | No | No | 203 |
| `DATA_SOFT_DELETE` | Eliminar datos lógicamente | Propuesta genérica diferida; RECORD_SOFT_DELETE sigue como implementación. | Comprobantes | PROPOSED | DISABLED_PENDING_BACKEND | No | No | No | 204 |

### Presets × capability

| Capability | Root técnico MICA | Administración general MICA | Administrador de organización | Contador / operador contable | Operador de importaciones | Consulta / auditor |
|---|---|---|---|---|---|---|
| `ORG_VIEW` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `ORG_SETTINGS_VIEW` | ✅ | ✅ | ✅ | ✅ | — | — |
| `ORG_SETTINGS_MANAGE` | ✅ | ✅ | ✅ | — | — | — |
| `ORG_MEMBER_VIEW` | ✅ | ✅ | ✅ | — | — | — |
| `ORG_MEMBER_INVITE` | ✅ | ✅ | ✅ | — | — | — |
| `ORG_MEMBER_MANAGE` | ✅ | ✅ | ✅ | — | — | — |
| `ORG_MEMBER_PERMISSION_MANAGE` | ✅ | ✅ | ✅ | — | — | — |
| `IMPORT_VIEW` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `IMPORT_CREATE` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `IMPORT_RETRY` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `IMPORT_REVIEW` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `RECORD_VIEW` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `RECORD_CLASSIFY` | ✅ | ✅ | ✅ | ✅ | — | — |
| `RECORD_SOFT_DELETE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `RECORD_RESTORE` | ✅ | ✅ | — | — | — | — |
| `PERCEPTION_IMPORT` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `BANK_IMPORT` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `PAYROLL_IMPORT` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `ISSUE_RESOLVE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `CATALOG_ORG_VIEW` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `CATALOG_ACTIVITY_MANAGE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `CATALOG_CATEGORY_MANAGE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `REPORT_VIEW` | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| `REPORT_EXPORT` | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| `TICKET_CREATE` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `TICKET_VIEW_ORG` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `AUDIT_VIEW_ORG` | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| `FINANCIAL_ALLOCATION_EDIT` | ✅ | ✅ | ✅ | ✅ | — | — |
| `SENSITIVEDATA_BANKING_READ` | ✅ | ✅ | ✅ | ✅ | — | — |
| `SENSITIVEDATA_SALARIES_READ` | ✅ | ✅ | ✅ | ✅ | — | — |
| `DOCUMENTS_UPLOAD` | ✅ | ✅ | ✅ | ✅ | — | — |
| `DOCUMENTS_OCR_PROCESS` | ✅ | ✅ | ✅ | ✅ | — | — |
| `DOCUMENTS_OCR_VERIFY` | ✅ | ✅ | ✅ | ✅ | — | — |
| `PURCHASES_INVOICES_MANAGE` | ✅ | ✅ | — | — | — | — |
| `SUPPLIERS_VIEW` | ✅ | ✅ | — | — | — | — |
| `SUPPLIERS_MANAGE` | ✅ | ✅ | — | — | — | — |
| `SALES_VIEW` | ✅ | ✅ | — | — | — | — |
| `PERSONNEL_EMPLOYEES_MANAGE` | ✅ | ✅ | — | — | — | — |
| `INTEGRATIONS_CONFIG_MANAGE` | ✅ | ✅ | — | — | — | — |
| `INTEGRATIONS_SYNC_TRIGGER` | ✅ | ✅ | — | — | — | — |
| `MANUAL_MOVEMENT_VIEW` | ✅ | ✅ | ✅ | ✅ | — | — |
| `MANUAL_MOVEMENT_CREATE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `MANUAL_MOVEMENT_EDIT` | ✅ | ✅ | ✅ | ✅ | — | — |
| `MANUAL_MOVEMENT_SOFT_DELETE` | ✅ | ✅ | ✅ | ✅ | — | — |
| `FISCAL_DOCUMENT_IMPORT` | — | — | — | — | — | — |
| `DOCUMENTS_OCR_CONFIRM` | — | — | — | — | — | — |
| `RECONCILIATION_VIEW` | — | — | — | — | — | — |
| `RECONCILIATION_CONFIRM` | — | — | — | — | — | — |
| `DATA_SOFT_DELETE` | — | — | — | — | — | — |

El preset es una base: ALLOW amplía y DENY restringe capacidades delegables dentro del alcance. OWNER_RESERVED nunca puede obtenerse por override. RECORD_RESTORE se administra sólo en bridges/platform scopes MICA, no en presets/memberships tenant nuevos. Los grants históricos se conservan, pero ambos RPC exigen además DATA_RESTORE_ANY_ORG efectiva y alcance de plataforma. Ningún tenant restaura con RECORD_RESTORE solo.

## Funciones que comparten permiso vigente

| Función | Grupo | Capability compartida |
|---|---|---|
| Ver percepciones | Percepciones | `RECORD_VIEW` |
| Ver movimientos bancarios | Bancos | `RECORD_VIEW` |
| Ver información de sueldos | Sueldos | `RECORD_VIEW` |
| Ver movimientos manuales | Carga manual y OCR | `RECORD_VIEW` |
| Ver resultados | Reportes | `REPORT_VIEW` |
| Ver resumen impositivo | Reportes | `REPORT_VIEW` |
| Ver comprobantes de ventas | Ventas | `RECORD_VIEW` |

No se ofrecen checkboxes independientes para estas funciones: revocar RECORD_VIEW afecta a todos sus módulos. Conciliar/confirmar no se infiere de clasificar: RECONCILIATION_VIEW/CONFIRM siguen como propuestas.
