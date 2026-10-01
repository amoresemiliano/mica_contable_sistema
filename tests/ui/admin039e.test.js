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
