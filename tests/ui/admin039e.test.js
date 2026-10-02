import { jest } from '@jest/globals';
import { openAdminDrawer } from '../../src/js/components/adminDrawer.js';
import { createAdministrationView } from '../../src/js/components/administration.js';
const walk = n => [n,...(n.children||[]).filter(c=>typeof c==='object').flatMap(walk)];
function node(tag) {
    return {tag,children:[],events:{},value:'',className:'',
        append(...children){this.children.push(...children);},replaceChildren(...children){this.children=children;},
        setAttribute(key,value){this[key]=value;},addEventListener(key,fn){this.events[key]=fn;},
        focus(){global.document.activeElement=this;},close:jest.fn(),remove:jest.fn(),showModal:jest.fn(),
        closest(){return null;},getClientRects(){return [1];},querySelectorAll(){return walk(this).filter(n=>['button','input','select'].includes(n.tag));}};
}
let oldDocument;
beforeEach(()=>{oldDocument=global.document;global.document={createElement:node,activeElement:null};});
afterEach(()=>{global.document=oldDocument;});
test('drawer cycles keyboard focus in both directions and Escape restores opener',()=>{
    const opener=node('button');opener.focus();const root=node('root');
    const {body}=openAdminDrawer(root,'Usuario');const input=node('input');body.append(input);
    const dialog=root.children[0],close=dialog.children[0].children[1];
    expect(dialog.showModal).toHaveBeenCalled();expect(global.document.activeElement).toBe(close);
    dialog.events.keydown({key:'Tab',shiftKey:true,preventDefault(){}});expect(global.document.activeElement).toBe(input);
    dialog.events.keydown({key:'Tab',shiftKey:false,preventDefault(){}});expect(global.document.activeElement).toBe(close);
    dialog.events.keydown({key:'Escape',preventDefault(){}});expect(dialog.remove).toHaveBeenCalled();expect(global.document.activeElement).toBe(opener);
});
const data=()=>({rights:{organizations:true,users:true,assignments:true,memberships:true},
    organizations:[{id:'north',name:'Norte',tax_id:'123',is_active:true},{id:'south',name:'Sur',tax_id:'456',is_active:true}],
    users:[{id:'ana',email:'ana@example.invalid',is_active:true},{id:'bea',email:'bea@example.invalid',is_active:false,pending:true}],
    presets:[],capabilities:[],platform_roles:[],memberships:[{user_profile_id:'ana',organization_id:'north',is_active:true}],scopes:[],overrides:[]});
test('039g platform context explains organization permissions instead of showing false denials',async()=>{
    const root=node('root'), snapshot=data();
    snapshot.rights={assignments:true};
    snapshot.capabilities=[{code:'ORGANIZATION_CREATE',scope:'PLATFORM'},{code:'RECORD_VIEW',scope:'ORGANIZATION'}];
    const store={sessionUserId:'actor',contextGeneration:1,contextState:'PLATFORM_READY',activeOrganizationId:null,subscribe(){}};
    await createAdministrationView(root,store,{read:async()=>snapshot}).load();
    walk(root).find(n=>n.textContent==='Ver detalle').onclick();
    const texts=walk(root).map(n=>n.textContent||'');
    expect(texts).toContain('Permisos de plataforma');
    expect(texts).toContain('Permisos de organización');
    expect(texts).toContain('Seleccioná una organización para consultar sus permisos efectivos.');
    expect(texts.some(t=>t.startsWith('Ver comprobantes · Efectivo:'))).toBe(false);
});

test('039g revised operational configuration hides structural tools and leads with companies',async()=>{
    const root=node('root'), snapshot=data();
    snapshot.rights={operational_admin:true,organizations:true,create_organization:true,update_organization:true,users:true,memberships:true};
    snapshot.presets=[{id:'reader',name:'Consulta',scope:'ORGANIZATION',is_active:true}];
    const store={sessionUserId:'operator',contextGeneration:1,contextState:'TENANT_READY',activeOrganizationId:'north',subscribe(){},hasCapability:()=>true};
    await createAdministrationView(root,store,{read:async()=>snapshot,invitation:async()=>[]}).load();
    expect(walk(root).filter(n=>n.role==='tab').map(n=>n.textContent)).toEqual(['Empresas','Usuarios de empresas','Categorías y actividades','Impuestos']);
    expect(walk(root).some(n=>n.textContent==='+ Nueva empresa')).toBe(true);
    walk(root).find(n=>n.textContent==='+ Nueva empresa').onclick();
    expect(walk(root).filter(n=>['name','legal_name','trade_name','tax_id'].includes(n.name))).toHaveLength(4);
    expect(walk(root).some(n=>n.name==='is_active')).toBe(false);
    walk(root).find(n=>n.role==='tab'&&n.textContent==='Usuarios de empresas').onclick();
    const text=walk(root).map(n=>n.textContent||'').join(' ');
    for(const forbidden of ['Roles y permisos','Asignaciones','Overrides','Capabilities','Ámbitos de plataforma','Estado de la cuenta']) expect(text).not.toContain(forbidden);
    expect(walk(root).some(n=>n.name==='operational-company')).toBe(true);
    expect(walk(root).some(n=>n.textContent==='+ Invitar usuario de empresa')).toBe(true);
    walk(root).find(n=>n.textContent==='Ver detalle').onclick();
    expect(walk(root).some(n=>n.name==='preset')).toBe(true);
    expect(walk(root).some(n=>n.name==='active')).toBe(true);
});

test.each([false,true])('deprecated accounting never appears in assignment selectors, even stale active=%s',async(is_active)=>{
    const root=node('root'), snapshot=data();
    snapshot.rights={assignments:true,memberships:true,global_users:true};
    snapshot.presets=[{id:'historical',code:'ACCOUNTING_SUPERADMIN',name:'Historical accounting',scope:'PLATFORM',is_active,capabilities:[],bridge:[]},
        {id:'operational',code:'ADMINISTRACION_OPERATIVA_MICA',name:'Operativa',scope:'PLATFORM',is_active:true,capabilities:[],bridge:[]}];
    const store={sessionUserId:'root',contextGeneration:1,contextState:'PLATFORM_READY',activeOrganizationId:null,subscribe(){}};
    await createAdministrationView(root,store,{read:async()=>snapshot}).load();
    walk(root).find(n=>n.textContent==='Ver detalle').onclick();
    const values=walk(root).filter(n=>n.tag==='option').map(n=>n.value);
    expect(values).toContain('operational');
    expect(values).not.toContain('historical');
});

test('root retains full configuration navigation',async()=>{
    const root=node('root'), snapshot=data();
    snapshot.rights={organizations:true,users:true,presets:true,assignments:true,global_users:true};
    const store={sessionUserId:'root',contextGeneration:1,contextState:'PLATFORM_READY',activeOrganizationId:null,subscribe(){}};
    await createAdministrationView(root,store,{read:async()=>snapshot}).load();
    expect(walk(root).filter(n=>n.role==='tab').map(n=>n.textContent)).toEqual(['Organizaciones','Usuarios','Roles y permisos','Asignaciones']);
});
test('vertical keyboard navigation mounts only selected section and user filters combine',async()=>{
    const root=node('root'),store={sessionUserId:'actor',contextGeneration:1,contextState:'TENANT_READY',activeOrganizationId:'north',subscribe(){}};
    await createAdministrationView(root,store,{read:async()=>data()}).load();
    expect(walk(root).filter(n=>n.role==='tabpanel')).toHaveLength(1);
    expect(walk(root).some(n=>n.name==='user-state')).toBe(false);
    walk(root).find(n=>n.role==='tab').onkeydown({key:'ArrowDown',preventDefault(){}});
    expect(walk(root).filter(n=>n.role==='tabpanel')).toHaveLength(1);
    const state=walk(root).find(n=>n.name==='user-state'),org=walk(root).find(n=>n.name==='user-org');
    const visibleEmail=()=>walk(root).filter(n=>n.tag==='td'&&n.textContent?.includes('@')).map(n=>n.textContent);
    state.value='pending';state.onchange();expect(visibleEmail()).toEqual(['bea@example.invalid']);
    org.value='north';org.onchange();expect(visibleEmail()).toEqual([]);
    state.value='active';state.onchange();expect(visibleEmail()).toEqual(['ana@example.invalid']);
    walk(root).find(n=>n.textContent==='Ver detalle').onclick();
    expect(walk(root).filter(n=>n.tag==='dialog')).toHaveLength(1);
    expect(walk(root).filter(n=>n.type==='checkbox')).toHaveLength(0);
});
