/** Sequential requests; each server receipt is atomic, the file is not. */
export async function persistImportChunks(rpc, { importId, fileInfo, stagedRows, kind }) {
    if (!Array.isArray(stagedRows) || !stagedRows.length) throw new Error('No hay filas para persistir.');
    const count=Math.ceil(stagedRows.length/500);
    let result;
    try {
        for (let index=0;index<count;index++) {
            const {data,error}=await rpc('persist_import_chunk',{
                p_import_id:importId,p_file_info:fileInfo,p_staged_rows:stagedRows.slice(index*500,(index+1)*500),
                p_kind:kind,p_chunk_index:index,p_total_rows:stagedRows.length
            });
            if (error) throw new Error(`Error en lote ${index+1}/${count}: ${error.message}`);
            if (!data || data.import_id!==importId || data.next_chunk_index<index+1 ||
                (index===count-1 && (data.complete!==true || data.total_rows!==stagedRows.length)))
                throw new Error('Respuesta de lote incompleta o identidad de importación inválida.');
            result=data;
        }
        return result;
    } catch(error) {
        // A lost response may follow a committed transaction, even on the first request.
        error.preserveSourceFile=true;
        throw error;
    }
}
