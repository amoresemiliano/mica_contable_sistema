# 038 — Administración MICA Contable Argentina

Estado: IMPLEMENTED; validación estática y harness DB preparado. Ningún SQL ejecutado.
Único proyecto previsto: `ourzapkjykzlwsjunzmd`.

## Diseño mínimo

Dos RPC públicas, SECURITY DEFINER, search_path vacío, EXECUTE sólo authenticated.
El rol SQL authenticated no autoriza acciones por sí mismo:

| RPC | Contrato |
| --- | --- |
| `mica_admin_read(p_org uuid default null, p_search text default '') -> jsonb` | Derechos de secciones, organizaciones, usuarios, presets registrados, asignaciones y overrides. Proyecciones explícitas; 200 usuarios por búsqueda y 250 organizaciones. |
| `mica_admin_apply(p_action text, p_data jsonb) -> uuid` | Mutación validada y auditada; acciones organization, preset, user, platform_role, membership, scope, override. |

| Acción | Autoridad |
| --- | --- |
| Crear / actualizar / activar-archivar organización | ORGANIZATION_CREATE / ORGANIZATION_UPDATE / ORGANIZATION_ARCHIVE. UPDATE no-root exige scope explícito. Defaults CUIT / AR / ARS / America/Argentina/Buenos_Aires. |
| Perfil: aprobar / activar / desactivar | GLOBAL_USER_MANAGE. Asignación activa previa; nunca root ni autoedición. |
| Preset global (PLATFORM o ORGANIZATION) | PLATFORM_MANAGE. Sólo capabilities MICA activas y delegables. |
| Preset propio del tenant | ORG_MEMBER_PERMISSION_MANAGE y contexto confirmado; no permite delegar acciones que el actor no posee. |
| Membership tenant | ORG_MEMBER_MANAGE + ORG_MEMBER_PERMISSION_MANAGE; INVITE para una membership nueva. GLOBAL_USER_MANAGE también permite esta administración global explícita, pero exige contexto tenant coincidente y activo. |
| Rol plataforma / scopes / override plataforma o platform-org | GLOBAL_USER_MANAGE; no genera memberships. |
| Override membership | ORG_MEMBER_PERMISSION_MANAGE, contexto y capacidad delegable efectiva, o GLOBAL_USER_MANAGE con contexto confirmado. |

ACCESS_ANY_ORG no autoriza estas acciones. No se modifica can_org, can_platform ni
can_operate_mica_org. DENY/ALLOW siguen resolviéndose por 036/037. Marianela usa
sus grants delegables, sin equipararla al root técnico.

Presets: registro privado `eco_mica_presets` distingue los presets creados desde
038 de templates históricos. Los históricos siguen funcionando, pero no se editan
ni se reasignan desde este editor. Para administrar un preset existente se crea
uno MICA explícito y se asigna; no hay importación automática ni rol por usuario.
Editar un preset compartido exige confirmar el número de destinatarios actual;
scope y organización son inmutables. Root y presets que lo afectan quedan protegidos.
Las mutaciones 038 se serializan con advisory lock y producen eventos MICA_ADMIN_*.

## Registro y aprobación

Se conserva el trigger existente de Auth; se reemplaza sólo su función
`public.handle_new_user()`. El registro crea un perfil inactivo, sin organización,
grants, membership ni contexto. USER es únicamente una etiqueta de compatibilidad.
La persona se registra por el acceso habitual; 038 no crea contraseñas ni envía
invitaciones de Auth. El administrador asigna preset/ámbito y luego aprueba.

Al aprobar por primera vez, el tenant recibe contexto de su membership; si hay
varias, se exige elegir la inicial. El usuario plataforma comienza en Plataforma.
Los perfiles existentes no se migran ni desactivan. El registro privado de pendientes
sólo corresponde a altas posteriores a 038.

## Preflight y rollback

El repo no contiene la definición anterior de handle_new_user. El UP conserva la
definición y ACL LIVE exactas antes del reemplazo. Su preflight exige la firma
trigger, owner postgres, ejecución por su owner, SECURITY DEFINER, VOLATILE y
proconfig NULL, conforme a la evidencia LIVE recibida. Exige on_auth_user_created
como único trigger AFTER INSERT por fila en auth.users,
organization_id nullable y ausencia de columnas obligatorias desconocidas en profiles.
Exige 037/037a aplicadas y que el guard instalado coincida con el hotfix.

La evidencia recibida describe el comportamiento previo (alta activa y bootstrap
por allowlist), pero no incluye el texto completo ni su hash: no se afirma una
comparación byte a byte del cuerpo. El reemplazo no consulta ni modifica esa
allowlist y elimina todos los grants EXECUTE a roles distintos del owner del
trigger, incluidos grants particulares anteriores. La aprobación posterior se
realiza por mica_admin_apply. Los seis usuarios existentes no se reinsertan ni
se modifican por aplicar el UP; el trigger sólo procesa nuevas altas Auth.

Las demás condiciones de esquema deben verificarse en la aplicación manual.
Ante drift, aborta la transacción. Las migraciones
anteriores permanecen intactas.

El DOWN verifica definición, owner y ACL instalados, restaura el trigger histórico
y los permisos anteriores (equivalentes incluso si la ACL original era implícita).
Luego elimina sólo las RPC/helpers y tablas privadas de 038, sin CASCADE.
Conserva perfiles, organizaciones, templates, grants y auditoría creados durante
el uso: es rollback de la API, no reversión de decisiones de negocio.
Eliminar el registro privado deja esos presets fuera del editor tras una reaplicación.
El trigger histórico restaurado vuelve a tener su comportamiento anterior.

## Diagnóstico estático de categorizer

categorizer.js exporta una instancia de CategorizationEngine con setContext.
store.js importa esa instancia y la llama desde clearTenantState y
loadTenantPreferences. parser.js importa la misma instancia; no hay reasignaciones
en el código revisado ni dependencias circulares en categorizer.js.
La versión anterior al commit 5aa1cb5 carecía de setContext: un store nuevo con
ese archivo antiguo reproduciría exactamente el TypeError reportado.
Es una explicación compatible con caché/despliegue parcial, no una causa LIVE
demostrada. No se modificó frontend en este cierre. Propuesta separada mínima:
publicar versiones coherentes de ambos módulos y revalidar/versionar sus recursos
en el despliegue. No omitir setContext con optional chaining: perdería la limpieza
del estado por tenant.

## Frontend y límites

Configuración reemplaza sus filas mock por cuatro secciones autorizadas por servidor.
Los textos se insertan con textContent. Se bloquea el cambio de contexto durante
mutaciones y se descartan lecturas tardías; después de guardar se recargan contexto,
capabilities y destinos del selector.

El editor muestra inherited / ALLOW / DENY y una previsión efectiva de la asignación
seleccionada en ámbito activo; no sustituye al chequeo runtime de contexto de 037.
No calcula presets históricos desconocidos. OCR permanece en el contrato MICA.
No se modifica visibilidad general de módulos, import boxes ni bloqueo de importación
por ACCESS_ANY_ORG. Esas validaciones siguen correspondiendo a 039.

## Validación manual preparada

1. Revisar y aplicar 038 sólo en MICA, después de 037a. El agente no la ejecutó.
2. Ejecutar completo tests/db/038_mica_administration.sql: BEGIN/ROLLBACK,
   alta Auth pendiente, permisos de root/delegado, scopes sin membership,
   ALLOW/DENY, preset scope, aislamiento y protección del root.
3. En Configuración, crear organización y comprobar que aparece en el selector;
   crear preset reutilizable, registrar usuario, asignar membership y aprobar.
4. Entrar con ese usuario: contexto inicial correcto; modificar un override y
   verificar permisos tras recarga. Un manager no puede administrar otro tenant.
5. Verificar que ninguna capability reservada o ajena aparece en el editor y que
   OCR sí está disponible en presets ORGANIZATION.
