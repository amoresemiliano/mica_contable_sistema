# 039b — Disponibilidad operativa

Generado desde micaPermissionContract.js. Describe la implementación preparada, no una validación LIVE. ACTIVE no significa grant automático. DISABLED_PENDING_BACKEND permite asignar el permiso aprobado, pero no ejecutar una función inexistente. Las propuestas siguen sin ser asignables.

## ACTIVE

| Código | Función | Estado del contrato |
|---|---|---|
| `DATA_RESTORE_ANY_ORG` | Restaurar datos de empresas autorizadas | PREPARED_039B |
| `MICA_ADMIN_MANAGE` | Administrar usuarios y permisos MICA | PREPARED_039B |
| `PLATFORM_MANAGE` | Administrar la plataforma técnica | CURRENT |
| `GLOBAL_USER_MANAGE` | Administrar identidades globales | CURRENT |
| `PLAN_MANAGE` | Administrar planes | CURRENT |
| `ACCESS_ANY_ORG` | Acceder a cualquier organización | CURRENT |
| `SUPPORT_IMPERSONATE` | Asistencia técnica excepcional | CURRENT |
| `HARD_DELETE_EXCEPTIONAL` | Eliminar definitivamente de forma excepcional | CURRENT |
| `ORGANIZATION_CREATE` | Crear organizaciones | CURRENT |
| `ORGANIZATION_UPDATE` | Editar organizaciones | CURRENT |
| `ORGANIZATION_ARCHIVE` | Archivar organizaciones | CURRENT |
| `PLATFORM_MIGRATIONS_APPLY` | Aplicar migraciones técnicas | CURRENT |
| `PLATFORM_TENANTS_PROVISION` | Provisionar entornos | CURRENT |
| `PLATFORM_SYSTEM_MONITOR` | Supervisar el sistema | CURRENT |
| `GLOBAL_CATALOG_VIEW` | Ver catálogos generales | CURRENT |
| `GLOBAL_CATALOG_MANAGE` | Administrar catálogos generales | CURRENT |
| `CATALOG_ASSIGN_ANY_ORG` | Asignar catálogos a empresas | CURRENT |
| `RATE_MANAGE_ANY_ORG` | Administrar tasas de empresas | CURRENT |
| `AUDIT_PLATFORM_VIEW` | Ver auditoría de MICA | CURRENT |
| `ORG_VIEW` | Ver categorías y actividades | CURRENT |
| `ORG_SETTINGS_VIEW` | Ver configuración de la empresa | CURRENT |
| `ORG_SETTINGS_MANAGE` | Administrar configuración de la empresa | CURRENT |
| `ORG_MEMBER_VIEW` | Ver usuarios de la empresa | CURRENT |
| `ORG_MEMBER_INVITE` | Incorporar usuarios | CURRENT |
| `ORG_MEMBER_MANAGE` | Administrar usuarios de la empresa | CURRENT |
| `ORG_MEMBER_PERMISSION_MANAGE` | Administrar permisos de la empresa | CURRENT |
| `IMPORT_VIEW` | Ver historial de cargas | CURRENT |
| `IMPORT_CREATE` | Crear / importar comprobantes | CURRENT |
| `IMPORT_RETRY` | Reintentar carga | CURRENT |
| `IMPORT_REVIEW` | Revisar cargas e incidencias | CURRENT |
| `RECORD_VIEW` | Ver comprobantes | CURRENT |
| `RECORD_CLASSIFY` | Clasificar comprobantes | CURRENT |
| `RECORD_SOFT_DELETE` | Eliminar lógicamente | CURRENT |
| `RECORD_RESTORE` | Restaurar registros eliminados | CURRENT |
| `PERCEPTION_IMPORT` | Importar percepciones | CURRENT |
| `BANK_IMPORT` | Importar extractos | CURRENT |
| `PAYROLL_IMPORT` | Importar liquidaciones | CURRENT |
| `ISSUE_RESOLVE` | Resolver incidencias | CURRENT |
| `CATALOG_ORG_VIEW` | Ver tasas y catálogos asignados | CURRENT |
| `CATALOG_ACTIVITY_MANAGE` | Administrar actividades | CURRENT |
| `CATALOG_CATEGORY_MANAGE` | Administrar categorías | CURRENT |
| `REPORT_VIEW` | Ver reportes, resultados y resumen impositivo | CURRENT |
| `REPORT_EXPORT` | Exportar reportes | CURRENT |
| `TICKET_CREATE` | Crear solicitud de soporte | CURRENT |
| `TICKET_VIEW_ORG` | Ver solicitudes de soporte | CURRENT |
| `AUDIT_VIEW_ORG` | Ver auditoría de la empresa | CURRENT |
| `FINANCIAL_ALLOCATION_EDIT` | Editar imputaciones y asignaciones | CURRENT |
| `SENSITIVEDATA_BANKING_READ` | Ver información bancaria sensible | CURRENT |
| `SENSITIVEDATA_SALARIES_READ` | Ver información salarial sensible | CURRENT |

## DISABLED_PENDING_BACKEND

| Código | Función | Estado del contrato |
|---|---|---|
| `REPORT_COMPARE_SCOPED_ORGS` | Comparar organizaciones | CURRENT |
| `REPORT_CONSOLIDATED_SCOPED_ORGS` | Ver reportes consolidados | CURRENT |
| `SAAS_ANALYTICS_VIEW` | Ver métricas de plataforma | CURRENT |
| `DOCUMENTS_UPLOAD` | Subir documentos | CURRENT |
| `DOCUMENTS_OCR_PROCESS` | Procesar con OCR | CURRENT |
| `DOCUMENTS_OCR_VERIFY` | Verificar OCR | CURRENT |
| `PURCHASES_INVOICES_MANAGE` | Gestionar comprobantes de compras | PREPARED_039B |
| `SUPPLIERS_VIEW` | Ver proveedores | PREPARED_039B |
| `SUPPLIERS_MANAGE` | Administrar proveedores | PREPARED_039B |
| `SALES_VIEW` | Ver comprobantes de ventas | PREPARED_039B |
| `PERSONNEL_EMPLOYEES_MANAGE` | Administrar empleados | PREPARED_039B |
| `INTEGRATIONS_CONFIG_MANAGE` | Configurar integraciones | PREPARED_039B |
| `INTEGRATIONS_SYNC_TRIGGER` | Ejecutar sincronizaciones | PREPARED_039B |
| `MANUAL_MOVEMENT_VIEW` | Ver movimientos manuales | PREPARED_039B |
| `MANUAL_MOVEMENT_CREATE` | Crear movimientos manuales | PREPARED_039B |
| `MANUAL_MOVEMENT_EDIT` | Editar movimientos manuales | PREPARED_039B |
| `MANUAL_MOVEMENT_SOFT_DELETE` | Eliminar lógicamente movimientos manuales | PREPARED_039B |
| `FISCAL_DOCUMENT_IMPORT` | Importar comprobantes fiscales | PROPOSED |
| `DOCUMENTS_OCR_CONFIRM` | Incorporar comprobante verificado | PROPOSED |
| `RECONCILIATION_VIEW` | Revisar conciliaciones | PROPOSED |
| `RECONCILIATION_CONFIRM` | Confirmar conciliaciones | PROPOSED |
| `DATA_SOFT_DELETE` | Eliminar datos lógicamente | PROPOSED |

Los códigos ACTIVE mantienen sus operaciones y controles existentes; no crean módulos nuevos. Restauración se implementa en ambos RPC con doble permiso y alcance. Los códigos nuevos de proveedores/compras/ventas/personal/integraciones y manuales son asignables con backend específico pendiente. Las vistas compartidas actuales siguen usando RECORD_VIEW. OCR, importación fiscal y confirmación de conciliaciones continúan cerrados.
