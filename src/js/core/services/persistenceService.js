import { supabase } from './supabaseClient.js';

/**
 * Servicio de Persistencia para MICA (Fase 2 - Supabase Staging)
 * Responsable de la integración de archivos, hashes, storage privado y RPCs.
 */
export class PersistenceService {

    async loadMyEffectiveCapabilities(orgId = null) {
        const { data, error } = await supabase.rpc('get_my_effective_capabilities', { p_org_id: orgId });
        if (error) throw new Error(error.message);
        if (!Array.isArray(data) || data.some(r => !r || typeof r.code !== 'string' ||
            !['PLATFORM', 'ORGANIZATION'].includes(r.scope) ||
            (r.scope === 'ORGANIZATION' && (!orgId || r.organization_id !== orgId)))) {
            throw new Error('Invalid effective capabilities response');
        }
        return data;
    }

    async listCatalogAssignmentTargets() {
        const { data, error } = await supabase.rpc('list_catalog_assignment_targets');
        if (error) throw new Error(error.message);
        if (!Array.isArray(data) || data.some(row => !row || typeof row.organization_id !== 'string' || typeof row.organization_name !== 'string')) throw new Error('Invalid catalog targets response');
        return data;
    }

    async listCatalogAssignmentState(catalogType) {
        const rows = [];
        // The catalog can have more assignment rows than PostgREST's response cap.
        // SQL orders by organization/item so adjacent pages are deterministic.
        for (;;) {
            const { data, error } = await supabase.rpc('list_catalog_assignment_state', { p_catalog_type: catalogType })
                .range(rows.length, rows.length + 499);
            if (error) throw new Error(error.message);
            if (!Array.isArray(data) || data.some(row => !row || typeof row.organization_id !== 'string' ||
                typeof row.item_id !== 'string' || typeof row.is_assigned !== 'boolean' || typeof row.is_active !== 'boolean')) {
                throw new Error('Invalid catalog assignment state response');
            }
            if (data.length === 0) return rows;
            rows.push(...data);
        }
    }

    async loadMyCatalogCapabilities() {
        const { data, error } = await supabase.rpc('get_my_catalog_capabilities').single();
        if (error) throw error;
        if (!data || ['global_catalog_manage', 'catalog_assign_any_org', 'access_any_org']
            .some(key => typeof data[key] !== 'boolean')) throw new Error('Invalid catalog capabilities response');
        return data;
    }

    get supabase() {
        return supabase;
    }

    /**
     * Calcula el hash SHA-256 de un archivo/blob mediante Web Crypto API.
     * Retorna una cadena hexadecimal en minúsculas de 64 caracteres.
     */
    async sha256File(file) {
        if (!file) throw new Error("Archivo es obligatorio para sha256File");
        const arrayBuffer = await file.arrayBuffer();
        const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        return hashHex.toLowerCase();
    }

    /**
     * Sanitiza el nombre del archivo para generar un path de Storage seguro.
     */
    getSafeFilename(originalName) {
        if (!originalName || typeof originalName !== 'string') {
            return `import_${Date.now()}.bin`;
        }
        
        const lastDot = originalName.lastIndexOf('.');
        let name = originalName;
        let ext = '';
        
        if (lastDot !== -1) {
            name = originalName.substring(0, lastDot);
            ext = originalName.substring(lastDot).toLowerCase();
        }

        const safeName = name
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '') // Quitar acentos
            .replace(/[^a-zA-Z0-9_.\-]/g, '_') // Quitar caracteres especiales
            .replace(/_+/g, '_')
            .substring(0, 100);

        const safeExt = ext.replace(/[^a-z0-9.]/g, '');
        return `${safeName || 'file'}${safeExt}`;
    }

    /**
     * Infiere un MIME type fallback si el navegador entrega file.type vacío.
     */
    getMimeTypeFallback(fileName, mimeType) {
        if (mimeType && mimeType.trim() !== '') {
            return mimeType;
        }
        
        const ext = (fileName || '').toLowerCase().split('.').pop();
        switch (ext) {
            case 'xls':
                return 'application/vnd.ms-excel';
            case 'xlsx':
                return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
            case 'csv':
                return 'text/csv';
            case 'txt':
                return 'text/plain';
            default:
                throw new Error(`Extensión no soportada para fallback MIME: .${ext}`);
        }
    }

    /**
     * Pre-check RPC para verificar si un archivo con el mismo Hash SHA-256 ya fue importado.
     */
    async checkFileImportable(hashHex) {
        const { data, error } = await supabase.rpc('check_file_importable', {
            p_sha256_hash: hashHex
        });

        if (error) {
            throw new Error(`Error en RPC check_file_importable: ${error.message}`);
        }

        return data;
    }

    /**
     * Inicia una importación en DB obteniendo import_id y storage_prefix autorizados.
     */
    async createImport(sourceType = 'ARCA_RECIBIDOS', operationType = 'COMPRA') {
        const { data, error } = await supabase.rpc('create_import', {
            p_source_type: sourceType,
            p_operation_type: operationType
        });

        if (error) {
            throw new Error(`Error en RPC create_import: ${error.message}`);
        }

        return data;
    }

    /**
     * Solicita reintento de una importación fallida reutilizando trazabilidad e import_id.
     */
    async requestFailedImportRetry(importId) {
        const { data, error } = await supabase.rpc('request_failed_import_retry', {
            p_import_id: importId
        });

        if (error) {
            throw new Error(`Error en RPC request_failed_import_retry: ${error.message}`);
        }

        return {
            import_id: data.new_import_id || data.import_id,
            organization_id: data.organization_id,
            storage_prefix: data.storage_prefix,
            ...data
        };
    }

    /**
     * Subida de archivo al bucket privado eco-imports-private-staging.
     */
    async uploadSourceFile({ file, storagePrefix, safeFilename, mimeType }) {
        if (!storagePrefix) throw new Error("storagePrefix es obligatorio para la subida");
        
        const targetPath = `${storagePrefix}/${safeFilename}`;
        const finalMime = this.getMimeTypeFallback(file.name, mimeType || file.type);

        const { data, error } = await supabase.storage
            .from('eco-imports-private-staging')
            .upload(targetPath, file, {
                contentType: finalMime,
                upsert: false
            });

        if (error) {
            throw new Error(`Error en Storage upload (${targetPath}): ${error.message}`);
        }

        return { path: data.path || targetPath, mimeType: finalMime };
    }

    /**
     * Intenta eliminar un archivo de Storage en caso de fallo durante la persistencia.
     */
    async cleanupStorageFile(storagePath) {
        try {
            await supabase.storage
                .from('eco-imports-private-staging')
                .remove([storagePath]);
        } catch (err) {
            console.error("Fallo durante cleanup compensatorio de Storage:", err);
        }
    }

    /**
     * Persiste el lote de importación en la base de datos mediante la RPC transaccional.
     */
    async persistImportBatch({ importId, fileInfo, stagedRows }) {
        const p_file_info = {
            original_name: fileInfo.original_name,
            storage_path: fileInfo.storage_path,
            mime_type: fileInfo.mime_type,
            size_bytes: fileInfo.size_bytes,
            sha256_hash: fileInfo.sha256_hash
        };

        const p_staged_rows = stagedRows.map(r => ({
            sourceRowNumber: r.sourceRowNumber,
            rawRow: r.rawRow || [],
            normalizedData: r.normalizedData || null,
            errors: r.errors || [],
            warnings: r.warnings || []
        }));

        const { data, error } = await supabase.rpc('persist_import_batch', {
            p_import_id: importId,
            p_file_info: p_file_info,
            p_staged_rows: p_staged_rows
        });

        if (error) {
            throw new Error(`Error en RPC persist_import_batch: ${error.message}`);
        }

        return data;
    }

    /**
     * Persiste el lote de percepciones (ARBA / IVA) en la base de datos mediante la RPC transaccional.
     */
    async persistPerceptionsBatch({ importId, fileInfo, stagedRows }) {
        const p_file_info = {
            original_name: fileInfo.original_name,
            storage_path: fileInfo.storage_path,
            mime_type: fileInfo.mime_type,
            size_bytes: fileInfo.size_bytes,
            sha256_hash: fileInfo.sha256_hash
        };

        const p_staged_rows = stagedRows.map(r => ({
            sourceRowNumber: r.sourceRowNumber,
            rawRow: r.rawRow || [],
            normalizedData: r.normalizedData || null,
            errors: r.errors || [],
            warnings: r.warnings || []
        }));

        const { data, error } = await supabase.rpc('persist_perceptions_batch', {
            p_import_id: importId,
            p_file_info: p_file_info,
            p_staged_rows: p_staged_rows
        });

        if (error) {
            throw new Error(`Error en RPC persist_perceptions_batch: ${error.message}`);
        }

        return data;
    }

    /**
     * Persiste el lote de movimientos financieros (Banco / Sueldos) en la base de datos mediante la RPC transaccional.
     */
    async persistFinancialMovementsBatch({ importId, fileInfo, stagedRows }) {
        const p_file_info = fileInfo ? {
            original_name: fileInfo.original_name || fileInfo.name,
            storage_path: fileInfo.storage_path || fileInfo.storagePath,
            mime_type: fileInfo.mime_type || fileInfo.type,
            size_bytes: fileInfo.size_bytes || fileInfo.size,
            sha256_hash: fileInfo.sha256_hash || fileInfo.sha256Hash
        } : null;

        const p_staged_rows = stagedRows.map(r => ({
            sourceRowNumber: r.sourceRowNumber,
            rawRow: r.rawRow || [],
            normalizedData: r.normalizedData || null,
            errors: r.errors || [],
            warnings: r.warnings || []
        }));

        const { data, error } = await supabase.rpc('persist_financial_movements_batch', {
            p_import_id: importId,
            p_file_info: p_file_info,
            p_staged_rows: p_staged_rows
        });

        if (error) {
            throw new Error(`Error en RPC persist_financial_movements_batch: ${error.message}`);
        }

        return data;
    }

    /**
     * Rehidrata los movimientos financieros activos del usuario desde DB.
     */
    async loadActiveFinancialMovements(rows = null) {
        const { data, error } = rows === null ? await supabase.rpc('get_active_financial_movements') : { data: rows };

        if (error) {
            throw new Error(`Error en RPC get_active_financial_movements: ${error.message}`);
        }

        if (!Array.isArray(data)) return [];

        return data.map(r => {
            const d = r.normalized_payload || {};
            return {
                id: r.id,
                organization_id: r.organization_id,
                sourceType: r.source_type,
                operationType: r.operation_type,
                fecha: r.fecha,
                fechaValor: r.fecha_valor,
                periodo: r.periodo,
                descripcion: r.descripcion,
                referencia: r.referencia,
                accountIdentifier: r.account_identifier,
                movementType: r.movement_type,
                monto: r.monto,
                saldo: r.saldo,
                identityKey: r.identity_key,
                financialFingerprint: r.financial_fingerprint,
                rawRecord: d
            };
        });
    }

    /**
     * Rehidrata los comprobantes fiscales (ARCA) activos del usuario desde DB.
     */
    async loadActiveFiscalRecords(rows = null) {
        const { data, error } = rows === null ? await supabase.rpc('get_active_normalized_records') : { data: rows };

        if (error) {
            throw new Error(`Error en RPC get_active_normalized_records: ${error.message}`);
        }

        if (!Array.isArray(data)) return [];

        return data
            .filter(r => 
                r.record_type === 'ARCA_RECIBIDOS' || r.record_type === 'ARCA_EMITIDOS' || 
                r.tipo_operacion === 'COMPRA' || r.tipo_operacion === 'VENTA'
            )
            .map(r => {
                const d = r.normalized_payload || {};
                const isCompra = r.tipo_operacion === 'COMPRA' || r.record_type === 'ARCA_RECIBIDOS';
                const cuitVal = r.cuit || d.cuit || '';
                const razonVal = r.razon_social || d.razonSocial || '';
                return {
                    id: r.id,
                    organization_id: r.organization_id,
                    fecha: d.fecha || r.fecha,
                    tipo: isCompra ? 'recibido' : 'emitido',
                    tipoOperacion: isCompra ? 'COMPRA' : 'VENTA',
                    tenant: cuitVal,
                    cuit: cuitVal,
                    razonSocial: razonVal,
                    proveedor: isCompra ? (razonVal || ("CUIT " + cuitVal)) : (razonVal || ("CUIT " + cuitVal)),
                    comprobante: r.comprobante || `${d.tipo_cbte}-${d.pdv}-${d.nroDesde}`,
                    tipo_cbte: d.tipo_cbte,
                    pdv: d.pdv,
                    nroDesde: d.nroDesde,
                    nroHasta: d.nroHasta || d.nroDesde,
                    moneda: d.moneda || 'PES',
                    tipoCambio: d.tipoCambio || 1,
                    total: typeof r.total === 'number' ? r.total : (d.total || 0),
                    importe: typeof r.total === 'number' ? r.total : (d.total || 0),
                    importeTotal: typeof r.total === 'number' ? r.total : (d.total || 0),
                    totalIva: d.totalIva || 0,
                    iva: d.totalIva || 0,
                    otrosTributos: d.otrosTributos || 0,
                    exento: d.exento || 0,
                    netoNoGravado: d.netoNoGravado || 0,
                    noGravado: d.netoNoGravado || 0,
                    netoGravado: d.netoGravado || 0,
                    alicuotas: d.alicuotas || [],
                    categoria: r.categoria || null,
                    sugerida: false,
                    confirmada: r.confirmada || false,
                    rawRecord: d
                };
            });
    }

    /**
     * Rehidrata las percepciones impositivas activas del usuario desde DB.
     */
    async loadActivePerceptions(rows = null) {
        const { data, error } = rows === null ? await supabase.rpc('get_active_normalized_records') : { data: rows };

        if (error) {
            throw new Error(`Error en RPC get_active_normalized_records: ${error.message}`);
        }

        if (!Array.isArray(data)) return [];

        return data
            .filter(r => {
                const rt = String(r.record_type || '').toUpperCase();
                const op = String(r.tipo_operacion || '').toUpperCase();
                return rt.includes('PERCEPCION') || rt === 'ARBA' || rt === 'IVA' || op === 'PERCEPCION';
            })
            .map(r => {
                const d = r.normalized_payload || {};
                return {
                    id: r.id,
                    organization_id: r.organization_id,
                    cuit: r.cuit || d.cuit || '',
                    razonSocial: r.razon_social || d.razonSocial || 'AGENTE PERCEPCION',
                    fecha: d.fecha || r.fecha,
                    period: d.period || d.periodo || r.periodo,
                    periodo: d.period || d.periodo || r.periodo,
                    regimen: d.regimen,
                    sucursal: d.sucursal,
                    comprobante: r.comprobante || d.comprobante,
                    monto: typeof r.total === 'number' ? r.total : (d.monto || d.amount || 0),
                    amount: typeof r.total === 'number' ? r.total : (d.amount || d.monto || 0),
                    jurisdiction: d.jurisdiction || (String(r.record_type).includes('ARBA') || r.record_type === 'ARBA' ? 'ARBA' : 'NACIONAL (IVA)'),
                    fuente: d.fuente || (String(r.record_type).includes('ARBA') || r.record_type === 'ARBA' ? 'ARBA' : 'IVA'),
                    tipo: 'percepcion',
                    rawRecord: d
                };
            });
    }

    /**
     * Obtiene registros eliminados lógicamente (Papelera)
     */
    async loadDeletedRecords() {
        const { data, error } = await supabase.rpc('get_deleted_normalized_records');
        if (error) throw new Error(`Error get_deleted_normalized_records: ${error.message}`);
        return data || [];
    }

    /**
     * Obtiene movimientos financieros eliminados lógicamente (Papelera)
     */
    async loadDeletedFinancialMovements() {
        const { data, error } = await supabase.rpc('get_deleted_financial_movements');
        if (error) throw new Error(`Error get_deleted_financial_movements: ${error.message}`);
        return data || [];
    }

    /**
     * Soft delete masivo de registros normalizados (Comprobantes y Percepciones)
     */
    async bulkSoftDeleteRecords(recordIds) {
        if (!recordIds || recordIds.length === 0) return;
        const results = await Promise.all(
            recordIds.map(id => supabase.rpc('soft_delete_normalized_record', { p_record_id: id }))
        );
        const err = results.find(r => r.error);
        if (err) throw new Error(`Error soft_delete_normalized_record: ${err.error.message}`);
    }

    /**
     * Soft delete masivo de movimientos financieros (Extractos Bancarios y Sueldos)
     */
    async bulkSoftDeleteFinancialMovements(movementIds) {
        if (!movementIds || movementIds.length === 0) return;
        const results = await Promise.all(
            movementIds.map(id => supabase.rpc('soft_delete_financial_movement', { p_movement_id: id }))
        );
        const err = results.find(r => r.error);
        if (err) throw new Error(`Error soft_delete_financial_movement: ${err.error.message}`);
    }

    /**
     * Restauración masiva de registros normalizados
     */
    async bulkRestoreRecords(recordIds) {
        if (!recordIds || recordIds.length === 0) return;
        const results = await Promise.all(
            recordIds.map(id => supabase.rpc('restore_normalized_record', { p_record_id: id }))
        );
        const err = results.find(r => r.error);
        if (err) throw new Error(`Error restore_normalized_record: ${err.error.message}`);
    }

    /**
     * Clasificación masiva
     */
    async bulkUpdateRecordClassification(recordIds, cuit, categoryId, activityId = null) {
        if (!recordIds || recordIds.length === 0) return;
        const { error } = await supabase.rpc('bulk_update_record_classification', {
            p_record_ids: recordIds,
            p_cuit: cuit,
            p_category_id: categoryId,
            p_activity_id: activityId
        });
        if (error) throw new Error(`Error bulk_update_record_classification: ${error.message}`);
    }

    /**
     * Cargar categorías tributarias activas asignadas a la org mediante SELECT directo con RLS
     */
    async loadActiveTaxCategories() {
        const { data, error } = await supabase
            .from('eco_org_tax_categories')
            .select('id, organization_id, is_assigned, is_active, created_at, category:eco_tax_categories(id, name, description, category_type, is_active)')
            .eq('is_assigned', true)
            .eq('is_active', true);
        if (error) throw new Error(`Error loadActiveTaxCategories: ${error.message}`);
        return (data || []).filter(item => item.category && item.category.is_active).map(item => ({
            id: item.category.id,
            organization_id: item.organization_id,
            name: item.category.name,
            description: item.category.description,
            category_type: item.category.category_type,
            is_active: item.is_active
        }));
    }

    /**
     * Cargar actividades económicas activas asignadas a la org mediante SELECT directo con RLS
     */
    async loadActiveEconomicActivities() {
        const { data, error } = await supabase
            .from('eco_org_economic_activities')
            .select('id, organization_id, is_assigned, is_active, created_at, activity:eco_economic_activities(id, arca_code, name, description, is_active)')
            .eq('is_assigned', true)
            .eq('is_active', true);
        if (error) throw new Error(`Error loadActiveEconomicActivities: ${error.message}`);
        return (data || []).filter(item => item.activity && item.activity.is_active).map(item => ({
            id: item.activity.id,
            organization_id: item.organization_id,
            arca_code: item.activity.arca_code,
            name: item.activity.name,
            description: item.activity.description,
            is_active: item.is_active
        }));
    }

    /**
     * Cargar catálogo global de actividades ARCA
     */
    async loadGlobalEconomicActivities() {
        const { data, error } = await supabase
            .from('eco_economic_activities')
            .select('*')
            .order('arca_code', { ascending: true });
        if (error) throw new Error(`Error loadGlobalEconomicActivities: ${error.message}`);
        return data || [];
    }

    /**
     * Asignar actividad económica a la organización
     */
    async assignEconomicActivityToOrg(activityId) {
        const { error } = await supabase.rpc('assign_economic_activity_to_org', {
            p_activity_id: activityId
        });
        if (error) throw new Error(`Error assignEconomicActivityToOrg: ${error.message}`);
    }

    /**
     * Desasignar actividad económica de la organización
     */
    async unassignEconomicActivityFromOrg(activityId) {
        const { error } = await supabase.rpc('unassign_economic_activity_from_org', {
            p_activity_id: activityId
        });
        if (error) throw new Error(`Error unassignEconomicActivityFromOrg: ${error.message}`);
    }

    /**
     * Cargar tasas IIBB activas de la organización
     */
    async loadActiveIibbRates() {
        const { data, error } = await supabase.rpc('get_active_org_iibb_rates');
        if (error) throw new Error(`Error get_active_org_iibb_rates: ${error.message}`);
        return data || [];
    }

    /**
     * Crear categoría global; asignar solo si se indica un destino explícito.
     */
    async createTaxCategory({ name, description = '', category_type = 'EXPENSE' }, targetOrgId = null) {
        if (!name || !name.trim()) {
            throw new Error('El nombre de la categoría es obligatorio.');
        }

        const { data: categoryId, error: createError } = await supabase.rpc('create_global_tax_category', {
            p_name: name.trim(),
            p_description: description ? description.trim() : '',
            p_category_type: category_type || 'EXPENSE'
        });
        if (createError) throw new Error(`Error al crear categoría tributaria: ${createError.message}`);

        if (targetOrgId) {
            const { error: assignError } = await supabase.rpc('assign_tax_category_to_org', {
                p_category_id: categoryId,
                p_custom_name: null,
                p_target_org_id: targetOrgId
            });
            if (assignError) throw new Error(`Error al asignar categoría a la organización: ${assignError.message}`);
        }

        return { id: categoryId, name: name.trim(), description: description ? description.trim() : '', category_type };
    }

    /**
     * Modificar categoría tributaria global (Semántica ADMIN)
     */
    async updateTaxCategory(categoryId, { name, description, is_active = true }) {
        const { error } = await supabase.rpc('update_global_tax_category', {
            p_category_id: categoryId,
            p_name: name,
            p_description: description,
            p_is_active: is_active
        });
        if (error) throw new Error(`Error updateTaxCategory: ${error.message}`);
    }

    /**
     * Asignar categoría tributaria para la organización actual
     */
    async assignTaxCategoryToOrg(categoryId) {
        const { error } = await supabase.rpc('assign_tax_category_to_org', {
            p_category_id: categoryId,
            p_custom_name: null
        });
        if (error) throw new Error(`Error assignTaxCategoryToOrg: ${error.message}`);
    }

    /**
     * Cargar lista de organizaciones registradas (para SUPERADMIN)
     */
    async loadOrganizations(organizationId = null) {
        if (organizationId) {
            const { data, error } = await supabase.from('eco_organizations')
                .select('id, name').eq('id', organizationId).maybeSingle();
            if (error) throw new Error(`loadOrganizations: ${error.message}`);
            if (!data) throw new Error('La organización activa no está disponible para esta sesión.');
            return [data];
        }
        const { data, error } = await supabase
            .from('eco_organizations')
            .select('id, name, created_at')
            .order('name', { ascending: true });
        if (error) {
            throw new Error(`loadOrganizations: ${error.message}`);
        }
        return data || [];
    }

    /**
     * Cambiar contexto organizacional para SUPERADMIN via RPC 017
     */
    async switchSuperadminOrgContext(orgId) {
        const { error } = await supabase.rpc('switch_superadmin_org_context', {
            p_org_id: orgId || null
        });
        if (error) throw new Error(error.message);
    }

    async listOperationalOrgTargets() {
        const rows = [];
        for (let offset = 0; ; offset += 500) {
            const { data, error } = await supabase.rpc('list_operational_org_targets').range(offset, offset + 499);
            if (error) throw new Error(error.message);
            if (!Array.isArray(data) || data.some(r => !r.organization_id || typeof r.organization_name !== 'string')) {
                throw new Error('Invalid operational targets response');
            }
            rows.push(...data);
            if (data.length === 0) return rows;
        }
    }

    async getOperationalContext() {
        const { data, error } = await supabase.rpc('get_my_operational_context');
        if (error) throw new Error(error.message);
        if (!data || !Object.hasOwn(data, 'organization_id') ||
            (data.organization_id !== null && (typeof data.organization_id !== 'string' || !data.organization_name))) {
            throw new Error('Invalid canonical context response');
        }
        return data;
    }

    async loadOperationalPages(rpcName, orgId) {
        const rows = [];
        let afterId = null;
        for (;;) {
            const { data, error } = await supabase.rpc(rpcName, {
                p_org_id: orgId, p_after_id: afterId, p_limit: 500
            });
            if (error) throw new Error(error.message);
            if (!Array.isArray(data) || data.length > 500 || data.some((r, i) =>
                r.organization_id !== orgId || typeof r.id !== 'string' || !r.id ||
                (i ? r.id <= data[i - 1].id : afterId !== null && r.id <= afterId))) {
                throw new Error(`Invalid tenant data or cursor: ${rpcName}`);
            }
            if (!data.length) return rows;
            rows.push(...data);
            afterId = data[data.length - 1].id;
            // Do not stop on a short page: PostgREST may impose a smaller row limit.
        }
    }

    async loadOperationalSnapshot(orgId, { catalogOnly = false } = {}) {
        const { data, error } = await supabase.rpc('get_operational_snapshot', { p_org_id: orgId });
        if (error) throw new Error(error.message);
        if (!data || data.organization_id !== orgId) throw new Error('Operational context mismatch');
        for (const key of ['categories', 'activities', 'rates']) {
            if (!Array.isArray(data[key]) || data[key].some(r => r.organization_id !== orgId)) {
                throw new Error(`Invalid tenant data: ${key}`);
            }
        }
        const catalogs = {
            taxCategories: data.categories.map(c => ({ ...c, isAssignedToOrg: true, assignedState: '' })),
            economicActivities: data.activities.filter(a => a.is_active),
            displayedEconomicActivities: data.activities,
            iibbRates: data.rates.map(r => ({ ...r, rate_percent: r.rate,
                activity_name: data.activities.find(a => a.id === r.activity_id)?.name || '' }))
        };
        if (catalogOnly) return catalogs;
        const [recordRows, financialRows] = await Promise.all([
            this.loadOperationalPages('get_operational_records_page', orgId),
            this.loadOperationalPages('get_operational_financials_page', orgId)
        ]);
        // UUID cursors bound server responses; preserve newest-first presentation after loading.
        const newestFirst = (a, b) => String(b.fecha || '').localeCompare(String(a.fecha || '')) || b.id.localeCompare(a.id);
        recordRows.sort(newestFirst);
        financialRows.sort(newestFirst);
        const [items, perceptions, financials] = await Promise.all([
            this.loadActiveFiscalRecords(recordRows), this.loadActivePerceptions(recordRows),
            this.loadActiveFinancialMovements(financialRows)
        ]);
        const financialRecord = f => ({ ...f.rawRecord, id: f.id, organization_id: orgId,
            periodo: f.periodo || f.rawRecord.periodo, fecha: f.rawRecord.fecha || f.fecha });
        return {
            items, perceptions,
            bankTransactions: financials.filter(f => f.operationType === 'BANCO').map(financialRecord),
            salariesList: financials.filter(f => f.operationType === 'SUELDO').map(f => {
                const s = financialRecord(f);
                return { ...s, sueldoBruto: s.sueldoBruto || s.sueldoBrutoCalculado || s.remunerativo || 0,
                    sueldoBrutoCalculado: s.sueldoBrutoCalculado || s.remunerativo || 0,
                    anticipos: s.anticipos || s.anticipoSueldo || 0, anticipoSueldo: s.anticipoSueldo || s.anticipos || 0,
                    sindicatoAporte: s.sindicatoAporte || s.aporteSindicalCalculado || s.aporteSindicalObligatorio || 0,
                    aporteSindicalCalculado: s.aporteSindicalCalculado || s.aporteSindicalObligatorio || 0,
                    sueldoNeto: s.sueldoNeto || 0, remunerativo: s.remunerativo || 0, noRemunerativo: s.noRemunerativo || 0 };
            }),
            ...catalogs
        };
    }

    /**
     * Asignar categoría tributaria para organización (propia o target)
     */
    async assignTaxCategoryToOrg(categoryId, targetOrgId = null) {
        const { error } = await supabase.rpc('assign_tax_category_to_org', {
            p_category_id: categoryId,
            p_target_org_id: targetOrgId || null
        });
        if (error) throw new Error(`Error assignTaxCategoryToOrg: ${error.message}`);
    }

    /**
     * Desasignar categoría tributaria para organización (propia o target)
     */
    async unassignTaxCategoryFromOrg(categoryId, targetOrgId = null) {
        const { error } = await supabase.rpc('unassign_tax_category_from_org', {
            p_category_id: categoryId,
            p_target_org_id: targetOrgId || null
        });
        if (error) throw new Error(`Error unassignTaxCategoryFromOrg: ${error.message}`);
    }

    /**
     * Asignar actividad económica para organización (propia o target)
     */
    async assignEconomicActivityToOrg(activityId, targetOrgId = null) {
        const { error } = await supabase.rpc('assign_economic_activity_to_org', {
            p_activity_id: activityId,
            p_target_org_id: targetOrgId || null
        });
        if (error) throw new Error(`Error assignEconomicActivityToOrg: ${error.message}`);
    }

    /**
     * Desasignar actividad económica para organización (propia o target)
     */
    async unassignEconomicActivityFromOrg(activityId, targetOrgId = null) {
        const { error } = await supabase.rpc('unassign_economic_activity_from_org', {
            p_activity_id: activityId,
            p_target_org_id: targetOrgId || null
        });
        if (error) throw new Error(`Error unassignEconomicActivityFromOrg: ${error.message}`);
    }

    /**
     * Importar catálogo ARCA por lotes seguros
     */
    async activateEconomicActivity(id) {
        const { error } = await supabase.rpc('activate_economic_activity', { p_activity_id: id });
        if (error) throw new Error(error.message);
    }

    async deactivateEconomicActivity(id) {
        const { error } = await supabase.rpc('deactivate_economic_activity', { p_activity_id: id });
        if (error) throw new Error(error.message);
    }

    async activateTaxCategory(id) {
        const { error } = await supabase.rpc('activate_tax_category', { p_category_id: id });
        if (error) throw new Error(error.message);
    }

    async deactivateTaxCategory(id) {
        const { error } = await supabase.rpc('deactivate_tax_category', { p_category_id: id });
        if (error) throw new Error(error.message);
    }

    async upsertArcaCatalog(activitiesJson) {
        if (!Array.isArray(activitiesJson) || activitiesJson.length === 0) {
            throw new Error('No hay actividades válidas para importar.');
        }
        const BATCH_SIZE = 200;
        let totalUpserted = 0;
        for (let i = 0; i < activitiesJson.length; i += BATCH_SIZE) {
            const batch = activitiesJson.slice(i, i + BATCH_SIZE);
            const { data, error } = await supabase.rpc('upsert_arca_activity_catalog', {
                p_activities: batch
            });
            if (error) throw new Error(`Error upsert_arca_activity_catalog: ${error.message}`);
            totalUpserted += (typeof data === 'number' ? data : batch.length);
        }
        return totalUpserted;
    }

    /**
     * CRUD IIBB Rates via M014 RPCs
     */
    async createIibbRate(payload) {
        const { data, error } = await supabase.rpc('create_org_activity_iibb_rate', {
            p_activity_id: payload.activity_id,
            p_jurisdiction: payload.jurisdiction,
            p_rate: payload.rate_percent,
            p_valid_from: payload.valid_from,
            p_valid_to: payload.valid_to || null
        });
        if (error) throw new Error(`Error createIibbRate: ${error.message}`);
        return data;
    }

    async updateIibbRate(rateId, payload) {
        const { data, error } = await supabase.rpc('update_org_activity_iibb_rate', {
            p_rate_id: rateId,
            p_rate: payload.rate_percent,
            p_valid_from: payload.valid_from,
            p_valid_to: payload.valid_to || null,
            p_is_active: payload.is_active !== undefined ? payload.is_active : true
        });
        if (error) throw new Error(`Error updateIibbRate: ${error.message}`);
        return data;
    }

    /**
     * Cargar errores de importación pendientes
     */
    async loadImportIssues() {
        const { data, error } = await supabase
            .from('eco_import_issues')
            .select('*')
            .order('created_at', { ascending: false });
        if (error) throw new Error(`Error loadImportIssues: ${error.message}`);
        return data || [];
    }
}

export const persistenceService = new PersistenceService();
