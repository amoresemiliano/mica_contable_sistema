import { jest } from '@jest/globals';
import * as XLSX from 'xlsx';
import { readFileSync } from 'node:fs';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';
import { moduleExportRecords, moduleExportRows, moduleCsv, moduleWorkbook, downloadModule, moduleFilename } from '../../src/js/core/moduleExports.js';
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({supabase:{}}));
const {AppStore} = await import('../../src/js/store.js');
const {persistenceService} = await import('../../src/js/core/services/persistenceService.js');
let store;
beforeEach(() => {
    store = new AppStore(); store.activeOrganizationId='A'; store.contextState='TENANT_READY';
    store.confirmedOrganizationName='Peña / Sur';
    store.permissions.organization={loaded:true,orgId:'A',codes:['RECORD_VIEW','REPORT_EXPORT']};
    store.items=[{organization_id:'A',fecha:'16/10/2026',tipo:'emitido',tipo_cbte:3,comprobante:'0001-000003',
        razonSocial:'Muñoz; "José", S.A.\nCórdoba',moneda:'USD',tipoCambio:1200,total:-121,iva:-21,netoGravado:-100}];
    store.perceptions=[{organization_id:'A',fecha:'16/10/2026',fuente:'IVA',jurisdiction:'NACIONAL (IVA)',regimen:'001',amount:-10}];
    store.salaries={organization_id:'A',periodo:'2026-10',fuente:'PAYROLL',sueldoNeto:1500.25};
    store.salariesList=[store.salaries,{organization_id:'A',periodo:'2026-09',sueldoNeto:99}];
});
afterEach(()=>jest.restoreAllMocks());
test.each(['comprobantes','percepciones','sueldos'])('%s CSV and XLSX round trip with numeric cells', module => {
    const records=moduleExportRecords(store,module);
    const rows=moduleExportRows(store,module,records);
    const csv=moduleCsv(rows);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    const parsed=XLSX.utils.sheet_to_json(XLSX.read(Buffer.from(csv,'utf8'),{type:'buffer',raw:true,FS:';'}).Sheets.Sheet1,{header:1,defval:''});
    expect(parsed[0]).toEqual(rows[0]);
    expect(parsed[1].map(String)).toEqual(rows[1].map(String));
    const book=moduleWorkbook(rows,module,XLSX);
    const reopened=XLSX.read(XLSX.write(book,{type:'buffer',bookType:'xlsx'}),{type:'buffer'});
    expect(XLSX.utils.sheet_to_json(reopened.Sheets[reopened.SheetNames[0]],{header:1})).toEqual(rows);
    const writeFile=jest.fn();downloadModule(store,module,null,'xlsx',{XLSX:{...XLSX,writeFile}});
    expect(writeFile).toHaveBeenCalledTimes(1);
    const click=jest.fn(); const createObjectURL=jest.spyOn(URL,'createObjectURL').mockReturnValue('blob:test');
    jest.useFakeTimers(); downloadModule(store,module,null,'csv',{document:{createElement:()=>({click})}});
    expect(click).toHaveBeenCalledTimes(1); expect(createObjectURL).toHaveBeenCalled();
    jest.runAllTimers();jest.useRealTimers();
});
test('Spanish CSV escaping, negative credit amounts, USD and no raw objects',()=>{
    const rows=moduleExportRows(store,'comprobantes',store.items);
    expect(moduleCsv(rows)).toContain('"Muñoz; ""José"", S.A.\nCórdoba"');
    expect(rows[1][6]).toBe('USD');expect(rows[1][13]).toBe(-121);
    expect(moduleCsv(rows)).toContain('"-121"');
    expect(moduleCsv([['=SUM(A1)','+cmd','@x',{secret:true},-12]])).toBe('\uFEFF"\'=SUM(A1)";"\'+cmd";"\'@x";"";"-12"');
});
test('filters, dates, operation, search, order, all pages and company isolation',()=>{
    const grid=new OperationalGrid({moduleId:'comprobantes',searchFields:['razonSocial'],dateField:'fecha'});
    store.items.push({...store.items[0],organization_id:'B'}, {...store.items[0],fecha:'01/09/2026'}, {...store.items[0],tipo:'recibido'});
    grid.setPeriod('2026-10');grid.setPrimaryFilter('emitidos');grid.setSearch('munoz');
    expect(moduleExportRecords(store,'comprobantes',grid)).toEqual([store.items[0]]);
    grid.setCustomRange('2026-10-17','2026-10-20');expect(moduleExportRecords(store,'comprobantes',grid)).toEqual([]);
    grid.clearPeriod();grid.setPrimaryFilter('all');
    store.items=Array.from({length:25},(_,n)=>({...store.items[0],total:n}));
    grid.toggleSort('total','numeric');grid.toggleSort('total','numeric');
    expect(moduleExportRecords(store,'comprobantes',grid)).toHaveLength(25);
    expect(moduleExportRecords(store,'comprobantes',grid)[0].total).toBe(24);
});
test('perception filters preserve IVA and IIBB amounts separately',()=>{
    store.perceptions.push({...store.perceptions[0],fuente:'ARBA',jurisdiction:'ARBA',amount:42});
    const grid=new OperationalGrid({moduleId:'percepciones',searchFields:['fuente'],dateField:'fecha'});
    grid.setPrimaryFilter('IVA');expect(moduleExportRecords(store,'percepciones',grid).map(r=>r.amount)).toEqual([-10]);
    grid.setPrimaryFilter('ARBA');expect(moduleExportRecords(store,'percepciones',grid).map(r=>r.amount)).toEqual([42]);
});
test('payroll exports only the displayed consolidated period, no invented employee fields',()=>{
    expect(moduleExportRecords(store,'sueldos')).toEqual([store.salaries]);
    expect(moduleExportRows(store,'sueldos',[store.salaries])[0].join()).not.toMatch(/Empleado|CUIL/);
    expect(moduleFilename(store,'sueldos',null,[store.salaries],'csv')).toBe('mica_sueldos_Pena_Sur_2026-10.csv');
});
test.each(['SWITCHING','LOADING','ERROR','SIGNED_OUT'])('no export in %s state',state=>{
    store.contextState=state;
    for(const module of ['comprobantes','percepciones','sueldos'])expect(()=>downloadModule(store,module,null,'csv')).toThrow('No hay registros');
});
test('actual organization switch clears export data before hydration and rejects old rows',async()=>{
    store.permissions.platform={loaded:true,codes:['ACCESS_ANY_ORG']};store.platformContextSwitchAllowed=true;
    let finish; jest.spyOn(persistenceService,'switchSuperadminOrgContext').mockImplementation(()=>new Promise(r=>finish=r));
    jest.spyOn(persistenceService,'getOperationalContext').mockResolvedValue({organization_id:'B'});
    jest.spyOn(store,'hydrateConfirmedContext').mockImplementation(async()=>{
        expect(store.items).toEqual([]);expect(store.salaries).toBeNull();
        store.activeOrganizationId='B';store.contextState='TENANT_READY';
        store.permissions.organization={loaded:true,orgId:'B',codes:['RECORD_VIEW','REPORT_EXPORT']};
    });
    const switching=store.switchOrganizationContext('B');
    expect(moduleExportRecords(store,'comprobantes')).toEqual([]);finish();await switching;
    expect(moduleExportRecords(store,'comprobantes')).toEqual([]);
    store.items=[{organization_id:'A'}, {organization_id:'B'}];
    expect(moduleExportRecords(store,'comprobantes')).toEqual([{organization_id:'B'}]);
});
test('empty, missing org, revoked export permission and loading dataset block download',()=>{
    store.items=[];expect(()=>downloadModule(store,'comprobantes',null,'csv')).toThrow('No hay registros');
    store.activeOrganizationId=null;expect(moduleExportRecords(store,'sueldos')).toEqual([]);store.activeOrganizationId='A';
    store.permissions.organization.codes=['RECORD_VIEW'];expect(moduleExportRecords(store,'sueldos')).toEqual([]);
    store.permissions.organization.codes.push('REPORT_EXPORT');
    jest.spyOn(store,'operationalDataStatus').mockReturnValue({loading:true});expect(moduleExportRecords(store,'sueldos')).toEqual([]);
});
test('existing Extractos workbook contract is unchanged',()=>{
    global.window={XLSX:{...XLSX,writeFile:jest.fn()}};
    store.bankTransactions=[{fecha:'16/10/2026',descripcion:'Banco Ñ',monto:-25,tipo:'debit',category_id:'cat'}];
    store.exportBankMovements();
    const [book,filename]=window.XLSX.writeFile.mock.calls[0];
    expect(filename).toBe('Extractos_Bancarios.xlsx');expect(book.SheetNames).toEqual(['Extractos']);
    expect(XLSX.utils.sheet_to_json(book.Sheets.Extractos)).toEqual([{Fecha:'16/10/2026',Descripcion:'Banco Ñ',Monto:-25,Tipo:'debit',Categoria:'Asignada'}]);
    delete global.window;
});
test('six controls use shared secondary style and wrapping groups',()=>{
    const html=readFileSync('index.html','utf8');
    expect(html.match(/data-module-export=/g)).toHaveLength(6);
    expect(html.match(/class="module-export-actions"[^>]*flex-wrap:wrap/g)).toHaveLength(3);
});
