import { openAdminDrawer } from './adminDrawer.js';
import { administrationService, editableCapabilities, assignmentPermissionPreview } from '../core/services/administrationService.js';
import { capabilityPresentation } from '../core/capabilityPresentation.js';
import { SCOPE_LABELS, PERMISSION_STATES, MICA_BUSINESS_FUNCTIONS, PERMISSION_GROUPS } from '../core/micaPermissionContract.js';

export function createAdministrationView(root, store, service = administrationService) {
    let epoch = 0, snapshot = null, busy = false, contextKey = '', search = '';
    let activeSection = '', selectedUser = '', selectedPreset = '', tabs, content, drawer;
    let userState = '', userOrg = '';
    const el = (tag, text, props = {}) => {
        const node = document.createElement(tag);
        if (text !== null && text !== undefined) node.textContent = text;
        Object.assign(node, props);
        return node;
    };
    const context = () => [store.sessionUserId, store.contextGeneration, store.contextState, store.activeOrganizationId].join('|');
    const ready = () => ['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState);
    const mayInvite = rights => rights.global_users || (store.activeOrganizationId &&
        ['ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PERMISSION_MANAGE'].every(code=>
            store.hasCapability?.(code,{scope:'ORGANIZATION',orgId:store.activeOrganizationId})));
    function clear(message) { drawer?.close(); drawer = null; root.replaceChildren(el('p', message, { role: 'status' })); }
    function field(form, name, title, value = '', options = null) {
        const label = el('label', title + ' ');
        let input;
        if (options) {
            input = el('select', null, { name, required: true });
            for (const [key, caption] of options) input.append(el('option', caption, { value: key }));
            input.value = value || options[0]?.[0] || '';
        } else input = el('input', null, { name, value: value ?? '', type: 'text' });
        label.append(input); form.append(label); return input;
    }
    const choice = (form, name, title, value) => field(form, name, title, String(value ?? true), [['true', 'Activo'], ['false', 'Inactivo']]);
    const options = (rows, key = 'name') => rows.map(r => [r.id, r[key] || r.id]);
    function form(section, title, submit) {
        const f = el('form', null, { className: 'mica-admin-form' });
        f.append(el('h4', title));
        const status = el('p', '', { role: 'status' });
        const button = el('button', 'Guardar', { type: 'submit' });
        f.addEventListener('submit', async event => {
            event.preventDefault();
            if (busy || !ready()) return;
            busy = true; button.disabled = true; ++store.pendingOperations;
            const token = epoch;
            try {
                await submit(new FormData(f));
                if (token === epoch) {
                    // Refresh selector targets and the current actor's effective capabilities.
                    if (store.reloadOperationalContext) await store.reloadOperationalContext();
                    await load();
                }
            } catch (error) {
                if (token === epoch) status.textContent = error.message;
            } finally { busy = false; button.disabled = false; --store.pendingOperations; }
        });
        section.append(f); f.append(button, status);
        return f;
    }
    function section(title) {
        const node = el('section', null, { className: 'mica-admin-panel', role: 'tabpanel', id: 'mica-admin-content' });
        node.setAttribute?.('aria-labelledby', 'mica-section-' + activeSection.replaceAll(' ', '-'));
        node.actionHeader = el('header', null, {className:'mica-admin-heading'});
        node.actionHeader.append(el('h3', title)); node.append(node.actionHeader); content.append(node); return node;
    }
    function navigation(titles, data) {
        tabs = el('nav', null, { className: 'mica-admin-tabs', role: 'tablist', ariaLabel: 'Secciones de configuración' });
        tabs.setAttribute?.('aria-orientation', 'vertical');
        titles.forEach((title, index) => {
            const button = el('button', title, { type: 'button', role: 'tab', id: 'mica-section-' + title.replaceAll(' ', '-') });
            button.setAttribute?.('aria-controls', 'mica-admin-content');
            button.ariaSelected = String(title === activeSection); button.tabIndex = title === activeSection ? 0 : -1;
            button.onclick = () => { activeSection = title; render(data); tabs.children[index]?.focus?.(); };
            button.onkeydown = event => {
                const next = {ArrowDown:(index+1)%titles.length,ArrowUp:(index+titles.length-1)%titles.length,Home:0,End:titles.length-1}[event.key];
                if (next === undefined) return;
                event.preventDefault(); activeSection=titles[next]; render(data); tabs.children[next]?.focus?.();
            };
            tabs.append(button);
        });
        content = el('div', null, { className: 'mica-admin-content' }); root.append(tabs, content);
    }
    function table(parent, rows, columns, edit) {
        const table = el('table', null, { className: 'mica-admin-table' });
        const head = el('thead'), headings = el('tr');
        for (const [label] of columns) headings.append(el('th', label, { scope: 'col' }));
        if (edit) headings.append(el('th', 'Acciones', { scope: 'col' }));
        head.append(headings); table.append(head);
        const body = el('tbody'); table.append(body);
        for (const row of rows) {
            const tr = el('tr');
            for (const [,value] of columns) tr.append(el('td', value(row)));
            if (edit) { const td=el('td'), button=el('button','Ver detalle',{type:'button'});
                button.onclick=()=>edit(row); td.append(button); tr.append(td); }
            body.append(tr);
        }
        if (!rows.length) {const tr=el('tr');tr.append(el('td','Sin resultados.',{colSpan:columns.length+(edit?1:0)}));body.append(tr);}
        const scroll=el('div',null,{className:'mica-admin-table-scroll'});scroll.append(table);parent.append(scroll);
    }
    function list(parent, rows, label, edit) {
        const ul = el('table', null, { className: 'mica-admin-table' });
        const body = el('tbody'); ul.append(body);
        for (const row of rows) {
            const li = el('tr'); li.append(el('td', label(row)));
            if (edit) {
                const actions = el('td');
                const button = el('button', 'Editar', { type: 'button' });
                button.addEventListener('click', () => edit(row)); actions.append(button); li.append(actions);
            }
            body.append(li);
        }
        if (!rows.length) { const row = el('tr'); row.append(el('td', 'Sin registros.')); body.append(row); }
        const wrap = el('div', null, { className: 'mica-admin-table-scroll' });
        wrap.append(ul); parent.append(wrap);
    }
    function disclosure(parent, title) {
        const details = el('details');
        if (parent.className === 'mica-admin-editor') details.setAttribute?.('name', 'mica-assignment-tools');
        details.append(el('summary', title)); parent.append(details); return details;
    }
    function openEditor(title = 'Editar configuración') {
        drawer?.close(); drawer = openAdminDrawer(root, title); return drawer.body;
    }
    function render(data) {
        drawer?.close(); drawer = null; root.replaceChildren();
        const { rights: r, organizations, users, presets, capabilities } = data;
        if (!Object.values(r).some(Boolean)) { clear('No tenés permisos de administración en este contexto.'); return; }
        const availableSections = [[r.organizations,'Organizaciones'],[r.users,'Usuarios'],[r.presets,'Roles y permisos'],[r.assignments,'Asignaciones']].filter(([allowed])=>allowed).map(([,title])=>title);
        if (!availableSections.includes(activeSection)) activeSection = availableSections[0];
        navigation(availableSections, data);
        if (r.organizations && activeSection === 'Organizaciones') {
            const s = section('Organizaciones');
            let editor;
            function edit(row = {}) {
                editor = openEditor(row.id ? 'Editar organización' : 'Nueva organización');
                const f = form(editor, row.id ? 'Editar organización' : 'Crear organización', fd => {
                    const payload = row.id ? { id: row.id } : {};
                    for (const key of ['name', 'legal_name', 'trade_name', 'tax_id']) if (fd.has(key)) payload[key] = fd.get(key);
                    if (row.id && r.archive_organization) payload.is_active = fd.get('is_active') === 'true';
                    return service.apply('organization', payload);
                });
                if (!row.id || r.update_organization) {
                    field(f, 'name', 'Nombre', row.name).required = true;
                    field(f, 'legal_name', 'Razón social', row.legal_name);
                    field(f, 'trade_name', 'Nombre comercial', row.trade_name);
                    field(f, 'tax_id', 'CUIT', row.tax_id);
                }
                if (row.id && r.archive_organization) choice(f, 'is_active', 'Estado', row.is_active);
            }
            s.append(el('p', organizations.length + ' organizaciones disponibles', {className:'mica-admin-summary'}));
            table(s, organizations, [['Nombre',o=>o.name],['CUIT',o=>o.tax_id||'—'],['Estado',o=>o.is_active?'Activa':'Inactiva']], r.update_organization || r.archive_organization ? edit : null);
            if (r.create_organization) {
                const b = el('button', 'Nueva organización', { type: 'button' });
                b.className='btn-primary mica-admin-primary'; b.onclick = () => edit(); s.actionHeader.append(b);
            }
        }
        if (r.users && activeSection === 'Usuarios') {
            const s = section('Usuarios');
            s.append(el('p', 'El usuario se registra con el acceso habitual. La cuenta nueva queda pendiente; asigná un preset y ámbito antes de aprobarla.'));
            const sf = el('form',null,{className:'mica-admin-search'});
            const q = field(sf, 'search', 'Buscar email', search);
            sf.append(el('button', 'Buscar', { type: 'submit' }));
            sf.onsubmit = e => { e.preventDefault(); search = q.value; load(); }; s.append(sf);
            let editor;
            if (service.invitation && mayInvite(r)) {
                const invite = el('button','+ Invitar usuario',{type:'button'});
                invite.onclick = () => {
                    editor = openEditor('Invitar usuario');
                    const f = form(editor,'Invitar usuario',fd => service.invitation('create',
                        fd.get('scope') === 'PLATFORM' ? null : store.activeOrganizationId,
                        {email:fd.get('email'),role_template_id:fd.get('preset')}));
                    const email = field(f,'email','Email'); email.type='email'; email.required=true;
                    const scope=field(f,'scope','Tipo',store.activeOrganizationId?'ORGANIZATION':'PLATFORM',[
                        ...(store.activeOrganizationId ? [['ORGANIZATION',SCOPE_LABELS.ORGANIZATION]] : []),...(r.global_users ? [['PLATFORM',SCOPE_LABELS.PLATFORM]] : [])]);
                    const preset=field(f,'preset','Preset','',[]);
                    const draw=()=>{preset.replaceChildren(...presets.filter(p=>p.is_active&&p.scope===scope.value&&
                        (!p.organization_id||p.organization_id===store.activeOrganizationId)).map(p=>el('option',p.name,{value:p.id})));};
                    scope.onchange=draw; draw();
                    f.append(el('p','Organización: '+(organizations.find(o=>o.id===store.activeOrganizationId)?.name||'Seleccioná una empresa en el selector superior')+'. Para otra empresa, cambiá el contexto antes de invitar.'));
                    f.append(el('p','Estado inicial: pendiente de autenticación. Se registra una preautorización; no se envía email. Compartí el acceso habitual de MICA. Después de autenticarse, confirmá la asignación y activá la cuenta por separado.'));
                }; invite.className='btn-primary mica-admin-primary'; s.actionHeader.append(invite);
                list(disclosure(s,'Invitaciones pendientes'),data.invitations||[],i=>i.email+' · '+(i.assigned_at?'Asignada · activar desde Usuarios':i.user_profile_id?'Pendiente de confirmación':'Pendiente de autenticación'),i=>{
                    editor = openEditor();
                    if (!i.user_profile_id || i.assigned_at) { editor.append(el('p','La cuenta debe autenticarse antes de confirmar. Las asignaciones ya confirmadas se administran desde Usuarios y Asignaciones.')); return; }
                    form(editor,'Confirmar preset y organización para '+i.email,()=>service.invitation('assign',i.organization_id,
                        {id:i.id,user_profile_id:i.user_profile_id}));
                    editor.append(el('p','Esta confirmación asigna el preset; la cuenta continúa inactiva hasta que la actives en Usuarios.'));
                });
            }
            const filters=el('div',null,{className:'mica-admin-filters'}); s.append(filters);
            const state=field(filters,'user-state','Estado',userState,[['','Todos'],['active','Activo'],['inactive','Inactivo'],['pending','Pendiente']]); state.value=userState;
            const organization=field(filters,'user-org','Organización',userOrg,[['','Todas'],...options(organizations)]); organization.value=userOrg;
            const listing=el('div'); s.append(listing);
            const assignments = user => [...data.platform_roles,...data.memberships].filter(a=>a.user_profile_id===user.id);
            const roleName = user => assignments(user).map(a=>presets.find(p=>p.id===a.role_template_id)?.name||'Preset histórico').join(' · ')||'Sin asignación';
            const status = user => user.protected?'Root protegido':user.pending?'Pendiente':user.is_active?'Activo':'Inactivo';
            const drawUsers=()=>{ listing.replaceChildren(); table(listing,users.filter(u=>
                (!userState || (userState==='pending'?u.pending:userState==='active'?u.is_active&&!u.pending:!u.is_active&&!u.pending)) &&
                (!userOrg || [...data.memberships,...data.scopes].some(a=>a.user_profile_id===u.id&&a.organization_id===userOrg))),
                [['Usuario',u=>u.name||u.email.split('@')[0]],['Email',u=>u.email],
                 ['Ámbito',u=>data.platform_roles.some(a=>a.user_profile_id===u.id)?'Plataforma':'Organización'],['Preset / Rol',roleName],['Estado',status]],user=>{
                    editor=openEditor(user.email);
                    editor.append(el('p',roleName(user)),el('p',status(user)));
                    const scopes=[...data.memberships,...data.scopes].filter(a=>a.user_profile_id===user.id);
                    editor.append(el('p',scopes.map(a=>(organizations.find(o=>o.id===a.organization_id)?.name||a.organization_id)+(a.is_active?'':' (inactivo)')).join(' · ')||'Sin ámbitos asignados'));
                    if(user.protected) {editor.append(el('p','Root técnico protegido.'));return;}
                    if(r.global_users) { const f=form(editor,'Estado de la cuenta',fd=>service.apply('user',{
                        user_profile_id:user.id,organization_id:store.activeOrganizationId,is_active:fd.get('active')==='true'
                    }));choice(f,'active','Estado',user.is_active); }
                    if(r.assignments) {const assign=el('button','Preset y permisos',{type:'button'});
                        assign.onclick=()=>{selectedUser=user.id;activeSection='Asignaciones';render(data);};editor.append(assign);}
                }); };
            state.onchange=()=>{userState=state.value;drawUsers();};organization.onchange=()=>{userOrg=organization.value;drawUsers();};drawUsers();
            if (users.length === 200) s.append(el('p', 'Se muestran 200 usuarios. Refiná la búsqueda.'));
        }
        if (r.presets && activeSection === 'Roles y permisos') {
            const s = section('Roles y permisos');
            s.append(el('p', 'Presets MICA reutilizables. Los templates históricos no se editan desde esta pantalla.'));
            const split=el('div',null,{className:'mica-preset-split'}), master=el('div',null,{className:'mica-preset-list'}), editor=el('div',null,{className:'mica-admin-editor'});
            split.append(master,editor);s.append(split);
            function edit(row = {}) {
                editor.replaceChildren();
                const f = form(editor, row.id ? 'Editar preset' : 'Crear preset', fd => service.apply('preset', {
                    id: row.id || null, organization_id: row.id ? row.organization_id : (r.global_presets ? null : store.activeOrganizationId),
                    name: fd.get('name'), scope: fd.get('scope'), is_active: fd.get('active') === 'true',
                    capabilities: fd.getAll('capabilities'), bridge: fd.getAll('bridge'),
                    expected_recipients: Number(fd.get('recipients') || 0)
                }));
                field(f, 'name', 'Nombre', row.name).required = true;
                const scope = field(f, 'scope', 'Ámbito', row.scope || 'ORGANIZATION',
                    row.id ? [[row.scope, SCOPE_LABELS[row.scope]]] : r.global_presets ? [['ORGANIZATION', SCOPE_LABELS.ORGANIZATION], ['PLATFORM', SCOPE_LABELS.PLATFORM]] : [['ORGANIZATION', SCOPE_LABELS.ORGANIZATION]]);
                choice(f, 'active', 'Estado', row.is_active);
                field(f, 'recipients', 'Confirmar cantidad de destinatarios afectados', row.recipients || 0).type = 'number';
                const checks = el('div'); f.append(checks);
                function draw() {
                    checks.replaceChildren();
                    for (const [name, sc] of [['capabilities', scope.value], ...(scope.value === 'PLATFORM' ? [['bridge', 'ORGANIZATION']] : [])]) {
                        const group = el('fieldset'); group.append(el('legend', name === 'bridge' ? SCOPE_LABELS.ORGANIZATION + ' · acciones en el ámbito asignado' : SCOPE_LABELS[sc]));
                        const toolbar = el('div',null,{className:'mica-permission-toolbar'});
                        const search = el('input',null,{type:'search',placeholder:'Buscar permiso o código',ariaLabel:'Buscar permisos'});
                        const counter = el('span','',{className:'mica-permission-count',role:'status'});
                        const expand = el('button','Expandir grupos',{type:'button'}), collapse = el('button','Contraer grupos',{type:'button'});
                        toolbar.append(search,counter,expand,collapse); group.append(toolbar);
                        const entries=[]; const groups=new Map();
                        const updateCount = () => {counter.textContent = `${entries.filter(e=>e.input?.checked).length} de ${entries.filter(e=>e.input).length} seleccionados`;};
                        for (const cap of editableCapabilities(capabilities, sc, name === 'bridge' ? 'PLATFORM_BRIDGE' : 'STANDARD')) {
                            const presentation=capabilityPresentation(cap);
                            if(!groups.has(presentation.group)) {
                                const details=el('details',null,{open:false}); details.append(el('summary',presentation.group));
                                groups.set(presentation.group,details); group.append(details);
                            }
                            const label = el('label',null,{className:'mica-permission-option',title:presentation.description});
                            const input = el('input', null, { type: 'checkbox', name, value: cap.code, checked: (row[name] || []).includes(cap.code) });
                            const text = el('span',null,{className:'mica-permission-text'});
                            text.append(el('strong',presentation.label),el('small',presentation.description,{className:'mica-permission-description'}),el('small',cap.code,{className:'mica-permission-code'}));
                            input.setAttribute?.('role','switch'); input.title=cap.code;
                            if (presentation.runtimeStatus === 'DISABLED_PENDING_BACKEND')
                                text.append(el('small','Permiso asignable · función pendiente de backend',{className:'mica-permission-code'}));
                            label.append(input,text); input.onchange=updateCount;
                            groups.get(presentation.group).append(label); entries.push({label,input,group:presentation.group,text:(presentation.label+' '+presentation.description+' '+cap.code).toLowerCase()});
                        }
                        expand.onclick=()=>{for(const details of groups.values()) details.open=true;};
                        collapse.onclick=()=>{for(const details of groups.values()) details.open=false;};
                        if (sc === 'ORGANIZATION') for (const fn of MICA_BUSINESS_FUNCTIONS) {
                            const groupName = PERMISSION_GROUPS[fn.group];
                            if (!groups.has(groupName)) {
                                const details = el('details'); details.append(el('summary',groupName));
                                groups.set(groupName,details); group.append(details);
                            }
                            const label = el('p',fn.label + ': comparte el permiso «' + capabilityPresentation({code:fn.capability}).label + '».', {className:'mica-shared-permission'});
                            groups.get(groupName).append(label);
                            entries.push({label,group:groupName,text:(fn.label+' '+fn.capability).toLowerCase()});
                        }
                        updateCount();
                        search.oninput=()=>{const q=search.value.toLowerCase(); entries.forEach(e=>e.label.hidden=!e.text.includes(q));
                            for(const [name,details] of groups) { details.hidden=!entries.some(e=>e.group===name&&!e.label.hidden); details.open=!!q; }};
                        checks.append(group);
                    }
                }
                scope.onchange = draw; draw();
            }
            const visiblePresets=presets.filter(p => r.global_presets || p.organization_id === store.activeOrganizationId);
            const selected=visiblePresets.find(p=>p.id===selectedPreset)||visiblePresets[0];
            selectedPreset=selected?.id||'';
            for(const preset of visiblePresets) {
                const button=el('button',preset.name,{type:'button',ariaPressed:String(selectedPreset===preset.id)});
                button.onclick=()=>{selectedPreset=preset.id;for(const child of master.children)child.ariaPressed=String(child===button);edit(preset);};master.append(button);
            }
            const add=el('button','Nuevo preset',{type:'button',className:'btn-primary'});add.onclick=()=>{selectedPreset='';for(const child of master.children)child.ariaPressed='false';edit();};master.append(add);
            if(selected) {selectedPreset=selected.id;edit(selected);}
            else editor.append(el('p','Creá un preset para definir sus permisos.'));

        }
        if (r.assignments && activeSection === 'Asignaciones') {
            const s = section('Asignaciones');
            const candidates=users.filter(u=>!u.protected);
            if(!candidates.some(u=>u.id===selectedUser)) selectedUser='';
            table(s,candidates,[['Usuario',u=>u.email],['Estado',u=>u.is_active?'Activo':'Inactivo']],user=>{selectedUser=user.id;drawAssignment();});
            function drawAssignment() {
            const panel=openEditor(users.find(u=>u.id===selectedUser)?.email||'Asignación');
            const editable = candidates.filter(u=>u.id===selectedUser);
            if (!editable.length) { panel.append(el('p', 'Buscá un usuario administrable.')); return; }
            const org = store.activeOrganizationId;
            const available = presets.filter(p => p.is_active);
            const presetName = id => presets.find(p => p.id === id)?.name || 'Preset histórico (no editable)';
            list(panel, data.platform_roles.filter(p => p.user_profile_id === selectedUser), p =>
                'Plataforma · ' + presetName(p.role_template_id) + ' · ' + (p.is_active ? 'Activo' : 'Inactivo'));
            list(panel, data.memberships.filter(m => m.user_profile_id === selectedUser), m =>
                presetName(m.role_template_id) + ' · ' +
                (organizations.find(o => o.id === m.organization_id)?.name || m.organization_id) + ' · ' + (m.is_active ? 'Activa' : 'Inactiva'));
            if (r.memberships) {
            const f = form(disclosure(panel, 'Preset y organización'), 'Asignar preset', fd => {
                const preset = available.find(p => p.id === fd.get('preset'));
                if (!preset) throw new Error('Seleccioná un preset.');
                return service.apply(preset.scope === 'PLATFORM' ? 'platform_role' : 'membership', {
                    user_profile_id: fd.get('user'), role_template_id: preset.id,
                    organization_id: preset.scope === 'PLATFORM' ? null : org, is_active: fd.get('active') === 'true'
                });
            });
            field(f, 'user', 'Usuario', '', options(editable, 'email'));
            field(f, 'preset', 'Preset', '', options(available.filter(p => p.scope === 'PLATFORM' ? r.global_users : !!org)));
            choice(f, 'active', 'Estado', true);
            }
            if (!org) panel.append(el('p', 'Seleccioná una organización en el selector operacional para administrar memberships.'));
            if (r.global_users) {
                const scopesPanel = disclosure(panel, 'Ámbitos de plataforma');
                const scopeForm = form(scopesPanel, 'Asignar / revocar ámbito de plataforma', fd => service.apply('scope', {
                    user_profile_id: fd.get('user'), organization_id: fd.get('organization'), is_active: fd.get('active') === 'true'
                }));
                field(scopeForm, 'user', 'Usuario plataforma', '', options(editable.filter(u => data.platform_roles.some(p => p.user_profile_id === u.id && p.is_active)), 'email'));
                field(scopeForm, 'organization', 'Organización', '', options(organizations.filter(o => o.is_active)));
                choice(scopeForm, 'active', 'Estado', true);
                list(scopesPanel, data.scopes.filter(row=>row.user_profile_id===selectedUser), row => (users.find(u => u.id === row.user_profile_id)?.email || '') + ' · ' +
                    (organizations.find(o => o.id === row.organization_id)?.name || row.organization_id) + ' · ' + (row.is_active ? 'Ámbito activo' : 'Ámbito inactivo'));
            }
            const overridePanel = disclosure(panel, 'Personalizar permisos');
            list(overridePanel, data.overrides.filter(o => o.user_profile_id === selectedUser), o =>
                capabilityPresentation({code:o.capability}).label + ' · ' + PERMISSION_STATES[o.effect] + ' · ' +
                (organizations.find(org => org.id === o.organization_id)?.name || o.organization_id || 'Plataforma'));
            const of = form(overridePanel, 'Excepción individual', fd => service.apply('override', {
                user_profile_id: fd.get('user'), kind: fd.get('kind'), organization_id: fd.get('kind') === 'platform' ? null : org,
                capability: fd.get('capability'), effect: fd.get('effect')
            }));
            const who = field(of, 'user', 'Usuario', '', options(editable, 'email'));
            const kind = field(of, 'kind', 'Tipo', '', r.global_users ?
                [['platform', 'Plataforma'], ...(org ? [['membership', 'Membership'], ['platform_org', 'Plataforma en organización']] : [])] : [['membership', 'Membership']]);
            const cap = field(of, 'capability', 'Permiso', '', []);
            field(of, 'effect', 'Excepción individual', 'INHERITED', Object.entries(PERMISSION_STATES));
            const preview = el('p'); of.append(preview);
            function showPreview() {
                const state = assignmentPermissionPreview(data, who.value, org,
                    {code: cap.value, scope: kind.value === 'platform' ? 'PLATFORM' : 'ORGANIZATION'});
                preview.textContent = state.unknown ? 'Preset histórico: estado efectivo no calculado.' :
                    'Estado guardado · Base: ' + (state.inherited ? 'Permitido' : 'sin permiso') + ' · Excepción: ' + PERMISSION_STATES[state.effect] +
                    ' · Efectivo: ' + (state.effective ? 'Permitido' : 'Denegado');
            }
            function refreshCaps() {
                cap.replaceChildren(...editableCapabilities(capabilities, kind.value === 'platform' ? 'PLATFORM' : 'ORGANIZATION', kind.value === 'platform_org' ? 'PLATFORM_BRIDGE' : 'STANDARD')
                    .map(c => el('option', capabilityPresentation(c).label, { value: c.code, title:c.code })));
                showPreview();
            }
            who.onchange = cap.onchange = showPreview; kind.onchange = refreshCaps; refreshCaps();
            const effective = disclosure(panel, 'Permisos efectivos');
            effective.append(el('p', 'Cálculo del estado guardado, para el contexto activo del usuario. El servidor valida cada operación. Actualizá para consultar cambios de otra sesión.'));
            const refresh = el('button', 'Actualizar', {type: 'button'}); refresh.onclick = load; effective.append(refresh);
            const filter = field(effective, 'permission-search', 'Buscar permiso');
            const results = el('div'); effective.append(results);
            const drawEffective = () => {
                results.replaceChildren();
                list(results, capabilities.filter(c => editableCapabilities([c],c.scope,'PLATFORM_BRIDGE').length &&
                    (c.code + ' ' + capabilityPresentation(c).label).toLowerCase().includes(filter.value.toLowerCase())), c => {
                    const state = assignmentPermissionPreview(data, selectedUser, org, c);
                    return capabilityPresentation(c).label + ' · Efectivo: ' +
                        (state.unknown ? 'No calculado' : state.effective ? 'Permitido' : 'Denegado') + ' · ' + PERMISSION_STATES[state.effect];
                });
            };
            filter.oninput = drawEffective; drawEffective();
            }
            if(selectedUser) drawAssignment();
        }
    }
    async function load() {
        const token = ++epoch; contextKey = context(); snapshot = null;
        clear('Cargando administración…');
        if (!ready()) { clear('Esperá a que el contexto esté confirmado.'); return; }
        try {
            const data = await service.read(store.activeOrganizationId, search);
            if (service.invitation && mayInvite(data.rights)) {
                data.invitations = (await Promise.all([...(data.rights.global_users?[null]:[]),...(store.activeOrganizationId?[store.activeOrganizationId]:[])].map(org=>service.invitation('list',org)))).flat();
            }
            if (token !== epoch || contextKey !== context()) return;
            snapshot = data; render(data);
        } catch (error) { if (token === epoch) clear(error.message); }
    }
    store.subscribe(() => {
        if (contextKey !== context()) { ++epoch; snapshot = null; clear('El contexto cambió.'); if (ready()) load(); }
    });
    return { load, get snapshot() { return snapshot; } };
}

let mounted;
export function openAdministration(store) {
    const root = document.getElementById('mica-administration');
    if (!root) return;
    mounted ||= createAdministrationView(root, store);
    return mounted.load();
}
