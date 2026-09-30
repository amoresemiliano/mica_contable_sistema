import { jest } from '@jest/globals';
import { OperationalGrid } from '../../src/js/core/operationalGrid.js';
import { renderGridPagination } from '../../src/js/components/gridPagination.js';
import { createAdministrationView } from '../../src/js/components/administration.js';
import { assignmentPermissionPreview } from '../../src/js/core/services/administrationService.js';
import { MICA_TENANT_PRESETS, MICA_ACCOUNTING_PLATFORM } from '../../src/js/core/micaPresets.js';
import { MICA_ORGANIZATION_CAPABILITIES } from '../../src/js/core/micaCapabilities.js';
import { MICA_PERMISSION_CATALOG } from '../../src/js/core/micaPermissionContract.js';
import { MODULES, canImport, canVisitModule } from '../../src/js/core/moduleAccess.js';

const node = tag => ({ tag, children: [], value: '', hidden: false, events: {},
    append(...children) { this.children.push(...children); }, replaceChildren(...children) { this.children = children; },
    setAttribute(key, value) { this[key] = value; }, addEventListener(key, fn) { this.events[key] = fn; }, focus() {} });
const all = n => [n, ...(n.children || []).filter(c => typeof c === 'object').flatMap(all)];
const rows = Array.from({length: 123}, (_, i) => ({id: String(i), name: i < 66 ? 'Norte' : 'Sur', fecha: '2026-09-01'}));

test('039c invitation UI filters preset scope and keeps activation separate',async()=>{
    const oldDocument=global.document,oldFormData=global.FormData;
    global.document={createElement:node};
    global.FormData=class {constructor(f){this.inputs=all(f);}get(name){return this.inputs.find(n=>n.name===name)?.value;}};
    try {
        const data=fixture(),root=node('root'); data.presets.push({id:'tenant',name:'Contador',scope:'ORGANIZATION',is_active:true});
        const invitation=jest.fn(async(action)=>action==='list'?[]:{status:'PENDING_AUTHENTICATION'}),apply=jest.fn();
        const store={sessionUserId:'actor',contextState:'TENANT_READY',activeOrganizationId:'NORTE',contextGeneration:1,pendingOperations:0,subscribe(){}};
        await createAdministrationView(root,store,{read:async()=>data,invitation,apply}).load();
        all(root).find(n=>n.textContent==='+ Invitar usuario').onclick();
        const f=all(root).find(n=>n.tag==='form'&&all(n).some(c=>c.textContent==='Invitar usuario'));
        const scope=all(f).find(n=>n.name==='scope'),preset=all(f).find(n=>n.name==='preset');
        expect(preset.children.map(n=>n.value)).toEqual(['tenant']);
        scope.value='PLATFORM';scope.onchange();expect(preset.children.map(n=>n.value)).toEqual(['p']);
        all(f).find(n=>n.name==='email').value='new@example.invalid';preset.value='p';
        await f.events.submit({preventDefault(){}});
        expect(invitation).toHaveBeenCalledWith('create',null,{email:'new@example.invalid',role_template_id:'p'});
        expect(apply).not.toHaveBeenCalled();
    } finally {global.document=oldDocument;global.FormData=oldFormData;}
});

test('pagination bounds, sizes, filter reset, empty results and tenant reset', () => {
    const grid = new OperationalGrid({moduleId:'comprobantes',searchFields:['name']});
    expect(grid.paginate(rows)).toMatchObject({page:1,pages:3,total:123,pageSize:50});
    grid.setPage(3); expect(grid.paginate(rows).rows).toEqual(rows.slice(100));
    grid.setPageSize(25); expect(grid.paginate(rows)).toMatchObject({page:1,pages:5,pageSize:25});
    grid.setPage(4); grid.setSearch('Norte');
    expect(grid.paginate(grid.filterAndSort(rows))).toMatchObject({page:1,pages:3,total:66});
    grid.setPage(3); expect(grid.paginate(grid.filterAndSort(rows)).rows).toHaveLength(16);
    grid.toggleSort('name'); expect(grid.paginate(rows).page).toBe(1);
    grid.setPageSize(100); expect(grid.paginate(rows).rows).toHaveLength(100);
    grid.setPageSize(999); expect(grid.pageSize).toBe(100);
    grid.setPage(100); expect(grid.paginate([])).toMatchObject({page:1,pages:1,total:0,rows:[]});
    grid.selectedRowIds.add('old'); grid.resetTenantState();
    expect(grid.pageSize).toBe(50); expect(grid.page).toBe(1); expect(grid.getSelectedCount()).toBe(0);
});

test('real pagination component buttons render only current page and clear old bulk selection', () => {
    const grid = new OperationalGrid({moduleId:'comprobantes'}), elements = new Map();
    const header = {checked:true,indeterminate:true}, bar = {classList:{add:jest.fn()}};
    elements.set('bulk-actions-bar',bar);
    const table = {after(n) {elements.set(n.id,n);}, querySelectorAll:()=>[header]};
    const document = {createElement:node,getElementById:id=>elements.get(id)};
    const tbody = {closest:()=>table};
    let visible;
    const render = () => {visible=renderGridPagination(grid,rows,tbody,render,document);};
    render(); const controls=elements.get('pagination-comprobantes');
    expect(visible).toHaveLength(50); expect(controls.children[0].disabled).toBe(true);
    controls.children[2].onclick(); expect(visible[0].id).toBe('50');
    controls.children[2].onclick(); expect(controls.children[2].disabled).toBe(true);
    expect(controls.children[1].textContent).toContain('3 / 3');
    controls.children[3].value='25'; controls.children[3].onchange();
    expect(visible).toHaveLength(25); expect(grid.page).toBe(1);
    expect(header.checked).toBe(false); expect(bar.classList.add).toHaveBeenCalledWith('hidden');
});

test.each(['NORTE','OESTE','SUR','MICA'])('effective operational grant matrix in %s has no role bypass', org => {
    for (const platform of [['ACCESS_ANY_ORG'],MICA_ACCOUNTING_PLATFORM]) {
        const store = {contextState:'TENANT_READY',activeOrganizationId:org,codes:[...MICA_ORGANIZATION_CAPABILITIES],
            hasCapability(code,{scope='PLATFORM'}={}) {return (scope==='PLATFORM'?platform:this.codes).includes(code);}};
        for (const id of Object.keys(MODULES)) expect(canVisitModule(store,id)).toBe(true);
        for (const type of ['percepcion','banco','sueldo']) expect(canImport(store,type)).toBe(true);
        store.codes=store.codes.filter(c=>c!=='IMPORT_VIEW'); expect(canImport(store,'banco')).toBe(false);
        store.codes=['BANK_IMPORT','IMPORT_VIEW','IMPORT_CREATE']; expect(canVisitModule(store,'tab-bancos')).toBe(false);
        store.codes=MICA_TENANT_PRESETS.MICA_ORG_ADMIN; expect(canImport(store,'banco')).toBe(true);
        store.codes=MICA_TENANT_PRESETS.MICA_READ_ONLY; expect(canImport(store,'banco')).toBe(false);
    }
});

function fixture() {
    return {rights:{organizations:true,create_organization:true,users:true,global_users:true,presets:true,global_presets:true,assignments:true,memberships:true},
        organizations:[{id:'NORTE',name:'NORTE',is_active:true}],users:[{id:'u',email:'user@example.invalid',is_active:true}],
        presets:[{id:'p',name:'Contabilidad',scope:'PLATFORM',is_active:true,capabilities:['MICA_ADMIN_MANAGE'],bridge:['BANK_IMPORT'],recipients:1}],
        platform_roles:[{user_profile_id:'u',role_template_id:'p',is_active:true}],memberships:[],
        scopes:[{user_profile_id:'u',organization_id:'NORTE',is_active:true}],contexts:[{user_profile_id:'u',organization_id:'NORTE'}],
        overrides:[],capabilities:[{code:'BANK_IMPORT',scope:'ORGANIZATION'},{code:'ACCESS_ANY_ORG',scope:'PLATFORM',delegation_class:'OWNER_RESERVED'}]};
}
test('assignment preview requires active context/scope and DENY wins across paths', () => {
    const data=fixture(), cap=data.capabilities[0];
    const preview=()=>assignmentPermissionPreview(data,'u','NORTE',cap);
    expect(preview().effective).toBe(true);
    data.scopes[0].is_active=false; expect(preview().effective).toBe(false);
    data.scopes[0].is_active=true; data.contexts=[]; expect(preview().effective).toBe(false);
    data.contexts=[{user_profile_id:'u',organization_id:'NORTE'}];
    data.memberships=[{user_profile_id:'u',organization_id:'NORTE',role_template_id:'tenant',is_active:true}];
    data.presets.push({id:'tenant',is_active:true,capabilities:['BANK_IMPORT']});
    data.overrides=[{user_profile_id:'u',organization_id:'NORTE',kind:'platform_org',capability:'BANK_IMPORT',effect:'DENY'},
        {user_profile_id:'u',organization_id:'NORTE',kind:'membership',capability:'BANK_IMPORT',effect:'ALLOW'}];
    expect(preview()).toMatchObject({effective:false,effect:'DENY'});
    data.scopes[0].is_active=false; expect(preview().effective).toBe(false);
});

test('administration has one visible tab, compact editors, filtered capabilities and selected-user assignments', async () => {
    const old=global.document; global.document={createElement:node};
    try {
        const root=node('root'), data=fixture();
        const store={sessionUserId:'actor',contextState:'TENANT_READY',activeOrganizationId:'NORTE',contextGeneration:1,subscribe(){}};
        await createAdministrationView(root,store,{read:async()=>data}).load();
        const panels=()=>all(root).filter(n=>n.role==='tabpanel');
        expect(panels().filter(n=>!n.hidden)).toHaveLength(1);
        const tabs=all(root).filter(n=>n.role==='tab');
        expect(tabs.map(t=>t.textContent)).toEqual(['Organizaciones','Usuarios','Roles y permisos','Asignaciones']);
        tabs[2].onclick(); expect(panels().filter(n=>!n.hidden)[0].children[0].textContent).toBe('Roles y permisos');
        all(panels()[2]).find(n=>n.textContent==='Nuevo preset').onclick();
        const boxes=all(panels()[2]).filter(n=>n.type==='checkbox');
        expect(boxes.map(n=>n.value)).toContain('BANK_IMPORT'); expect(boxes.map(n=>n.value)).not.toContain('ACCESS_ANY_ORG');
        expect(all(panels()[2]).find(n=>n.className==='mica-permission-count').textContent).toBe('0 de 1 seleccionados');
        boxes[0].checked=true; boxes[0].onchange();
        expect(all(panels()[2]).find(n=>n.className==='mica-permission-count').textContent).toBe('1 de 1 seleccionados');
        expect(all(panels()[2]).find(n=>n.tag==='strong').textContent).toBe('Importar extractos');
        all(panels()[2]).find(n=>n.textContent==='Expandir grupos').onclick();
        expect(all(panels()[2]).filter(n=>n.tag==='details').every(n=>n.open)).toBe(true);
        all(panels()[2]).find(n=>n.textContent==='Contraer grupos').onclick();
        expect(all(panels()[2]).filter(n=>n.tag==='details').every(n=>!n.open)).toBe(true);
        const search=all(panels()[2]).find(n=>n.type==='search'); search.value='unmatched'; search.oninput();
        expect(all(panels()[2]).filter(n=>n.tag==='details').every(n=>n.hidden)).toBe(true);
        tabs[3].onclick(); expect(panels().filter(n=>!n.hidden)).toHaveLength(1);
        expect(all(panels()[3]).some(n=>n.textContent?.includes('Contabilidad'))).toBe(true);
        expect(all(panels()[3]).filter(n=>n.tag==='form').every(f=>all(panels()[3]).some(n=>n.tag==='details'&&all(n).includes(f)))).toBe(true);
    } finally {global.document=old;}
});

test('approved pending features remain selectable and persist in a custom preset with secondary codes', async () => {
    const oldDocument=global.document, oldFormData=global.FormData;
    global.document={createElement:node};
    global.FormData=class {
        constructor(form) {this.inputs=all(form).filter(n=>n.name&&(!n.type||n.type!=='checkbox'||n.checked));}
        get(name) {return this.inputs.find(n=>n.name===name)?.value ?? null;}
        getAll(name) {return this.inputs.filter(n=>n.name===name).map(n=>n.value);}
        has(name) {return this.inputs.some(n=>n.name===name);}
    };
    try {
        const root=node('root'), data=fixture();
        const approved=MICA_PERMISSION_CATALOG.filter(c=>c.scope==='ORGANIZATION'&&c.status==='PREPARED_039B');
        data.capabilities=[...approved,...MICA_PERMISSION_CATALOG.filter(c=>c.ownerReserved)];
        const apply=jest.fn(async()=> 'new-preset');
        const store={sessionUserId:'actor',contextState:'TENANT_READY',activeOrganizationId:'NORTE',contextGeneration:1,pendingOperations:0,subscribe(){}};
        await createAdministrationView(root,store,{read:async()=>data,apply}).load();
        all(root).find(n=>n.role==='tab'&&n.textContent==='Roles y permisos').onclick();
        all(root).find(n=>n.textContent==='Nuevo preset').onclick();
        const form=all(root).find(n=>n.tag==='form'&&all(n).some(c=>c.textContent==='Crear preset'));
        all(form).find(n=>n.name==='name').value='Permisos futuros';
        const boxes=all(form).filter(n=>n.type==='checkbox');
        expect(boxes.map(n=>n.value)).toEqual(approved.map(c=>c.code));
        for(const box of boxes) {expect(box.disabled).not.toBe(true); box.checked=true; box.onchange();}
        expect(all(form).filter(n=>n.textContent==='Permiso asignable · función pendiente de backend')).toHaveLength(7);
        for(const c of approved) {
            expect(all(form).some(n=>n.tag==='strong'&&n.textContent===c.label)).toBe(true);
            expect(all(form).some(n=>n.className==='mica-permission-code'&&n.textContent===c.code)).toBe(true);
        }
        await form.events.submit({preventDefault(){}});
        expect(apply).toHaveBeenCalledWith('preset',expect.objectContaining({scope:'ORGANIZATION',capabilities:approved.map(c=>c.code),bridge:[]}));
        expect(store.pendingOperations).toBe(0);
    } finally {global.document=oldDocument;global.FormData=oldFormData;}
});
