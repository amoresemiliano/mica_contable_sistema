// Product contract, not an authorization engine. Only effective server grants authorize.
// Proposed capabilities are documented here but never become assignable or grant authority.
export const MICA_PRESET_DEFINITIONS = Object.freeze({
    ROOT_TECHNICAL_MICA: { label: 'Root técnico MICA', scope: 'PLATFORM', structuralOwner: true },
    ACCOUNTING_SUPERADMIN: { label: 'Administración general MICA', scope: 'PLATFORM' },
    MICA_ORG_ADMIN: { label: 'Administrador de organización', scope: 'ORGANIZATION' },
    MICA_ACCOUNTANT: { label: 'Contador / operador contable', scope: 'ORGANIZATION' },
    MICA_IMPORT_OPERATOR: { label: 'Operador de importaciones', scope: 'ORGANIZATION' },
    MICA_READ_ONLY: { label: 'Consulta / auditor', scope: 'ORGANIZATION' }
});
export const PERMISSION_GROUPS = Object.freeze({
    platform: 'Administración MICA', organizations: 'Organizaciones', records: 'Comprobantes',
    perceptions: 'Percepciones', banks: 'Bancos', payroll: 'Sueldos', manual: 'Carga manual y OCR',
    catalogs: 'Categorización impositiva', reconciliation: 'Conciliación', reports: 'Reportes',
    sensitive: 'Datos sensibles', users: 'Usuarios y permisos', audit: 'Auditoría y soporte',
    purchases: 'Proveedores / compras', sales: 'Ventas', personnel: 'Personal', integrations: 'Integraciones'
});
export const SCOPE_LABELS = Object.freeze({ PLATFORM: 'MICA / Plataforma', ORGANIZATION: 'Organización / Empresa' });
export const PERMISSION_STATES = Object.freeze({ INHERITED: 'Heredado', ALLOW: 'Permitido', DENY: 'Denegado' });
const root = 'ROOT_TECHNICAL_MICA', mica = 'ACCOUNTING_SUPERADMIN';
const admin = 'MICA_ORG_ADMIN', accountant = 'MICA_ACCOUNTANT', importer = 'MICA_IMPORT_OPERATOR', auditor = 'MICA_READ_ONLY';
const everyone = [admin, accountant, importer, auditor], operators = [admin, accountant, importer], accounting = [admin, accountant];
// code, Spanish label, functional description, group, tenant defaults / reserved, MICA default
const platform = [
    ['DATA_RESTORE_ANY_ORG','Restaurar datos de empresas autorizadas','Restaurar con alcance, contexto confirmado y RECORD_RESTORE efectivo.','platform',false,true],
    ['MICA_ADMIN_MANAGE','Administrar usuarios y permisos MICA','Gestionar usuarios, presets y asignaciones dentro del alcance delegado.','users',false,true],
    ['PLATFORM_MANAGE','Administrar la plataforma técnica','Administración reservada del entorno técnico.','platform',true],
    ['GLOBAL_USER_MANAGE','Administrar identidades globales','Control reservado de identidades de la plataforma.','users',true],
    ['PLAN_MANAGE','Administrar planes','Administración técnica de planes de servicio.','platform',true],
    ['ACCESS_ANY_ORG','Acceder a cualquier organización','Permite seleccionar organizaciones; no concede acciones dentro de ellas.','organizations',true],
    ['SUPPORT_IMPERSONATE','Asistencia técnica excepcional','Facultad reservada de soporte; no sustituye la sesión de administración MICA.','platform',true],
    ['HARD_DELETE_EXCEPTIONAL','Eliminar definitivamente de forma excepcional','Eliminación irreversible, exclusiva del owner técnico.','platform',true],
    ['ORGANIZATION_CREATE','Crear organizaciones','Dar de alta una organización; reservado por el contrato vigente.','organizations',true],
    ['ORGANIZATION_UPDATE','Editar organizaciones','Editar datos de las organizaciones del alcance asignado.','organizations',false,true],
    ['ORGANIZATION_ARCHIVE','Archivar organizaciones','Desactivar organizaciones; reservado por el contrato vigente.','organizations',true],
    ['PLATFORM_MIGRATIONS_APPLY','Aplicar migraciones técnicas','Modificar la estructura técnica de la plataforma.','platform',true],
    ['PLATFORM_TENANTS_PROVISION','Provisionar entornos','Provisionar infraestructura y entornos técnicos.','platform',true],
    ['PLATFORM_SYSTEM_MONITOR','Supervisar el sistema','Consultar el estado técnico del sistema.','platform',true],
    ['GLOBAL_CATALOG_VIEW','Ver catálogos generales','Consultar los catálogos compartidos de MICA.','catalogs',false,true],
    ['GLOBAL_CATALOG_MANAGE','Administrar catálogos generales','Mantener los catálogos compartidos de MICA.','catalogs',false,true],
    ['CATALOG_ASSIGN_ANY_ORG','Asignar catálogos a empresas','Asignar elementos del catálogo a organizaciones autorizadas.','catalogs',false,true],
    ['RATE_MANAGE_ANY_ORG','Administrar tasas de empresas','Administrar tasas impositivas dentro del alcance autorizado.','catalogs',false,true],
    ['REPORT_COMPARE_SCOPED_ORGS','Comparar organizaciones','Consultar comparaciones entre organizaciones autorizadas; sin crear reportes nuevos.','reports',false,true],
    ['REPORT_CONSOLIDATED_SCOPED_ORGS','Ver reportes consolidados','Consultar reportes consolidados del alcance autorizado.','reports',false,true],
    ['SAAS_ANALYTICS_VIEW','Ver métricas de plataforma','Permiso existente de métricas; no implementa analítica nueva.','reports',false,true],
    ['AUDIT_PLATFORM_VIEW','Ver auditoría de MICA','Consultar eventos de auditoría de plataforma.','audit',false,true]
];
const organization = [
    ['ORG_VIEW','Ver categorías y actividades','Consultar el contexto de la empresa y sus categorías y actividades.','catalogs',everyone],
    ['ORG_SETTINGS_VIEW','Ver configuración de la empresa','Consultar la configuración de la organización.','organizations',[admin,accountant]],
    ['ORG_SETTINGS_MANAGE','Administrar configuración de la empresa','Modificar la configuración de la organización.','organizations',[admin]],
    ['ORG_MEMBER_VIEW','Ver usuarios de la empresa','Consultar los usuarios incorporados a la organización.','users',[admin]],
    ['ORG_MEMBER_INVITE','Incorporar usuarios','Incorporar usuarios existentes a la organización.','users',[admin]],
    ['ORG_MEMBER_MANAGE','Administrar usuarios de la empresa','Activar, desactivar y asignar perfiles a miembros.','users',[admin]],
    ['ORG_MEMBER_PERMISSION_MANAGE','Administrar permisos de la empresa','Gestionar permisos delegables de miembros sin superar la autoridad propia.','users',[admin]],
    ['IMPORT_VIEW','Ver historial de cargas','Consultar cargas e incidencias; requisito común de los importadores. No sustituye la lectura de registros.','records',everyone],
    ['IMPORT_CREATE','Crear / importar comprobantes','Requisito común de importación. Solo no habilita importadores, ni autoriza importación fiscal.','records',operators],
    ['IMPORT_RETRY','Reintentar carga','Reintentar una carga autorizada por su tipo de importación.','records',operators],
    ['IMPORT_REVIEW','Revisar cargas e incidencias','Revisar la información y las incidencias de una carga.','records',operators],
    ['RECORD_VIEW','Ver comprobantes','Lectura compartida de comprobantes, percepciones, bancos, sueldos y movimientos manuales en el contrato vigente.','records',everyone],
    ['RECORD_CLASSIFY','Clasificar comprobantes','Editar la clasificación de comprobantes y movimientos existentes.','records',accounting],
    ['RECORD_SOFT_DELETE','Eliminar lógicamente','Ocultar registros sin destruirlos: comprobantes, percepciones, bancos y sueldos persistidos. Manuales pendientes de backend.','records',accounting],
    ['RECORD_RESTORE','Restaurar registros eliminados','Restauración operativa MICA dentro del contexto de empresa; no se incluye en presets tenant nuevos.','records',[]],
    ['PERCEPTION_IMPORT','Importar percepciones','Importar percepciones con lectura de registros y requisitos comunes de importación.','perceptions',operators],
    ['BANK_IMPORT','Importar extractos','Importar extractos bancarios con lectura y requisitos comunes.','banks',operators],
    ['PAYROLL_IMPORT','Importar liquidaciones','Importar liquidaciones de sueldos con lectura y requisitos comunes.','payroll',operators],
    ['ISSUE_RESOLVE','Resolver incidencias','Resolver incidencias de cargas y registros.','reconciliation',accounting],
    ['CATALOG_ORG_VIEW','Ver tasas y catálogos asignados','Consultar tasas y catálogos asignados a la empresa.','catalogs',everyone],
    ['CATALOG_ACTIVITY_MANAGE','Administrar actividades','Gestionar actividades económicas de la organización.','catalogs',accounting],
    ['CATALOG_CATEGORY_MANAGE','Administrar categorías','Gestionar categorías impositivas de la organización.','catalogs',accounting],
    ['REPORT_VIEW','Ver reportes, resultados y resumen impositivo','Consultar las vistas de reportes ya existentes.','reports',[admin,accountant,auditor]],
    ['REPORT_EXPORT','Exportar reportes','Exportar reportes de la organización.','reports',[admin,accountant,auditor]],
    ['TICKET_CREATE','Crear solicitud de soporte','Solicitar asistencia para la organización.','audit',operators],
    ['TICKET_VIEW_ORG','Ver solicitudes de soporte','Consultar solicitudes de la organización.','audit',everyone],
    ['AUDIT_VIEW_ORG','Ver auditoría de la empresa','Consultar eventos de auditoría de la organización.','audit',[admin,accountant,auditor]],
    ['FINANCIAL_ALLOCATION_EDIT','Editar imputaciones y asignaciones','Editar imputaciones financieras; no equivale a una confirmación de conciliación.','reconciliation',accounting],
    ['SENSITIVEDATA_BANKING_READ','Ver información bancaria sensible','Acceso al permiso específico de información bancaria sensible.','sensitive',accounting],
    ['SENSITIVEDATA_SALARIES_READ','Ver información salarial sensible','Acceso al permiso específico de información salarial sensible.','sensitive',accounting],
    ['DOCUMENTS_UPLOAD','Subir documentos','Vía OCR dentro de carga manual; inhabilitada hasta disponer de backend real.','manual',accounting],
    ['DOCUMENTS_OCR_PROCESS','Procesar con OCR','Procesar documentos con un backend real, todavía pendiente.','manual',accounting],
    ['DOCUMENTS_OCR_VERIFY','Verificar OCR','Revisar una extracción real; no habilita su incorporación sin backend.','manual',accounting]
];
const approved039b = [
    ["PURCHASES_INVOICES_MANAGE","Gestionar comprobantes de compras","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","purchases", []],
    ["SUPPLIERS_VIEW","Ver proveedores","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","purchases", []],
    ["SUPPLIERS_MANAGE","Administrar proveedores","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","purchases", []],
    ["SALES_VIEW","Ver comprobantes de ventas","Permiso MICA aprobado; la vista compartida actual sigue requiriendo RECORD_VIEW.","sales", []],
    ["PERSONNEL_EMPLOYEES_MANAGE","Administrar empleados","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","personnel", []],
    ["INTEGRATIONS_CONFIG_MANAGE","Configurar integraciones","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","integrations", []],
    ["INTEGRATIONS_SYNC_TRIGGER","Ejecutar sincronizaciones","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","integrations", []],
    ["MANUAL_MOVEMENT_VIEW","Ver movimientos manuales","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","manual", accounting],
    ["MANUAL_MOVEMENT_CREATE","Crear movimientos manuales","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","manual", accounting],
    ["MANUAL_MOVEMENT_EDIT","Editar movimientos manuales","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","manual", accounting],
    ["MANUAL_MOVEMENT_SOFT_DELETE","Eliminar lógicamente movimientos manuales","Permiso MICA aprobado y asignable; su backend operativo sigue pendiente.","manual", accounting]
];
const proposed = [
    ['FISCAL_DOCUMENT_IMPORT','Importar comprobantes fiscales','Capability específica propuesta para recibidos y emitidos; endpoints siguen cerrados.','records'],
    ['DOCUMENTS_OCR_CONFIRM','Incorporar comprobante verificado','Confirmar la incorporación de un documento extraído; pendiente de backend.','manual'],
    ['RECONCILIATION_VIEW','Revisar conciliaciones','Propuesta de lectura específica de conciliaciones; sin módulo nuevo en esta fase.','reconciliation'],
    ['RECONCILIATION_CONFIRM','Confirmar conciliaciones','Confirmación de conciliaciones propuesta; no se infiere de clasificar.','reconciliation'],
    ['DATA_SOFT_DELETE','Eliminar datos lógicamente','Propuesta genérica diferida; RECORD_SOFT_DELETE sigue como implementación.','records'],
];
function entry(row, scope, status, index) {
    const [code,label,description,group,defaults,micaDefault] = row;
    const ownerReserved = scope === 'PLATFORM' && defaults === true;
    const defaultPresets = status === 'PROPOSED' ? [] : scope === 'PLATFORM'
        ? [root,...(micaDefault ? [mica] : [])] : [root,mica,...defaults];
    return Object.freeze({ code, label, description, group, scope, status, ownerReserved,
        delegationClass: ownerReserved ? 'OWNER_RESERVED' : scope + '_DELEGABLE',
        runtimeStatus: status === 'PROPOSED' || approved039b.some(r=>r[0]===code) || code.startsWith('DOCUMENTS_') ||
            ['REPORT_COMPARE_SCOPED_ORGS','REPORT_CONSOLIDATED_SCOPED_ORGS','SAAS_ANALYTICS_VIEW'].includes(code)
            ? 'DISABLED_PENDING_BACKEND' : 'ACTIVE',
        assignable: status !== 'PROPOSED' && !ownerReserved,
        visibleInEditor: status !== 'PROPOSED' && !ownerReserved,
        order: index, defaultPresets: Object.freeze(defaultPresets),
        delegationTargets: Object.freeze(code === 'RECORD_RESTORE' ? ['PLATFORM_BRIDGE'] : ['STANDARD','PLATFORM_BRIDGE']) });
}
export const MICA_PERMISSION_CATALOG_039B = Object.freeze([
    ...platform.map((r,i)=>entry(r,'PLATFORM',['MICA_ADMIN_MANAGE','DATA_RESTORE_ANY_ORG'].includes(r[0])?'PREPARED_039B':'CURRENT',i)),
    ...organization.map((r,i)=>entry(r,'ORGANIZATION','CURRENT',100+i)),
    ...approved039b.map((r,i)=>entry(r,'ORGANIZATION','PREPARED_039B',150+i)),
    ...proposed.map((r,i)=>entry(r,'ORGANIZATION','PROPOSED',200+i))
]);
// Frozen 039b projection keeps applied migration artifacts reproducible.
export const MICA_PERMISSION_CATALOG = Object.freeze(MICA_PERMISSION_CATALOG_039B.map(c => {
    if (c.code === 'FISCAL_DOCUMENT_IMPORT') return Object.freeze({ ...c,
        description: 'Importar comprobantes ARCA emitidos y recibidos con el pipeline fiscal.',
        status: 'PREPARED_039C', runtimeStatus: 'ACTIVE', assignable: true, visibleInEditor: true,
        defaultPresets: Object.freeze([root,mica,...operators]) });
    if (c.code.startsWith('MANUAL_MOVEMENT_')) return Object.freeze({ ...c,
        description: 'Carga manual persistente en la organización activa.', runtimeStatus: 'ACTIVE' });
    return c;
}));
export const permissionByCode = code => MICA_PERMISSION_CATALOG.find(c=>c.code===code);
// Several business functions share a legacy approved capability. These are explanations,
// not extra grants or independently assignable capabilities.
export const MICA_BUSINESS_FUNCTIONS = Object.freeze([
    {label:'Ver percepciones',group:'perceptions',capability:'RECORD_VIEW'},
    {label:'Ver movimientos bancarios',group:'banks',capability:'RECORD_VIEW'},
    {label:'Ver información de sueldos',group:'payroll',capability:'RECORD_VIEW'},
    {label:'Ver movimientos manuales',group:'manual',capability:'RECORD_VIEW'},
    {label:'Ver resultados',group:'reports',capability:'REPORT_VIEW'},
    {label:'Ver resumen impositivo',group:'reports',capability:'REPORT_VIEW'},
    {label:'Ver comprobantes de ventas',group:'sales',capability:'RECORD_VIEW'}
]);
export function presetCapabilities(preset, scope) {
    return MICA_PERMISSION_CATALOG.filter(c=>c.scope===scope && c.defaultPresets.includes(preset)).map(c=>c.code);
}
export const MICA_MODULE_CONTRACT = Object.freeze({
    'tab-conciliador': {label:'Comprobantes',any:['RECORD_VIEW'],datasets:['records']},
    'tab-percepciones': {label:'Percepciones',any:['RECORD_VIEW'],datasets:['records']},
    'tab-bancos': {label:'Bancos',any:['RECORD_VIEW'],datasets:['financials']},
    'tab-sueldos': {label:'Sueldos',any:['RECORD_VIEW'],datasets:['financials']},
    'tab-movimientos-manuales': {label:'Carga manual y OCR',any:['MANUAL_MOVEMENT_VIEW','RECORD_VIEW','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY'],datasets:['records','financials']},
    'tab-client-dashboard': {label:'Reportes',any:['REPORT_VIEW'],datasets:['records','financials']},
    'tab-categorizacion': {label:'Categorización impositiva',any:['ORG_VIEW','CATALOG_ORG_VIEW']}
});
export const MICA_IMPORT_CONTRACT = Object.freeze({
    percepcion: {all:['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','PERCEPTION_IMPORT'],enabled:true},
    banco: {all:['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','BANK_IMPORT'],enabled:true},
    sueldo: {all:['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','PAYROLL_IMPORT'],enabled:true},
    recibido: {all:['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','FISCAL_DOCUMENT_IMPORT'],enabled:true},
    emitido: {all:['RECORD_VIEW','IMPORT_VIEW','IMPORT_CREATE','FISCAL_DOCUMENT_IMPORT'],enabled:true}
});
export const MICA_OCR_ACTIONS = Object.freeze({upload:'DOCUMENTS_UPLOAD',process:'DOCUMENTS_OCR_PROCESS',verify:'DOCUMENTS_OCR_VERIFY'});
export const MICA_ACTION_CONTRACT = Object.freeze({
    classify: {all:['RECORD_VIEW','RECORD_CLASSIFY'],enabled:true},
    softDelete: {all:['RECORD_VIEW','RECORD_SOFT_DELETE'],enabled:true},
    restore: {all:['RECORD_VIEW','RECORD_RESTORE'],platformAll:['DATA_RESTORE_ANY_ORG'],enabled:true},
    export: {all:['RECORD_VIEW','REPORT_EXPORT'],enabled:true},
    manualCreate: {all:['MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE'],enabled:true},
    manualEdit: {all:['MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_EDIT'],enabled:true},
    manualSoftDelete: {all:['MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_SOFT_DELETE'],enabled:true}
});
export const MICA_METHOD_ACTIONS = Object.freeze({confirmItem:'classify',promptBulkClassification:'classify',
    promptBankBulkClassification:'classify',bulkSoftDeleteSelected:'softDelete',
    bulkSoftDeleteSelectedPercepciones:'softDelete',bulkSoftDeleteBankMovements:'softDelete'});
