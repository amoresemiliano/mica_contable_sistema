# INFORME DELTA FINAL PRE-MIGRACIÓN MICA

## 1. Cambios Exactos

- Se modificó `sql/001_schema.sql`: La Foreign Key de `eco_review_actions.issue_id` ahora utiliza `ON DELETE RESTRICT` para evitar el borrado accidental y en cascada de acciones humanas de revisión.
- Se modificó `sql/004_audit.sql`: La Foreign Key de `eco_audit_events.organization_id` ahora utiliza `ON DELETE RESTRICT` para evitar la pérdida de trazabilidad histórica en caso de borrado de una organización. Se agregó un trigger defensivo `prevent_audit_mutation()` que lanza una excepción al intentar `UPDATE` o `DELETE`.

## 2. FK Final Matrix

| Parent | Child | ON DELETE | Motivo |
|---|---|---|---|
| eco_organizations | eco_user_profiles | CASCADE | Borrar org borra sus usuarios (no crítico) |
| eco_organizations | eco_source_imports | CASCADE | Borrar org borra archivos subidos no críticos |
| eco_source_imports | eco_source_files | CASCADE | Borrar import borra archivos |
| eco_source_files | eco_import_rows | CASCADE | Borrar archivo borra filas temporales |
| eco_import_rows | eco_normalized_records | CASCADE | Borrar fila elimina el registro asociado |
| eco_normalized_records | eco_import_issues | CASCADE | Borrar registro elimina sus errores |
| eco_import_issues | eco_review_actions | RESTRICT | **PRESERVAR:** Las acciones de revisión humanas forman parte de la trazabilidad y no deben borrarse silenciosamente por borrado de registros. |
| eco_organizations | eco_audit_events | RESTRICT | **PRESERVAR:** Audit preserva el histórico completo incluso si se intenta borrar la organización. |

## 3. Audit Trigger

Se implementó en `004_audit.sql`:

```sql
CREATE OR REPLACE FUNCTION public.prevent_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RAISE EXCEPTION 'Audit events are immutable and append-only';
END;
$$;

CREATE TRIGGER enforce_append_only_audit
BEFORE UPDATE OR DELETE ON public.eco_audit_events
FOR EACH ROW
EXECUTE FUNCTION public.prevent_audit_mutation();
```

- **Función:** `prevent_audit_mutation()` lanza excepción (abort transaction).
- **Trigger:** `enforce_append_only_audit` opera `BEFORE UPDATE OR DELETE`.
- **Privilegios:** `SECURITY DEFINER` ejecutando como owner (postgres).
- **Comportamiento:** Impide mutaciones accidentales independientemente del RLS (protege contra service_role bypass accidental).
- **Rollback:** `DROP TRIGGER enforce_append_only_audit ON public.eco_audit_events; DROP FUNCTION public.prevent_audit_mutation();`

## 4. Clasificación Bootstrap

Esta migración inicial se documenta como:
**SCHEMA_BOOTSTRAP_LOCKED_BY_DEFAULT**

No es una base funcional completa. 
- Solo `eco_audit_events` tendrá policies habilitadas explícitamente para inserts.
- El resto de las tablas permanecerán bajo `LOCKED_BY_DEFAULT`.
- La SPA NO deberá integrarse con persistencia real hasta la siguiente subfase donde se definan las políticas explícitas funcionales.

## 5. Matriz Policies Futura (Solo Diseño)

| Tabla | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| eco_organizations | Authenticated (matching org_id) | Admin only / Deny (dashboard only) | Admin only | Deny (managed by backend) |
| eco_user_profiles | Authenticated (matching org_id) | Admin only | User self / Admin | Admin only |
| eco_source_imports | Authenticated (matching org_id) | Authenticated (matching org_id) | Deny | Admin / Uploader |
| eco_source_files | Authenticated (matching org_id) | Authenticated (matching org_id) | Deny | Admin / Uploader |
| eco_import_rows | Authenticated (matching org_id) | Backend only (service) | Deny | Deny |
| eco_normalized_records | Authenticated (matching org_id) | Backend only (service) | Authenticated (Reviewers) | Deny |
| eco_import_issues | Authenticated (matching org_id) | Backend only (service) | Authenticated (Reviewers) | Deny |
| eco_review_actions | Authenticated (matching org_id) | Authenticated (Reviewers) | Deny (immutable) | Deny (immutable) |

## 6. Storage Limits Propuestos

Propuestas iniciales para el bucket `eco-imports-private-staging`:
- `file_size_limit`: **20971520** bytes (20 MB), suficiente para reportes XLS/CSV sin colapsar RAM/Workers.
- `allowed_mime_types`: `['application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/plain', 'text/csv']` (Para restringir subidas maliciosas).

## 7. Rollback Actualizado

```sql
DROP POLICY IF EXISTS "Allow org to select its files" ON storage.objects;
DROP POLICY IF EXISTS "Allow org to insert its files" ON storage.objects;
DROP POLICY IF EXISTS "Allow org to delete its files" ON storage.objects;
-- API call: DELETE /storage/v1/bucket/eco-imports-private-staging

DROP POLICY IF EXISTS "Audit events viewable by org" ON public.eco_audit_events;
DROP POLICY IF EXISTS "Audit events insertable by org" ON public.eco_audit_events;
DROP TRIGGER IF EXISTS enforce_append_only_audit ON public.eco_audit_events;
DROP FUNCTION IF EXISTS public.prevent_audit_mutation();
DROP TABLE IF EXISTS public.eco_audit_events;

DROP FUNCTION IF EXISTS private.org_id();
DROP FUNCTION IF EXISTS private.func_role();
DROP SCHEMA IF EXISTS private;

DROP TABLE IF EXISTS public.eco_review_actions;
DROP TABLE IF EXISTS public.eco_import_issues;
DROP TABLE IF EXISTS public.eco_normalized_records;
DROP TABLE IF EXISTS public.eco_import_rows;
DROP TABLE IF EXISTS public.eco_source_files;
DROP TABLE IF EXISTS public.eco_source_imports;
DROP TABLE IF EXISTS public.eco_user_profiles;
DROP TABLE IF EXISTS public.eco_organizations;
```

## 8. MCP Final Check

- PROJECT_REF = ourzapkjykzlwsjunzmd
- READ_ONLY = true
- PUBLIC_TABLES = 0
- MIGRATIONS = 0
- WRITES_EXECUTED = 0

## 9. GO/NO-GO Final

**GO FINAL RECOMENDADO.** El paquete local fue endurecido, la trazabilidad está fuertemente protegida por triggers defensivos y `RESTRICT` en llaves foráneas críticas, superando el estado inicial. El proyecto permanece limpio y sin mutaciones.
