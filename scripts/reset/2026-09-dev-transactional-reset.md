# Documentación de Reseteo Transaccional DEV (One-Off)

## Propósito y Alcance
Este script realiza un borrado transaccional físico de **todos los datos transaccionales e importados** para la organización de prueba DEV (`59436df3-9f15-4f5e-b17e-37c55482521c`).
Permite volver a un estado inicial ("Clean Slate") donde se puedan volver a importar exactamente los mismos archivos físicos de extractos bancarios, comprobantes ARCA y percepciones sin que surjan errores de duplicado (`FILE_ALREADY_EXISTS` o `duplicate_rows`).

> [!CAUTION]
> **PROHIBIDA SU EJECUCIÓN EN PRODUCCIÓN (PROD)**.
> El script incluye un guard de ejecución obligatorio que valida que la organización objetivo coincida exactamente con la UUID de DEV (`59436df3-9f15-4f5e-b17e-37c55482521c`). Si se ejecuta en otra organización, abortará inmediatamente con `RAISE EXCEPTION`.

## Tablas Transaccionales Eliminadas (Físicamente)
En orden estricto de claves foráneas (child first):
1. `eco_review_actions`
2. `eco_movement_allocations`
3. `eco_financial_movements` (extractos bancarios + sueldos)
4. `eco_import_issues`
5. `eco_normalized_records` (comprobantes emitidos/recibidos ARCA + percepciones IVA/ARBA)
6. `eco_import_rows`
7. `eco_source_files` (metadatos DB y hashes SHA-256)
8. `eco_source_imports` (cabeceras de importación y reintentos)

## Tablas de Configuración Preservadas (Intactas)
El reseteo **NO** elimina ni altera:
- `eco_organizations` (Identidad de la empresa/organización)
- `eco_user_profiles` (Usuarios y perfiles asociados)
- `eco_tax_categories` y `eco_org_tax_categories` (Categorías fiscales asignadas)
- `eco_economic_activities` y `eco_org_economic_activities` (Actividades económicas ARCA)
- `eco_org_activity_iibb_rates` (Alícuotas de Ingresos Brutos)
- `eco_financial_accounts` (Cuentas financieras/bancarias configuradas)
- `eco_classification_rules` (Reglas automáticas de categorización)
- `eco_counterparties` (Catálogo de contrapartes/proveedores)
- Permisos RLS, esquemas, funciones y políticas de seguridad

## Almacenamiento (Supabase Storage)
- **`STORAGE_DELETE_REQUIRED: NO`**.
- La función de deduplicación de archivos `check_file_importable(hash)` valida únicamente la tabla `eco_source_files`. Al limpiar los registros en DB, el sistema permite reimportar exactamente los mismos archivos con los mismos hashes SHA-256.

## Instrucciones de Ejecución Manual (Human Gate)
Ejecutar el script `scripts/reset/2026-09-dev-transactional-reset.sql` únicamente tras aprobación del **Human Gate** en el editor de SQL de Supabase para el proyecto DEV staging.
