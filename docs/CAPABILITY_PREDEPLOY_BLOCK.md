# Bloque 031-033: implementado; pendiente de verificacion DB

030 ya esta aplicada y no se modifica. No se ejecuto SQL, commit, push ni deploy.
La evidencia LIVE aportada por el usuario confirma el scope NULL del Owner,
la semantica estricta de can_platform, eco_organizations.is_active y los helpers
que consumen eco_membership_capability_overrides. La ejecucion de estas nuevas
migraciones y su test DB todavia NO esta validada en runtime.

## Migraciones y rollback

031 acepta VEGEN_PLATFORM_ADMIN activo con scope NULL o PLATFORM. Aborta si falta,
si otro scope esta presente, si cualquier membership lo referencia o si tiene
grants no PLATFORM. Guarda previous_template_scope, existed_before de ACCESS_ANY_ORG
y los grants previos ANTES de normalizar NULL a PLATFORM y agregar el grant.
can_platform no cambia. Down retira solo el grant agregado y restaura NULL solo
cuando 031 cambio ese scope. No toca otros grants ni roles de usuarios.

032 mantiene su propuesta: activa ACCOUNTING_SUPERADMIN y agrega exclusivamente
GLOBAL_CATALOG_VIEW, GLOBAL_CATALOG_MANAGE, CATALOG_ASSIGN_ANY_ORG. No agrega
ACCESS_ANY_ORG, analitica, soporte ni administracion. No elimina grants anteriores.
Down restaura su activacion previa y elimina solo los tres grants que haya agregado.
Los codigos de template se usan como presets iniciales, nunca como autoridad RPC.

033 agrega CATALOG_ACTIVITY_MANAGE y CATALOG_CATEGORY_MANAGE (ORGANIZATION).
Cada una permite activar/desactivar su tipo. Se otorgan solo a presets existentes,
activos y scope ORGANIZATION: CONSULTANT (LIVE) y TENANT_ADMIN (019/023; el mapeo
ADMIN de 022 usa este preset). No crea templates, no otorga a todos y no sobrescribe
DENY. eco_membership_capability_overrides sigue siendo canonica por can_org y
 authorized_orgs_for_capability. eco_member_capability_overrides queda intacta:
legacy/indeterminada pendiente, no formalmente obsoleta.

033 guarda definiciones, owners y ACL de las funciones afectadas, las dos policies
SELECT y la existencia previa de cada default. Down restaura esos snapshots;
elimina las funciones nuevas si antes no existian y solo los defaults agregados.
Registra mediante INSERT RETURNING los IDs de capabilities creadas por 033.
Down elimina solo esos IDs; las capabilities preexistentes permanecen. Si hay
referencias posteriores (grants/overrides u otra FK), aborta toda la transaccion
antes de borrar configuracion ajena. No toca is_assigned, is_active
ni datos de negocio. Los snapshots de 033 se consumen al hacer down; una nueva
aplicacion captura otra base. Rollback coordinado con frontend anterior, en orden
033 down -> 032 down -> 031 down; no revertir 030.

## Autorizacion y lecturas

private.catalog_assignment_target(UUID) exige auth, perfil activo,
CATALOG_ASSIGN_ANY_ORG y destino explicito existente con is_active IS TRUE.
No exige role, ACCESS_ANY_ORG, ORG_VIEW ni membership destino. Las cuatro RPC
assign/unassign de 030 siguen llamando este helper y preservando is_active.

public.list_catalog_assignment_targets() exige la misma capability y devuelve
solo organization_id y organization_name de organizaciones activas, ordenadas.
public.list_catalog_assignment_state(TEXT) acepta activity/category y devuelve
solo organization_id, item_id, is_assigned, is_active para organizaciones activas.
No devuelve CUIT ni datos operacionales. Frontend pagina los estados hasta una
pagina vacia, con orden estable por organizacion/item; no depende del limite
predeterminado de filas de PostgREST.

Policies reemplazadas:
- Org activities viewable by org, public.eco_org_economic_activities.
- Org categories viewable by org, public.eco_org_tax_categories.
Antes: SUPERADMIN o contexto propio/is_assigned.
Ahora: organization_id = private.org_id(), is_assigned IS TRUE y can_org(ORG_VIEW).
can_org resuelve perfil/membership/template/overrides, sin bypass por rol ni por
ACCESS_ANY_ORG. El estado transversal de catalogo se obtiene solo por RPC.
No se cambian policies de eco_organizations ni de los catalogos globales: las
referencias historicas siguen pudiendo resolver nombres. No se amplian ACL de tablas.

Activacion: caller activo, contexto activo, organizacion activa, membership activa,
can_org del permiso MANAGE correspondiente y fila is_assigned=true. Las RPC solo
cambian is_active/updated_at y auditan. No aceptan organization_id desde cliente.

get_my_effective_capabilities(UUID DEFAULT NULL) devuelve code/scope/organization_id
solo del caller. Usa can_platform y can_org; no replica grants/overrides. Si el caller
no tiene permisos en el org solicitado, esa parte queda vacia; los PLATFORM propios
siguen disponibles. Un org inactivo no devuelve capabilities ORGANIZATION.
get_my_catalog_capabilities() permanece como compatibilidad temporal.
Todas las RPC publicas nuevas/redefinidas de 033 son SECURITY DEFINER, search_path='',
REVOKE EXECUTE PUBLIC/anon y GRANT authenticated. Helpers privados revocados tambien
a authenticated; se invocan internamente. Los readers y helpers son STABLE.

## Frontend

hasCapability separa caches PLATFORM/ORGANIZATION; fail closed y descarte de
respuestas tardias se conservan. No infiere permisos de role/template/nombre MICA.
GLOBAL_CATALOG_MANAGE controla mantenimiento; CATALOG_ASSIGN_ANY_ORG controla
asignacion; MANAGE por tipo controla activacion propia. Los handlers repiten las
guardias y SQL decide finalmente. El selector de targets usa exclusivamente su
RPC dedicada, nunca la lista operacional de organizaciones ni ACCESS_ANY_ORG.
Se eliminaron las exclusiones de nombre MICA en las etiquetas de asignacion.
El cambio de contexto sigue siendo server-first; un rechazo conserva contexto/datos.

## Orden y comprobaciones de aceptacion

1. Coordinar una ventana sin uso del frontend de catalogo anterior; conservar backup.
2. Aplicar manualmente 031 -> 032 -> 033. NO volver a aplicar 030.
3. Ejecutar 033_capability_block_readonly_checks.sql: scopes/defaults, grants previos,
   policies, ACL y helpers. Los SELECTs de RPC efectivos requieren JWT del caller;
   SQL Editor como postgres sin JWT no representa al usuario.
4. Ejecutar tests/db/030_assignment_activation.sql como postgres en DEV aislado.
   Termina en ROLLBACK. Si el cliente se detiene al error, ejecutar ROLLBACK antes
   de continuar. Requiere actores reales Owner, Accounting y CONSULTANT efectivos;
   no inventa grants para conseguir que pase. Crea targets activos/inactivos temporales.
5. Desplegar este frontend y recargar sesion/cache. Verificar Owner, Accounting y
   tenant: mantenimiento/asignacion/activacion segun capabilities; ningun permiso
   transversal tenant para Accounting. Verificar deny y cambio de contexto fallido.

No se promete compatibilidad completa durante la ventana DB/frontend: la UI antigua
puede depender del bypass SUPERADMIN para SELECT transversal y del rol para mostrar
botones. Tras 033 esas lecturas se restringen, y la UI nueva necesita las RPC nuevas.
Mantener el catalogo fuera de uso hasta terminar el despliegue coordinado.

## Evidencia y riesgos residuales

Jest cubre comportamiento de store/UI/services con mocks y contratos SQL estaticos.
El test DB preparado cubre RLS real, ACL, Owner normalizado/grants previos,
Accounting sin ORG_VIEW/ACCESS_ANY_ORG, CONSULTANT MANAGE, overrides DENY,
activacion/desactivacion, historial TRUE/FALSE y destinos inactivos. No se ejecuto.
Los up/down tampoco se ejecutaron: no declarar DEV_RUNTIME_VERIFIED ni CLOSED.
La configuracion de Accounting anterior no se borra: grants/overrides excesivos
preexistentes se detectan en post-check/test y requieren una decision independiente.
Un snapshot de ACL restaura las concesiones anteriores, incluidas las que sean
mas amplias que las nuevas. Revisar drift de policies adicionales en el post-check.
Las RPC de estado son consultas paginadas: cambios concurrentes de asignacion
pueden requerir refrescar la vista; cada escritura vuelve a autorizar en SQL.

## Fuera de alcance

No se implementa delegacion de permisos ni analitica. ORG_MEMBER_PERMISSION_MANAGE
es distinto de permiso de uso; PLATFORM_PERMISSION_MANAGE sigue siendo una propuesta.
El futuro flujo de delegacion requiere conjunto delegable, alcance, no autoescalado,
auditoria y tratar quitar DENY como grant. SAAS_ANALYTICS_VIEW no equivale a
ACCESS_ANY_ORG. No se cambia HORECA ni se renombran organizaciones.
