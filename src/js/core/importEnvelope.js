export function validateImportEnvelope(data, expectedOrg = null) {
    const envelope = { ...data, import_id: data?.new_import_id || data?.import_id };
    const { import_id: id, organization_id: org, storage_prefix: prefix } = envelope;
    if (typeof id !== 'string' || !id || typeof org !== 'string' || !org ||
        typeof prefix !== 'string' || !prefix)
        throw new Error('Respuesta de importación incompleta: faltan import_id, organization_id o storage_prefix. No se subió el archivo.');
    const parts = prefix.split('/');
    if (parts.length !== 2 || parts[0] !== org || parts[1] !== id || (expectedOrg && org !== expectedOrg))
        throw new Error('La importación no corresponde a la organización activa. Volvé a seleccionar el archivo.');
    return Object.freeze(envelope);
}

export function assertImportResult(result) {
    if (!result || Number(result.accepted_rows || 0) + Number(result.duplicate_rows || 0) <= 0)
        throw new Error('La carga no produjo registros válidos. Revisá las incidencias del archivo antes de reintentar.');
}

export async function refreshDuplicateImport({ check, type, service, store, isCurrent }) {
    const evidence = await service.inspectImportedFile(check.existing_file_id);
    if (!isCurrent()) return null;
    if (evidence.organization_id !== store.activeOrganizationId) throw new Error('El contexto de importación cambió.');
    const modules = { recibido:'tab-conciliador', emitido:'tab-conciliador', percepcion:'tab-percepciones', banco:'tab-bancos', sueldo:'tab-sueldos' };
    await store.refreshOperationalData(modules[type]);
    if (!isCurrent()) return null;
    if (!evidence.active_rows) throw new Error(evidence.total_rows
        ? 'El archivo ya existe, pero sus registros están eliminados. Solicitá una restauración autorizada.'
        : 'Inconsistencia: el archivo figura importado pero no tiene registros derivados. No se duplicó ni reintentó.');
    return 'Este archivo ya había sido importado. Se muestran los datos existentes.';
}
