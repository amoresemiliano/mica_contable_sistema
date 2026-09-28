# 039 — MICA Contable Argentina

Estado: implementación preparada para revisión manual. No se ejecutó SQL ni se verificó runtime DEV.
Proyecto canónico: `ourzapkjykzlwsjunzmd`.

## Contrato

- Un único helper frontend controla menú, navegación, importadores y descarte de datasets. Sólo consume capabilities efectivas filtradas por el contrato MICA de 038.
- Contexto `TENANT_READY` proviene de la confirmación del servidor. El servidor vuelve a validar perfil, organización activa, contexto coincidente, alcance y capability mediante `private.can_operate_mica_org` de 037. `ACCESS_ANY_ORG` nunca concede una acción.
- Comprobantes, percepciones, bancos, sueldos y movimientos manuales usan el VIEW existente `RECORD_VIEW`. Panel gerencial usa `REPORT_VIEW`. Categorías/actividades usan `ORG_VIEW`; tasas usan `CATALOG_ORG_VIEW`. Configuración conserva las capabilities administrativas de 038. Catálogo global sólo en Plataforma.
- Importadores requieren VIEW del módulo, `IMPORT_CREATE` y, respectivamente, `BANK_IMPORT`, `PERCEPTION_IMPORT` o `PAYROLL_IMPORT`. IMPORT_CREATE solo no habilita ningún importador. Recibidos/emitidos permanecen ocultos y sus endpoints de importación denegados hasta contar con una capability específica aprobada.
- La precedencia DENY/ALLOW/base permanece en 037; el frontend recibe su resultado efectivo y no recompone grants.
- Al recargar permisos, se descartan datasets sin VIEW, se limpian selecciones y se abandona un módulo revocado. Guardar administración recarga contexto; volver a enfocar la ventana también lo refresca si no hay operaciones pendientes. No se agregó sincronización multitab ni polling. El servidor verifica cada petición aunque el navegador tenga permisos anteriores.

## Backend necesario

Los importadores anteriores usaban `private.func_role()` y strings legacy. 039 sustituye esos controles, preservando sus contratos y lógica de persistencia. Se versionan 18 reemplazos:

- `create_import(text,text)`; `persist_import_batch(uuid,jsonb,jsonb)`; `persist_perceptions_batch(uuid,jsonb,jsonb)`; `persist_financial_movements_batch(uuid,jsonb,jsonb)`.
- `request_failed_import_retry(uuid)`; `check_file_importable(text)`.
- `soft_delete_normalized_record(uuid)`; `soft_delete_financial_movement(uuid)`; `restore_normalized_record(uuid)`; `restore_financial_movement(uuid)`.
- `update_record_classification(uuid,uuid,uuid)`; `update_movement_classification(uuid,uuid,uuid)`; `bulk_update_record_classification(text,date,date,uuid,uuid)`.
- `get_active_normalized_records()`; `get_active_financial_movements()`; `get_deleted_normalized_records()`; `get_deleted_financial_movements()`.

Tambi?n se protege el reader legacy `get_active_org_iibb_rates()` mediante `CATALOG_ORG_VIEW`. Las tablas de asignaci?n de categor?as/actividades/tasas reciben pol?ticas restrictivas equivalentes.

Helpers privados nuevos: `require_039_action(text)`, `require_039_import(text,text)`, `require_039_batch(uuid,text[])`. Predicado público de storage: `mica_storage_import_allowed(text,text)`.

Todas las funciones tienen `SECURITY DEFINER`, `search_path=''`; RPCs públicas sólo authenticated y helpers privados sin EXECUTE público. Se agregan políticas restrictivas de SELECT para records, financials y staging/import issues, además de SELECT/INSERT/DELETE del bucket privado. No se alteran políticas históricas ni `can_org`.

El UP aborta antes de DDL si los 18 cuerpos/atributos LIVE no coinciden con el baseline del repo. **Esos hashes no fueron comprobados contra LIVE en esta sesión.** Conserva un backup privado de definiciones y ACL. El DOWN valida drift, restaura funciones/ACL previas y elimina exclusivamente políticas/helpers/backup 039, sin CASCADE. No borra datos importados.

## Límites que requieren decisión o trabajo posterior

1. **Hueco fiscal documentado para fase posterior:** el contrato MICA de 037/038 y `src/js/core/micaCapabilities.js` no contiene una capability específica de importación de comprobantes. `RECORD_CLASSIFY` autoriza clasificación; `DOCUMENTS_UPLOAD` autoriza OCR; `IMPORT_RETRY`/`IMPORT_REVIEW` tampoco autorizan una importación fiscal nueva. No se reutilizan ni se crea una capability nueva en 039. Con VIEW + IMPORT_CREATE + PERCEPTION_IMPORT se muestra únicamente percepciones. Recibidos/emitidos quedan cerrados tanto en UI/handlers como en create/batch/retry/storage mediante el guard SQL compartido. Su módulo de consulta conserva RECORD_VIEW.
2. **OCR carece de backend real en este repo.** El flujo previo fabricaba proveedor/importes mediante un timer. Se retiró esa simulación. El módulo se descubre por `DOCUMENTS_UPLOAD`, `DOCUMENTS_OCR_PROCESS` o `DOCUMENTS_OCR_VERIFY`; cada acción tiene su guard separado, pero permanece inhabilitada con mensaje explícito hasta conectar un backend aprobado. Esto no equivale a OCR funcional end-to-end.
3. Persistencia manual permanece fuera de alcance. Su módulo respeta VIEW y sus formularios siguen deshabilitados.

## Cierre pre-aplicación

El permiso accidental estaba en `canImport()` (`recibido/emitido: null`) y en los pares ARCA/COMPRA-VENTA admitidos por `private.require_039_import()`. Ambos fueron cerrados. `store.canImportOperational()` delega en ese helper; el selector controla boxes/inputs; `ui.js` comprueba el helper antes del procesamiento y al confirmar la importación.

Las definiciones versionadas de 036/037/037a/038 no reemplazan ninguna de las 18 funciones que 039 reemplaza. Esto explica el baseline esperado, pero **no demuestra igualdad con LIVE**. No se modificaron sus hashes esperados para aceptar drift. El UP conserva preflight estricto y ahora comprueba también el backup 038 y sus dependencias directas. El DOWN sigue restaurando definiciones y ACL capturadas al aplicar el UP.

Antes de aplicar, ejecutar manualmente `sql/039_preflight_readonly.sql` únicamente en `ourzapkjykzlwsjunzmd` y revisar sus cuatro resultados: 18 firmas/cuerpos/atributos coincidentes, argumentos/retornos y ACL revisados, helpers y objetos 038 presentes, backup 039 ausente y columnas organization_id UUID con RLS. Las ACL extra requieren revisión: el UP restringe RPCs públicas a owner/authenticated, elimina EXECUTE de anon/PUBLIC y conserva la ACL previa en backup para el DOWN. Si hay un hash diferente, obtener pg_get_functiondef de esa firma y revisar antes de aplicar; no saltar el preflight. Estas consultas no fueron ejecutadas por el agente.

OCR deshabilitado es el estado aprobado para 039 y no bloquea esta aplicación.

## Validación preparada

- Jest: guards reales frontend, revocación, navegación, OCR independiente, ausencia de llamadas a datasets sin VIEW, contratos SQL y SHA-256 de migraciones anteriores.
- Harness `tests/db/039_module_and_import_capabilities.sql`: BEGIN/ROLLBACK; fixtures dinámicos; JWT; llamadas como authenticated; root, staff sin membership y tenant; scope sin acción, DENY, revocación entre creación y batch/storage, Plataforma/null, VIEW y organización inactiva. No ejecutado.

Tras revisar/aplicar manualmente 039: correr su harness; comprobar menú/navegación sin VIEW; conceder VIEW+IMPORT_CREATE+acción y completar una importación bancaria/percepción/sueldo; revocar VIEW y volver a la pesta?a; comprobar salida del módulo y descarte de datos. OCR debe mostrar claramente que está pendiente, sin crear comprobantes.

El diff de revisi?n re?ne los archivos implicados contra HEAD y los nuevos archivos 039. En los archivos que ya estaban modificados incluye tambi?n cambios previos de 037/038 presentes en el working tree; no debe aplicarse ciegamente como un parche aislado sobre otro baseline.
