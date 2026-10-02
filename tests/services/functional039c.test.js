import { jest } from '@jest/globals';
import { initializeWithSessionRecovery } from '../../src/js/core/sessionRecovery.js';
import { validateImportEnvelope, refreshDuplicateImport, assertImportResult } from '../../src/js/core/importEnvelope.js';
import { createAdministrationService } from '../../src/js/core/services/administrationService.js';
import { MICA_IMPORT_CONTRACT, presetCapabilities } from '../../src/js/core/micaPermissionContract.js';
import { canImport } from '../../src/js/core/moduleAccess.js';
import { manualRequest } from '../../src/js/manualMovements.js';

const session={user:{id:'user'}};
test('empty persistence results do not pretend a successful import',()=>{
    expect(()=>assertImportResult({accepted_rows:0,duplicate_rows:0,invalid_rows:5})).toThrow('no produjo');
    expect(()=>assertImportResult({accepted_rows:1,duplicate_rows:0})).not.toThrow();
    expect(()=>assertImportResult({accepted_rows:0,duplicate_rows:1})).not.toThrow();
});
test('future JWT refreshes session and automatically recovers with bounded backoff',async()=>{
    const initialize=jest.fn().mockRejectedValueOnce(new Error('JWT issued at future')).mockResolvedValue();
    const auth={refreshSession:jest.fn(async()=>({data:{session}}))},wait=jest.fn(async()=>{});
    await initializeWithSessionRecovery({session,auth,initialize,wait});
    expect(initialize).toHaveBeenCalledTimes(2); expect(auth.refreshSession).toHaveBeenCalledTimes(1);
    expect(wait).toHaveBeenCalledWith(400);
});
test('future JWT exhaustion is finite and preserves the real error',async()=>{
    const error=new Error('JWT issued at future'),initialize=jest.fn(async()=>{throw error;});
    const auth={refreshSession:async()=>({data:{session}}),getSession:async()=>({data:{session}})};
    await expect(initializeWithSessionRecovery({session,auth,initialize,wait:async()=>{}})).rejects.toBe(error);
    expect(initialize).toHaveBeenCalledTimes(4);
});
test.each(['JWT expired','Invalid JWT','permission denied'])('other error %s is immediately visible',async(message)=>{
    const auth={refreshSession:jest.fn()},initialize=jest.fn(async()=>{throw Error(message);});
    await expect(initializeWithSessionRecovery({session,auth,initialize})).rejects.toThrow(message);
    expect(auth.refreshSession).not.toHaveBeenCalled();expect(initialize).toHaveBeenCalledTimes(1);
});
test('logout during backoff cancels initialization and session refresh',async()=>{
    let current=true;const auth={refreshSession:jest.fn()},initialize=jest.fn(async()=>{throw Error('JWT issued at future');});
    await initializeWithSessionRecovery({session,auth,initialize,isCurrent:()=>current,wait:async()=>{current=false;}});
    expect(auth.refreshSession).not.toHaveBeenCalled();
});
test.each(['old-org','new-org'])('normal and retry envelopes use server prefix in %s',org=>{
    expect(validateImportEnvelope({import_id:'i',organization_id:org,storage_prefix:org+'/i'},org).import_id).toBe('i');
    expect(validateImportEnvelope({new_import_id:'retry',organization_id:org,storage_prefix:org+'/retry'},org).import_id).toBe('retry');
});
test('missing prefix fails early, and mixed organizations/import IDs cannot upload',()=>{
    expect(()=>validateImportEnvelope({import_id:'i',organization_id:'org'})).toThrow('storage_prefix');
    expect(()=>validateImportEnvelope({import_id:'i',organization_id:'org',storage_prefix:'other/i'})).toThrow('organización');
    expect(()=>validateImportEnvelope({import_id:'i',organization_id:'org',storage_prefix:'org/other'})).toThrow('organización');
    expect(()=>validateImportEnvelope({import_id:'i',organization_id:'org',storage_prefix:'org/i'},'other')).toThrow('organización');
});
test.each(Object.keys(MICA_IMPORT_CONTRACT))('%s duplicate reloads existing data without a new import',async type=>{
    const store={activeOrganizationId:'org',refreshOperationalData:jest.fn(async()=>{})};
    const service={inspectImportedFile:jest.fn(async()=>({organization_id:'org',total_rows:2,active_rows:2})),createImport:jest.fn()};
    const message=await refreshDuplicateImport({check:{existing_file_id:'file'},type,service,store,isCurrent:()=>true});
    expect(message).toContain('Se muestran los datos existentes');expect(store.refreshOperationalData).toHaveBeenCalledTimes(1);
    expect(service.createImport).not.toHaveBeenCalled();
});
test.each([0,2])('empty or deleted downstream rows report inconsistency without retry (%s)',async total=>{
    await expect(refreshDuplicateImport({check:{existing_file_id:'file'},type:'sueldo',
        service:{inspectImportedFile:async()=>({organization_id:'org',total_rows:total,active_rows:0})},
        store:{activeOrganizationId:'org',refreshOperationalData:async()=>{}},isCurrent:()=>true})).rejects.toThrow(total?'eliminados':'Inconsistencia');
});
test('stale duplicate result cannot refresh another organization',async()=>{
    const store={refreshOperationalData:jest.fn()};
    expect(await refreshDuplicateImport({check:{},type:'banco',store,service:{inspectImportedFile:async()=>({})},isCurrent:()=>false})).toBeNull();
    expect(store.refreshOperationalData).not.toHaveBeenCalled();
});
test.each(['ROOT_TECHNICAL_MICA','ACCOUNTING_SUPERADMIN','MICA_ORG_ADMIN','MICA_ACCOUNTANT','MICA_IMPORT_OPERATOR','MICA_READ_ONLY'])('%s fiscal matrix uses effective grants',preset=>{
    let codes=presetCapabilities(preset,'ORGANIZATION');
    const store={activeOrganizationId:'org',contextState:'TENANT_READY',hasCapability:code=>codes.includes(code)};
    for(const type of ['recibido','emitido']) expect(canImport(store,type)).toBe(preset!=='MICA_READ_ONLY');
    codes=codes.filter(c=>c!=='FISCAL_DOCUMENT_IMPORT');expect(canImport(store,'recibido')).toBe(false);
    codes=['IMPORT_CREATE'];expect(Object.keys(MICA_IMPORT_CONTRACT).some(t=>canImport(store,t))).toBe(false);
});
test('manual save uses RPC and context guard, never local store append',async()=>{
    const store={contextState:'TENANT_READY',activeOrganizationId:'org',contextGeneration:1,pendingOperations:0,canOperationalAction:()=>true};
    const client={rpc:jest.fn(async()=>({data:{id:'real'}}))};
    expect(await manualRequest('create',{kind:'INTERNAL',fields:{}},null,store,client)).toEqual({id:'real'});
    expect(client.rpc).toHaveBeenCalledWith('mica_manual_records',expect.objectContaining({p_expected_org:'org',p_action:'create'}));
    expect(store.pendingOperations).toBe(0);
    store.canOperationalAction=()=>false;
    await expect(manualRequest('create',{},null,store,client)).rejects.toThrow('permiso');expect(client.rpc).toHaveBeenCalledTimes(1);
});
test('invitation service uses authenticated RPC, assignment does not activate',async()=>{
    const client={rpc:jest.fn(async()=>({data:{activated:false}}))},service=createAdministrationService(client);
    await service.invitation('create','org',{email:'person@example.invalid',role_template_id:'preset'});
    const result=await service.invitation('assign','org',{id:'invitation',user_profile_id:'pending'});
    expect(result.activated).toBe(false);expect(client.rpc.mock.calls.map(c=>c[0])).toEqual(['mica_invitation','mica_invitation']);
});
