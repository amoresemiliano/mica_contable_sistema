import { supabase } from './supabaseClient.js';

/**
 * Servicio de Persistencia para MICA (Fase 2 - Supabase Staging)
 * Responsable de la integración de archivos, hashes, storage privado y RPCs.
 */
export class PersistenceService {

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
    async loadActiveFinancialMovements() {
        const { data, error } = await supabase.rpc('get_active_financial_movements');

        if (error) {
            throw new Error(`Error en RPC get_active_financial_movements: ${error.message}`);
        }

        if (!Array.isArray(data)) return [];

        return data.map(r => {
            const d = r.normalized_payload || {};
            return {
                id: r.id,
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
    async loadActiveFiscalRecords() {
        const { data, error } = await supabase.rpc('get_active_normalized_records');

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
    async loadActivePerceptions() {
        const { data, error } = await supabase.rpc('get_active_normalized_records');

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
     * Soft delete masivo de registros normalizados
     */
    async bulkSoftDeleteRecords(recordIds) {
        if (!recordIds || recordIds.length === 0) return;
        const { error } = await supabase.rpc('bulk_soft_delete_records', {
            p_record_ids: recordIds
        });
        if (error) throw new Error(`Error bulk_soft_delete_records: ${error.message}`);
    }

    /**
     * Restauración masiva de registros normalizados
     */
    async bulkRestoreRecords(recordIds) {
        if (!recordIds || recordIds.length === 0) return;
        const { error } = await supabase.rpc('bulk_restore_records', {
            p_record_ids: recordIds
        });
        if (error) throw new Error(`Error bulk_restore_records: ${error.message}`);
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
            .select('id, organization_id, is_active, created_at, category:eco_tax_categories(id, name, description, category_type, is_active)')
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
            .select('id, organization_id, is_active, created_at, activity:eco_economic_activities(id, arca_code, name, description, is_active)')
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
     * Crear categoría tributaria global y asignarla a la organización activa
     */
    async createTaxCategory({ name, description = '', category_type = 'EXPENSE' }) {
        if (!name || !name.trim()) {
            throw new Error('El nombre de la categoría es obligatorio.');
        }

        const { data: categoryId, error: createError } = await supabase.rpc('create_global_tax_category', {
            p_name: name.trim(),
            p_description: description ? description.trim() : '',
            p_category_type: category_type || 'EXPENSE'
        });
        if (createError) throw new Error(`Error al crear categoría tributaria: ${createError.message}`);

        const { error: assignError } = await supabase.rpc('assign_tax_category_to_org', {
            p_category_id: categoryId,
            p_custom_name: null
        });
        if (assignError) throw new Error(`Error al asignar categoría a la organización: ${assignError.message}`);

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
     * Asignar/Reactivar categoría tributaria para la organización actual
     */
    async assignTaxCategoryToOrg(categoryId) {
        const { error } = await supabase.rpc('assign_tax_category_to_org', {
            p_category_id: categoryId,
            p_custom_name: null
        });
        if (error) throw new Error(`Error assignTaxCategoryToOrg: ${error.message}`);
    }

    /**
     * Desactivar/Desasignar categoría tributaria para la organización actual
     */
    async unassignTaxCategoryFromOrg(categoryId) {
        const { error } = await supabase.rpc('unassign_tax_category_from_org', {
            p_category_id: categoryId
        });
        if (error) throw new Error(`Error unassignTaxCategoryFromOrg: ${error.message}`);
    }

    /**
     * Importar catálogo ARCA por lotes seguros
     */
    async upsertArcaCatalog(activitiesJson) {
        if (!Array.isArray(activitiesJson) || activitiesJson.length === 0) {
            throw new Error('No hay actividades válidas para importar.');
        }
        const BATCH_SIZE = 200;
        for (let i = 0; i < activitiesJson.length; i += BATCH_SIZE) {
            const batch = activitiesJson.slice(i, i + BATCH_SIZE);
            const { error } = await supabase.rpc('upsert_arca_activity_catalog', {
                p_activities: batch
            });
            if (error) throw new Error(`Error upsert_arca_activity_catalog: ${error.message}`);
        }
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
