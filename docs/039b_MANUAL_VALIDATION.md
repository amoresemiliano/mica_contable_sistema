# 039b — Matriz end-to-end preparada

**No ejecutada.** Requiere aplicación/deploy posteriores autorizados en `ourzapkjykzlwsjunzmd`. Usar fixtures y sesiones propias, sin impersonar usuarios reales.

| Perfil | Módulos/datasets | Importadores | Clasificar / baja lógica | Restaurar | Reportes / exportar | Usuarios/permisos | Alcance |
|---|---|---|---|---|---|---|---|
| Root | Todos MICA | Los tres aprobados | Sí / Sí | Sí, endpoint existente | Sí / Sí | Plataforma y empresa | Todas activas, sin membership artificial |
| Marianela | Todos MICA | Los tres | Sí / Sí | Sí, endpoint existente | Sí / Sí | Delegable, sin root/kernel | Scopes explícitos y altas futuras provisionadas |
| Admin organización | Empresa, configuración tenant | Los tres | Sí / Sí | No | Sí / Sí | Empresa y autoridad propia | Membership propio |
| Contador | Registros, catálogos, reportes, manual/OCR pendiente | Los tres | Sí / Sí | No | Sí / Sí | No | Membership propio |
| Importador | Registros, catálogos, consulta manual | Los tres, revisión/reintento | No / No | No | No / No | No | Membership propio |
| Auditor | Registros, catálogos, consulta manual, reportes | Ninguno | No / No | No | Sí / Sí | No | Membership propio |

Presupone perfiles activos, contexto confirmado, organización activa y sin overrides. Fiscal, altas/edición manual y OCR real siguen deshabilitados para todos. No se agrega CRUD/reporting/analytics nuevo.

## Seis checks de aceptación

1. **Perfil y navegación:** comprobar cada fila, incluyendo navegación directa a Configuración/reportes sin permisos. Root y Marianela recorren NORTE/OESTE/SUR/MICA desde sus sesiones; sin memberships inventados. En Network, Configuración/catálogos no solicitan readers de registros/financieros.
2. **Importadores y CRUD existente:** archivo de prueba de cada tipo autorizado; IMPORT_CREATE solo no abre nada; revocar IMPORT_VIEW oculta y deniega. Clasificar/baja lógica sólo con acciones concretas. MICA restaura mediante endpoint existente; tenant histórico con RECORD_RESTORE solo recibe denegación. DATA_RESTORE_ANY_ORG y RECORD_RESTORE efectivos son ambos obligatorios, junto a alcance y contexto. Los grants históricos no se borran. Auditor puede exportar; importador no. OCR/fiscal/manual persisten cerrados.
3. **ALLOW/DENY:** al auditor agregar ALLOW IMPORT_CREATE + BANK_IMPORT; habilita bancos porque ya tiene VIEW/IMPORT_VIEW. DENY BANK_IMPORT lo cierra. Revocar RECORD_VIEW retira módulos/datasets aunque queden acciones. Repetir DENY como root/Marianela. PLATFORM/null no opera tenant. El harness DB incluye ALLOW adicional y DENY.
4. **Datos/páginas:** 123 filas → 50/50/23, tamaños 25/100; filtro de 66 filas y totales filtrados. Búsqueda/orden/período vuelven a página 1. Clasificar en página 2 conserva IDs. Cambio de página/tenant borra selección; cambio durante lectura evita nuevas páginas/publicación anterior. Error muestra Reintentar sin bucle automático.
5. **Administración:** una tab visible, tablas acotadas y editor por selección. Roles: castellano, códigos secundarios, grupos/filtro/expandir/contador. OWNER_RESERVED/HORECA/propuestas no seleccionables. Revisar estado efectivo contextual. Marianela no modifica root ni delega fuera de alcance. Alta de organización crea scope; uno revocado no se reactiva.
6. **Responsive y pendientes:** 375px/escritorio, teclado/foco y formularios compactos. OCR sólo dentro de manuales; sin simulación. Llamada directa a creación manual/OCR permanece cerrada. Las once capabilities promovidas aparecen en el editor con aviso de backend pendiente y se guardan en presets/ALLOW. Las cuatro manuales forman parte del UP principal; asignarlas no habilita operaciones locales.

Registrar perfil/contexto, resultado esperado/observado, consola/respuesta servidor y capturas. Ejecutar harness DB sólo después de aprobación; usa fixtures y ROLLBACK. Jest no prueba compilación SQL, RLS ni RPC LIVE. No marcar end-to-end aprobado sin esas evidencias.
