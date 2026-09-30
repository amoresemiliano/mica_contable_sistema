# 039c — Estabilización funcional preparada

Estado: **IMPLEMENTED / STATICALLY_VERIFIED / READY_FOR_MANUAL_CHECK**.
Proyecto: MICA `ourzapkjykzlwsjunzmd`. Base revisada: `c4130ea`.
No se ejecutó SQL, no se hizo commit, push ni deploy. HORECA no se modificó.
La aplicación LIVE de 039b y el resultado de su harness son evidencia aportada por el usuario; no se volvieron a ejecutar.

## Diagnóstico y correcciones

| Problema | Evidencia del repositorio | Corrección preparada |
|---|---|---|
| Login intermitente | `checkUserProfile` declaraba fallo definitivo ante cualquier error de inicialización. `getSession` y `SIGNED_IN` podían iniciar cargas competidoras; se iniciaban RPC dentro del callback de auth. | Sólo `JWT issued at future`: hasta tres reintentos, esperas 400/1000/2000 ms, primer refresh y posterior recuperación de sesión. Cancelación por cambio de sesión. Otros errores quedan visibles. Callback diferido fuera del bloqueo de auth; bootstrap viejo no pisa eventos nuevos. No se atribuye el desfase al reloj del navegador: su origen LIVE no se comprobó. |
| Carga manual ausente | Git `5aa1cb5:index.html` conserva los formularios REGINFO y caja chica. Siguen en el HTML actual, ocultos por `renderOperationalImportControls`. Los handlers devuelven error antes de una antigua simulación local. | Se conservan campos, se retira la simulación y se conecta CRUD persistente. Tabla privada propia con contexto derivado, validación, autor/fechas, soft delete y auditoría. Listado y edición en Registro manual. OCR permite selección local y arrastre; no sube ni procesa. |
| Comprobantes sin box | `FISCAL_DOCUMENT_IMPORT` era una propuesta no asignable; ambos contratos de importación estaban deshabilitados y el guard SQL excluía ARCA. | Capability aprobada en 039c, presets y guard específicos. Usa los parsers ARCA existentes de recibidos/emitidos y sus archivos CSV/TXT/XLS/XLSX; no agrega formatos. |
| Sueldos duplicados invisibles | Las cuatro ramas `importable=false` terminaban sin refrescar. La caché por familia de 039b puede mantener un dataset ya cargado. El reader y el mapeo separan por `operation_type='SUELDO'`. | Recarga real, incluso con caché marcada como cargada; actualiza `salariesList` y `salaries`. RPC de diagnóstico cuenta filas del archivo mediante `row_id → file_id`, también tras retry. Distingue datos activos, eliminados y cabecera sin derivados. Sin consulta LIVE no se determina cuál de estos estados tiene el archivo reportado. |
| Banco: falta storagePrefix | `create_import` devuelve envelope completo. `request_failed_import_retry` de 039 devuelve `new_import_id` y `storage_path`, pero omite `organization_id/storage_prefix`. El frontend entra en esta rama cuando hay un archivo fallido, no por la antigüedad de la organización. | Retry devuelve envelope completo y creador actual, sin recurrir al creador histórico. Validación temprana e indivisible de ID/org/prefix. Archivo original reutilizado sin nueva subida ni cleanup de ese objeto. Cambio de generación invalida la operación pendiente; no se almacena envelope global. |
| Percepciones y duplicados | La rama de duplicado tampoco refrescaba, aunque los datos previamente cargados podían dar apariencia correcta. Los persistidores fiscal/percepciones rechazaban todo hash existente; el financiero ya contemplaba reutilización. | Recarga común sin duplicar. Reutilización sólo con linaje explícito de retry y ausencia de derivados, incluso eliminados. Bloqueo por archivo para carreras. Contadores de retries y derivados reales participan en detección de duplicados. Una carga con cero registros válidos no informa éxito. |
| Paginador | Ya tenía lógica 25/50/100, filtros y reset; controles sin estilo específico. | Cambios CSS acotados: espaciado, borde, foco, disabled y distribución móvil. Lógica conservada. |
| Alta/invitación de usuarios | Administración sólo ofrecía usuarios ya registrados. No hay carpeta de funciones/servidor desplegable para Admin API en el repo. | Opción B: preautorización pendiente. Email único, organización activa y preset compatible; autenticación Supabase normal mantiene perfil inactivo. Confirmación explícita sobre identidad verificada llama al asignador existente. Activación y overrides permanecen separados. No se envía email ni se expone service_role. |

## Contrato y alcance

Ver [matriz generada](039c_CONTRACT.md). Cada importador requiere `RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE` y su capability específica. `IMPORT_CREATE` solo nunca habilita un box.

- Fiscal: root, Administración general MICA, admin de organización, contador y operador; auditor no.
- Percepciones, bancos y sueldos: conservan capabilities específicas y parsers existentes.
- Manual: `MANUAL_MOVEMENT_VIEW` más CREATE, EDIT o SOFT_DELETE según acción. Los registros se muestran en **Registro manual**. No se simulan filas importadas ni se integran automáticamente en reporting: los registros normalizados requieren procedencia de archivo y no había un escritor manual seguro.
- OCR: selección local con `DOCUMENTS_UPLOAD`; estado explícito pendiente, sin procesamiento ni confirmación ficticios.
- Root y perfil `ACCOUNTING_SUPERADMIN`: se mantienen evaluador, DENY, scopes, restore y reserva técnica. No se crean memberships de plataforma. Las identidades reales de root/Marianela se validan manualmente en LIVE; las pruebas usan perfiles sintéticos.

`micaPermissionContract.js` sigue siendo la fuente de metadatos. La proyección histórica `MICA_PERMISSION_CATALOG_039B` permite reproducir los artefactos ya aplicados; 039c deriva el contrato actual sin reescribirlos.

## SQL preparado

1. [Preflight de lectura](../sql/039c_preflight_readonly.sql): siete firmas, MD5, owner, SECURITY DEFINER y search_path; colisión de capability fiscal. Diferencias requieren revisión antes de aplicar.
2. [UP](../sql/039c_functional_stabilization.sql): guarda definiciones, amplía contrato fiscal, completa retry, controla reutilización, añade diagnóstico de archivos y RPC/tablas privadas para manual e invitaciones. Preserva ACL de funciones reemplazadas; nuevos RPC sólo authenticated.
3. [DOWN](../sql/039c_functional_stabilization_down.sql): comprueba drift de funciones existentes y nuevas; rechaza si hay registros manuales/invitaciones o grants/overrides posteriores. No descarta datos de negocio para facilitar rollback.
4. [Harness](../tests/db/039c_functional_stabilization.sql): BEGIN/ROLLBACK, fixtures aislados, persistencia fiscal, retry bancario real, sueldo real, diagnóstico por linaje, manual CRUD/contexto/DENY, invitaciones tenant/plataforma, duplicados, pending, asignación, activación, override y root protegido. Los inserts auth del harness son exclusivamente fixtures; la implementación no escribe auth.users.

No se ha ejecutado ninguno de estos SQL. La compilación y ejecución PostgreSQL son parte del preflight/harness manual, no evidencia de Jest.

## Pruebas y conservación

- Jest completo: **45 suites, 583 tests**, resultado local satisfactorio.
- Tests nuevos: `functional039c.test.js`, `sql039c.test.js`; ampliados persistenceService, ownerOperationalContext y UI de administración.
- Incluye recuperación JWT acotada/cancelación, otros errores, envelopes nuevos/retry/org cruzada, reutilización sin upload, carga vacía, cinco tipos de duplicado, salary persistido con caché vacía, matriz fiscal por preset, manual RPC/permisos, invitación y separación de activación.
- Pruebas SQL son estáticas y no sustituyen el harness. Pruebas de UI usan DOM simulado; no se realizaron screenshots de navegador autenticado ni validación visual LIVE.
- Generadores 039b y 039c en modo `--check`, sintaxis JS y `git diff --check` forman parte del cierre local.
- Los **102 archivos anteriores del directorio sql** se compararon byte a byte mediante SHA-256, sin cambios.
- 039b UP: `9ACD24044BD054A2E96C3557C1A2EE96F5154F94C1E55A49C3CA43E6506806D6`.
- 039b DOWN: `D1A2A66CFC55B7706F00DA0E2DB2652B5C3F9322F21ECFDBE7104937E96E58E7`.

## Flujo de usuarios y UX esperada

Configuración → Usuarios → **+ Invitar usuario** → email/tipo/preset. Para tenant se usa la organización confirmada en el selector superior. La pantalla explica que registra preautorización y no envía correo. El administrador comparte el acceso habitual; el usuario autentica con Supabase y queda pendiente/inactivo. En la invitación, **Editar → Confirmar preset y organización** materializa asignación tras revalidar permisos e identidad. Después, **Usuarios → Editar → Activo** aprueba; **Asignaciones** mantiene scopes y overrides.

Carga manual conserva formulario REGINFO y movimiento interno, muestra el registro persistido y sus acciones según permisos. Seleccionar un PDF/imagen sólo muestra nombre y estado pendiente OCR. El paginador ocupa una franja compacta bajo la grilla; en móvil el indicador pasa a una línea propia y los controles conservan foco y disabled.

## Validación manual: seis bloques

1. **DB**: en el proyecto canónico, revisar el preflight antes de UP. Tras aplicación humana, ejecutar harness completo; esperar ROLLBACK sin excepción. No volver a aplicar 039b.
2. **Sesión**: iniciar root y Marianela; ante error futuro debe recuperarse sin clic o mostrar el error tras cuatro intentos totales. Cerrar sesión durante recuperación y comprobar que no reabre la cuenta. Otro error JWT debe permanecer visible.
3. **Importadores**: en organización existente y nueva, importar ARCA recibido/emitido, percepción, banco y sueldo soportados. Ver filas persistidas tras recarga. Repetir cada archivo: ningún alta extra, filas existentes visibles y mensaje común. Probar archivo fallido sin derivados: retry conserva org/linaje. Cabecera sin derivados aceptados debe mostrar inconsistencia, sin forzar reimportación.
4. **Contexto/permisos**: cambiar de org con preview abierto: se cierra y el callback viejo no guarda ni muestra datos en otra empresa. Revocar capability específica mediante DENY: desaparece box y RPC rechaza. Root y Marianela mantienen restore; Marianela no obtiene OWNER_RESERVED ni membership artificial.
5. **Manual/OCR/paginación**: guardar ambos formularios, recargar y editar/eliminar; cambiar org verifica aislamiento. Seleccionar/arrastrar imagen/PDF no crea comprobantes. Revisar paginador 25/50/100, filtros, reset al cambiar org y diseño móvil.
6. **Usuarios**: crear preautorizaciones tenant y plataforma, repetir email (rechazo), autenticar, confirmar asignación, comprobar aún inactivo, activar y aplicar DENY. Rechazar preset incompatible, target root y organización fuera de scope. Verificar entrada en contexto plataforma sin membership artificial.

## Archivos y diff

Runtime: `index.html`, `src/css/administration.css`, `src/js/ui.js`, `store.js`, `manualMovements.js`, `ocr.js`, `components/administration.js`, `components/operationalOrgSelector.js`, `core/sessionRecovery.js`, `core/importEnvelope.js`, `core/micaPermissionContract.js`, `core/services/administrationService.js`, `core/services/persistenceService.js`.

Contrato/evidencia: generadores `generate039bContract.mjs` y `generate039cContract.mjs`, los tres SQL 039c, harness 039c, fixture de hashes anteriores, tests mencionados, esta entrega, matriz y [diff completo del cambio](039c_REVIEW.diff). El diff excluye archivos scratch de trabajo y los untracked preexistentes ajenos a 039c.

**039c LISTA PARA PREFLIGHT LIVE**, no validada en runtime LIVE.
