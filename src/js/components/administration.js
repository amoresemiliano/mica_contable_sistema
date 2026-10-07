import { openAdminDrawer } from './adminDrawer.js';
import { administrationService, editableCapabilities, assignmentPermissionPreview } from '../core/services/administrationService.js';
import { capabilityPresentation } from '../core/capabilityPresentation.js';
import { SCOPE_LABELS, PERMISSION_STATES, MICA_BUSINESS_FUNCTIONS, PERMISSION_GROUPS } from '../core/micaPermissionContract.js';

export function createAdministrationView(root, store, service = administrationService) {
    let epoch = 0, snapshot = null, busy = false, contextKey = '', search = '';
    let activeSection = '', selectedUser = '', selectedPreset = '', tabs, content, drawer;
    let userState = '', userOrg = '';
    let advancedSection = '', advancedOpen = false, activeCategorizationSubSection = 'Categorías';
    const categorizationCards = new Map();
    let adminTargetOrg = '', targetIdentity = '';
    const managementOrg = () => store.contextState === 'PLATFORM_READY' ? adminTargetOrg : store.activeOrganizationId;
    const tenantOrg = () => store.contextState === 'TENANT_READY' ? store.activeOrganizationId : null;
    function cacheCards() {
        for (const id of ['card-tax-categories', 'card-economic-activities', 'card-iibb-rates', 'card-iva-rates']) {
            if (!categorizationCards.has(id)) {
                const card = document.getElementById?.(id);
                if (card) categorizationCards.set(id, { card, home: card.parentNode });
            }
        }
    }
    function parkCards() {
        cacheCards();
        for (const { card, home } of categorizationCards.values()) home?.append(card);
    }
    function syncTargetIdentity() {
        const identity = [store.sessionUserId, store.contextState, store.activeOrganizationId].join('|');
        if (identity !== targetIdentity) {
            adminTargetOrg = ''; selectedUser = ''; selectedPreset = ''; advancedOpen = false;
            targetIdentity = identity;
        }
    }
    const el = (tag, text, props = {}) => {
        const node = document.createElement(tag);
        if (text !== null && text !== undefined) node.textContent = text;
        Object.assign(node, props);
        return node;
    };
    const context = () => [store.sessionUserId, store.contextGeneration, store.contextState, store.activeOrganizationId].join('|');
    const ready = () => ['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState);
    const mayInvite = rights => rights.global_users || (store.activeOrganizationId &&
        ['ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN'].every(code=>
            store.hasCapability?.(code,{scope:'ORGANIZATION',orgId:store.activeOrganizationId})));
    function clear(message) { parkCards(); drawer?.close(); drawer = null; root.replaceChildren(el('p', message, { role: 'status' })); }
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
    function section(title, parent = content) {
        const node = el('section', null, { className: 'mica-admin-panel', role: parent === content ? 'tabpanel' : 'region', id: parent === content ? 'mica-admin-content' : 'mica-admin-advanced-content' });
        node.setAttribute?.(parent === content ? 'aria-labelledby' : 'aria-label', parent === content ? 'mica-nav-' + activeSection.replaceAll(' ', '-') : title);
        node.actionHeader = el('header', null, {className:'mica-admin-heading'});
        node.actionHeader.append(el('h3', title)); node.append(node.actionHeader); parent.append(node); return node;
    }
    function table(parent, rows, columns, edit, customActions = false) {
        const table = el('table', null, { className: 'mica-admin-table' });
        const head = el('thead'), headings = el('tr');
        for (const [label] of columns) headings.append(el('th', label, { scope: 'col' }));
        if (edit) headings.append(el('th', 'Acciones', { scope: 'col' }));
        head.append(headings); table.append(head);
        const body = el('tbody'); table.append(body);
        for (const row of rows) {
            const tr = el('tr');
            for (const [,value] of columns) tr.append(el('td', value(row)));
            if (edit) {
                const td=el('td'), actions=customActions ? edit(row) : null;
                if (actions) td.append(actions);
                else { const button=el('button','Ver detalle',{type:'button'}); button.onclick=()=>edit(row); td.append(button); }
                tr.append(td);
            }
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
    const ICON_EYE = 'eye', ICON_PENCIL = 'pencil', ICON_TRASH = 'trash';
    function createIconButton(icon, label, title, action, danger = false) {
        const button = el('button', null, { type: 'button', title, className: 'mica-action-btn' + (danger ? ' mica-action-danger' : '') });
        button.setAttribute?.('aria-label', label);
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '18'); svg.setAttribute('height', '18');
        svg.setAttribute('fill', 'none'); svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '1.8');
        svg.setAttribute('aria-hidden', 'true');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('d', {
            eye: 'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
            pencil: 'm16 3 5 5-12 12-6 1 1-6L16 3Z M13 6l5 5',
            trash: 'M3 6h18 M9 6V3h6v3 M5 6l1 15h12l1-15 M10 10v7 M14 10v7'
        }[icon]);
        svg.append(path); button.append(svg); button.onclick = action; return button;
    }
    function renderPersistentHeader(data, onNewCompany) {
        const header = el('div', null, { className: 'mica-admin-persistent-header' });
        const leftGroup = el('div', null, { className: 'mica-admin-header-left' });
        const orgSelectorWrap = el('div', null, { className: 'mica-admin-org-selector' });
        
        const platform = store.contextState === 'PLATFORM_READY';
        const contextName = platform ? 'Vegen Platform' : (store.getActiveOrganizationName?.() || data.organizations.find(o => o.id === store.activeOrganizationId)?.name || 'Organización');
        orgSelectorWrap.append(el('span', 'Contexto: ' + contextName, { className: 'mica-admin-context' }));
        if (platform) {
        const orgSelectLabel = el('label', 'Empresa gestionada:', { className: 'mica-admin-org-label' });
        const selector = el('select', null, { className: 'mica-admin-org-select', name: 'administration-target' });
        selector.append(el('option', 'Seleccioná una empresa', { value: '' }));
        for (const o of data.organizations.filter(org => org.is_active)) {
            selector.append(el('option', o.name + (o.tax_id ? ` (${o.tax_id})` : ''), { value: o.id }));
        }
        selector.value = adminTargetOrg;
        selector.onchange = async () => {
            if (busy || !ready()) return;
            adminTargetOrg = data.organizations.some(o => o.id === selector.value && o.is_active) ? selector.value : '';
            root.dataset.catalogTarget = adminTargetOrg;
            try {
                globalThis.window?.handleCatalogTargetChange?.('all');
                render(data, false);
            } catch (error) {
                content?.append(el('p', error.message, { role: 'status' }));
            }
        };
        orgSelectLabel.append(selector); orgSelectorWrap.append(orgSelectLabel);
        }
        leftGroup.append(orgSelectorWrap);

        const navGroup = el('nav', null, { className: 'mica-admin-nav-group', role: 'tablist', ariaLabel: 'Secciones de administración' });
        const navSections = ['Empresas', 'Usuarios', 'Categorización'];
        
        navSections.forEach((secName, index) => {
            const btn = el('button', secName, {
                type: 'button',
                role: 'tab',
                className: 'mica-admin-nav-btn' + (secName === activeSection ? ' active' : ''),
                id: 'mica-nav-' + secName.replaceAll(' ', '-'),
                ariaSelected: String(secName === activeSection),
                tabIndex: secName === activeSection ? 0 : -1
            });
            btn.onclick = () => {
                activeSection = secName;
                render(data);
            };
            btn.setAttribute?.('aria-controls', 'mica-admin-content');
            btn.onkeydown = event => {
                const next = { ArrowRight: (index + 1) % 3, ArrowDown: (index + 1) % 3, ArrowLeft: (index + 2) % 3, ArrowUp: (index + 2) % 3, Home: 0, End: 2 }[event.key];
                if (next === undefined) return;
                event.preventDefault(); activeSection = navSections[next]; render(data);
                tabs.children[next]?.focus?.();
            };
            navGroup.append(btn);
        });
        tabs = navGroup;
        leftGroup.append(navGroup);
        header.append(leftGroup);

        if (data.rights?.create_organization) {
            const rightGroup = el('div', null, { className: 'mica-admin-header-right' });
            const newCompanyBtn = el('button', '+ Nueva Empresa', {
                type: 'button',
                className: 'btn-primary mica-admin-new-company-btn'
            });
            newCompanyBtn.onclick = onNewCompany;
            rightGroup.append(newCompanyBtn);
            header.append(rightGroup);
        }

        return header;
    }

    function renderCompanyDetailModal(o) {
        const modal = el('dialog', null, { className: 'mica-company-detail-card' });
        const title = el('h3', o.name || 'Detalle de la empresa');
        const closeBtn = el('button', '×', { type: 'button', className: 'mica-modal-close' });
        closeBtn.onclick = () => modal.remove();
        
        const detailsList = el('dl', null, { className: 'mica-company-detail-list' });
        const fields = [
            ['Razón Social', o.legal_name || o.name || '—'],
            ['CUIT', o.tax_id || '—'],
            ['Teléfono', o.phone || '—'],
            ['Email', o.email || '—'],
            ['Contacto', o.contact_person || '—'],
            ['Website', o.website || '—'],
            ['Domicilio', o.address || '—']
        ];
        fields.forEach(([label, val]) => {
            detailsList.append(el('dt', label), el('dd', val));
        });
        modal.append(closeBtn, title, detailsList);
        root.append(modal);
        if (modal.showModal) modal.showModal();
    }

    function editCompanyForm(o = {}) {
        const editor = openEditor(o.id ? 'Editar empresa' : 'Nueva empresa');
        const f = form(editor, o.id ? 'Editar datos de empresa' : 'Crear nueva empresa', fd => {
            const payload = o.id ? { id: o.id } : {};
            payload.name = fd.get('name');
            payload.legal_name = fd.get('legal_name');
            payload.trade_name = fd.get('trade_name');
            payload.tax_id = fd.get('tax_id');
            for (const key of ['phone', 'email', 'contact_person', 'website', 'address']) payload[key] = fd.get(key);
            return service.apply('organization', payload);
        });
        field(f, 'name', 'Nombre', o.name).required = true;
        field(f, 'legal_name', 'Razón social', o.legal_name);
        field(f, 'trade_name', 'Nombre comercial', o.trade_name);
        field(f, 'tax_id', 'CUIT', o.tax_id);
        field(f, 'phone', 'Teléfono', o.phone || '');
        field(f, 'email', 'Email', o.email || '');
        field(f, 'contact_person', 'Contacto', o.contact_person || '');
        field(f, 'website', 'Website', o.website || '');
        field(f, 'address', 'Domicilio', o.address || '');
    }

    async function archiveCompany(o) {
        if (confirm(`¿Deseás archivar la empresa "${o.name}"?`)) {
            try {
                await service.apply('organization', { id: o.id, is_active: false });
                if (store.reloadOperationalContext) await store.reloadOperationalContext();
                await load();
            } catch (err) {
                alert(err.message || 'No se pudo archivar la empresa.');
            }
        }
    }

    function renderPrimary(data, refreshCatalog = true) {
        const r = data.rights, org = managementOrg();
        const validSections = ['Empresas', 'Usuarios', 'Categorización'];
        if (!validSections.includes(activeSection)) activeSection = 'Empresas';

        content = el('div', null, { className: 'mica-admin-content' });
        root.append(renderPersistentHeader(data, () => editCompanyForm()), content);

        const s = section(activeSection);

        // SECTION 1: EMPRESAS
        if (activeSection === 'Empresas') {
            table(s, data.organizations, [
                ['Empresa', o => o.name],
                ['CUIT', o => o.tax_id || '—'],
                ['Estado', o => o.is_active ? 'Activa' : 'Inactiva']
            ], o => {
                const group = el('div', null, { className: 'mica-action-btn-group' });
                
                const viewBtn = createIconButton(ICON_EYE, `Ver detalle de ${o.name}`, 'Ver detalle', () => renderCompanyDetailModal(o));
                group.append(viewBtn);

                if (r.update_organization) {
                    const editBtn = createIconButton(ICON_PENCIL, `Editar ${o.name}`, 'Editar', () => editCompanyForm(o));
                    group.append(editBtn);
                }

                if (r.archive_organization) {
                    const trashBtn = createIconButton(ICON_TRASH, `Archivar ${o.name}`, 'Archivar', () => archiveCompany(o), true);
                    group.append(trashBtn);
                }

                return group;
            }, true);
            s.append(el('p', 'Seleccioná una empresa para administrar sus datos operativos, usuarios y categorización.'));
            return;
        }

        // SECTION 2: USUARIOS
        if (activeSection === 'Usuarios') {
            renderAdvancedEntry(s, data);
            if (!org) {
                s.append(el('p', 'Seleccioná una empresa gestionada para ver y gestionar sus usuarios.'));
                return;
            }
            const presets = data.presets.filter(p => p.scope === 'ORGANIZATION' && p.is_active && (!p.organization_id || p.organization_id === org));
            const members = data.memberships.filter(m => m.organization_id === org);
            const orgUsers = data.users.filter(u => !u.protected && members.some(m => m.user_profile_id === u.id));

            table(s, orgUsers, [
                ['Usuario', u => u.name || u.email.split('@')[0]],
                ['Email', u => u.email],
                ['Rol / Perfil', u => {
                    const m = members.find(mem => mem.user_profile_id === u.id);
                    return presets.find(p => p.id === m?.role_template_id)?.name || 'Usuario';
                }],
                ['Estado en empresa', u => members.find(m => m.user_profile_id === u.id)?.is_active ? 'Activo' : 'Inactivo']
            ], r.memberships && tenantOrg() ? user => {
                const group = el('div', null, { className: 'mica-action-btn-group' });
                const member = members.find(m => m.user_profile_id === user.id);
                
                const editRoleBtn = createIconButton(ICON_PENCIL, `Editar rol de ${user.email}`, 'Cambiar rol', () => {
                    const editor = openEditor(`Editar rol: ${user.email}`);
                    const f = form(editor, 'Perfil y estado en empresa', fd => service.apply('membership', {
                        organization_id: org, user_profile_id: user.id, role_template_id: fd.get('preset'), is_active: fd.get('active') === 'true'
                    }));
                    field(f, 'preset', 'Perfil existente', member?.role_template_id || '', options(presets));
                    choice(f, 'active', 'Estado en empresa', member?.is_active);
                    if (user.pending) form(editor, 'Activar cuenta invitada en esta empresa', () => service.apply('tenant_activate', { organization_id: org, user_profile_id: user.id }));
                });
                group.append(editRoleBtn);

                if (member) {
                    const toggleAccessBtn = createIconButton(ICON_TRASH, `Quitar acceso a ${user.email}`, 'Quitar acceso', async () => {
                        if (confirm(`¿Deseás desactivar el acceso de ${user.email} en esta empresa?`)) {
                            await service.apply('membership', {
                                organization_id: org, user_profile_id: user.id, role_template_id: member.role_template_id, is_active: false
                            });
                            await load();
                        }
                    }, true);
                    group.append(toggleAccessBtn);
                }

                return group;
            } : null, true);

            if (!tenantOrg()) s.append(el('p', 'Los cambios de membresía y las invitaciones a esta empresa requieren su contexto operativo.'));
            if (r.memberships && tenantOrg() && service.invitation && mayInvite(r)) {
                const b = el('button', '+ Invitar usuario', { type: 'button', className: 'btn-primary' });
                b.onclick = () => {
                    const editor = openEditor('Invitar usuario');
                    const f = form(editor, 'Invitar', fd => service.invitation('create', org, { email: fd.get('email'), role_template_id: fd.get('preset') }));
                    field(f, 'email', 'Email').required = true;
                    field(f, 'preset', 'Perfil existente', '', options(presets));
                    f.append(el('p', 'Compartí el acceso habitual de MICA. Tras registrarse y confirmar su email, confirmá la asignación y activá la cuenta.'));
                };
                s.actionHeader.append(b);

                if (data.invitations && data.invitations.length > 0) {
                    list(s, data.invitations.filter(i => i.organization_id === org), i => i.email + ' · ' + (i.assigned_at ? 'Asignada' : i.user_profile_id ? 'Confirmar asignación' : 'Esperando registro'), i => {
                        const editor = openEditor(i.email);
                        if (i.user_profile_id && !i.assigned_at) form(editor, 'Confirmar asignación', () => service.invitation('assign', org, { id: i.id, user_profile_id: i.user_profile_id }));
                        else editor.append(el('p', 'La cuenta debe registrarse y confirmar su email antes de asignarla.'));
                    });
                }
            }

            return;
        }

        // SECTION 3: CATEGORIZACIÓN
        if (activeSection === 'Categorización') {
            const subNav = el('nav', null, { className: 'mica-admin-subnav-group', ariaLabel: 'Secciones de categorización' });
            const subSections = [
                { id: 'Categorías', label: 'Categorías' },
                { id: 'Actividades', label: 'Actividades' },
                { id: 'Impuestos', label: 'Impuestos' }
            ];
            
            subSections.forEach(({ id, label }) => {
                const subBtn = el('button', label, {
                    type: 'button',
                    className: 'mica-admin-subnav-btn' + (activeCategorizationSubSection === id ? ' active' : ''),
                    ariaSelected: String(activeCategorizationSubSection === id)
                });
                subBtn.onclick = () => {
                    activeCategorizationSubSection = id;
                    render(data);
                };
                subNav.append(subBtn);
            });
            s.append(subNav);

            const catContainer = el('div', null, { id: 'mica-categorizacion-subview' });
            s.append(catContainer);

            cacheCards();
            const taxCatCard = categorizationCards.get('card-tax-categories')?.card;
            const econActCard = categorizationCards.get('card-economic-activities')?.card;
            const iibbCard = categorizationCards.get('card-iibb-rates')?.card;
            const ivaCard = categorizationCards.get('card-iva-rates')?.card;
            const platform = store.contextState === 'PLATFORM_READY';
            const globalCatalog = platform && store.isCatalogPlatformContext?.();
            if (platform && !org) s.append(el('p', 'Seleccioná una empresa para gestionar sus categorías, actividades e impuestos.', { role: 'status' }));
            if (platform && !globalCatalog && activeCategorizationSubSection !== 'Impuestos') {
                s.append(el('p', 'No hay permisos de catálogo global disponibles en este contexto.')); return;
            }

            if (activeCategorizationSubSection === 'Categorías') {
                if (taxCatCard) catContainer.append(taxCatCard);
                if (refreshCatalog) refreshCatalogData(() => store.loadTaxCategories?.(), catContainer);
            } else if (activeCategorizationSubSection === 'Actividades') {
                if (econActCard) catContainer.append(econActCard);
                if (refreshCatalog) refreshCatalogData(() => store.loadEconomicActivities?.(), catContainer);
            } else if (activeCategorizationSubSection === 'Impuestos') {
                if (!platform && iibbCard) catContainer.append(iibbCard);
                if (platform) catContainer.append(el('p', 'La gestión de tasas IIBB requiere el contexto operativo de la empresa. La selección de empresa gestionada no cambia ese contexto.'));
                if (ivaCard) catContainer.append(ivaCard);
                if (refreshCatalog && !platform) refreshCatalogData(() => store.loadIibbRates?.(), catContainer);
            }
            globalThis.window?.UIManager?.renderSettings?.();

            return;
        }
    }
    function refreshCatalogData(refresh, container) {
        const token = epoch;
        Promise.resolve().then(refresh).catch(error => {
            if (token === epoch && root.contains(container)) container.append(el('p', error.message, { role: 'status' }));
        });
    }
    function render(data, refreshCatalog = true) {
        // Deprecated presets remain in server history, never in assignment/edit controls.
        data={...data,presets:data.presets.filter(p=>p.code!=='ACCOUNTING_SUPERADMIN')};
        parkCards(); drawer?.close(); drawer = null; root.replaceChildren();
        root.dataset ||= {};
        root.dataset.catalogManagement = store.contextState === 'PLATFORM_READY' ? 'true' : 'false';
        root.dataset.catalogTarget = adminTargetOrg;
        if (!Object.values(data.rights).some(Boolean)) { clear('No tenés permisos de administración en este contexto.'); return; }
        renderPrimary(data, refreshCatalog);
        if (data.invitationError) content?.append(el('p', 'Invitaciones: ' + data.invitationError, { role: 'status' }));
    }
    function renderAdvancedEntry(parent, data) {
        const r = data.rights;
        if (!r.presets && !r.assignments && !(r.users && r.global_users)) return;
        const button = el('button', 'Permisos avanzados', { type: 'button', className: 'mica-admin-advanced-toggle' });
        button.setAttribute?.('aria-expanded', String(advancedOpen));
        button.setAttribute?.('aria-controls', 'mica-admin-advanced');
        button.onclick = () => { advancedOpen = !advancedOpen; render(data); };
        parent.actionHeader.append(button);
        if (advancedOpen) {
            const advancedContent = el('div', null, { id: 'mica-admin-advanced', className: 'mica-admin-advanced' });
            parent.append(advancedContent); renderAdvanced(data, advancedContent);
        }
    }
    function renderAdvanced(data, advancedContent) {
        const { rights: r, organizations, users, presets, capabilities } = data;
        const available = [[r.users && r.global_users,'Usuarios'],[r.presets,'Roles y permisos'],[r.assignments,'Asignaciones']]
            .filter(([allowed])=>allowed).map(([,title])=>title);
        if (!available.includes(advancedSection)) advancedSection = available[0];
        const nav = el('nav', null, { className: 'mica-admin-advanced-nav', ariaLabel: 'Herramientas avanzadas' });
        for (const title of available) {
            const button = el('button', title === 'Usuarios' ? 'Usuarios de plataforma' : title, { type: 'button', ariaPressed: String(title === advancedSection) });
            button.onclick = () => { advancedSection = title; render(data); };
            nav.append(button);
        }
        advancedContent.append(nav);
        if (r.users && advancedSection === 'Usuarios') {
            const s = section('Usuarios de plataforma', advancedContent);
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
                        fd.get('scope') === 'PLATFORM' ? null : tenantOrg(),
                        {email:fd.get('email'),role_template_id:fd.get('preset')}));
                    const email = field(f,'email','Email'); email.type='email'; email.required=true;
                    const scope=field(f,'scope','Tipo',tenantOrg()?'ORGANIZATION':'PLATFORM',[
                        ...(tenantOrg() ? [['ORGANIZATION',SCOPE_LABELS.ORGANIZATION]] : []),...(r.global_users ? [['PLATFORM',SCOPE_LABELS.PLATFORM]] : [])]);
                    const preset=field(f,'preset','Preset','',[]);
                    const draw=()=>{preset.replaceChildren(...presets.filter(p=>p.is_active&&p.scope===scope.value&&
                        (!p.organization_id||p.organization_id===managementOrg())).map(p=>el('option',p.name,{value:p.id})));};
                    scope.onchange=draw; draw();
                    f.append(el('p','Organización: '+(organizations.find(o=>o.id===managementOrg())?.name||'Seleccioná una empresa en el selector superior')+'. Para otra empresa, cambiá el contexto antes de invitar.'));
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
                        user_profile_id:user.id,organization_id:tenantOrg(),is_active:fd.get('active')==='true'
                    }));choice(f,'active','Estado',user.is_active); }
                    if(r.assignments) {const assign=el('button','Preset y permisos',{type:'button'});
                        assign.onclick=()=>{selectedUser=user.id;advancedSection='Asignaciones';render(data);};editor.append(assign);}
                }); };
            state.onchange=()=>{userState=state.value;drawUsers();};organization.onchange=()=>{userOrg=organization.value;drawUsers();};drawUsers();
            if (users.length === 200) s.append(el('p', 'Se muestran 200 usuarios. Refiná la búsqueda.'));
        }
        if (r.presets && advancedSection === 'Roles y permisos') {
            const s = section('Roles y permisos', advancedContent);
            s.append(el('p', 'Presets MICA reutilizables. Los templates históricos no se editan desde esta pantalla.'));
            const split=el('div',null,{className:'mica-preset-split'}), master=el('div',null,{className:'mica-preset-list'}), editor=el('div',null,{className:'mica-admin-editor'});
            split.append(master,editor);s.append(split);
            function edit(row = {}) {
                editor.replaceChildren();
                if (row.organization_id && row.organization_id !== tenantOrg()) {
                    editor.append(el('p', 'La edición de este preset requiere el contexto operativo de su empresa.'));
                    return;
                }
                const f = form(editor, row.id ? 'Editar preset' : 'Crear preset', fd => service.apply('preset', {
                    id: row.id || null, organization_id: row.id ? row.organization_id : (r.global_presets ? null : tenantOrg()),
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
            const visiblePresets=presets.filter(p => r.global_presets || p.organization_id === managementOrg());
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
        if (r.assignments && advancedSection === 'Asignaciones') {
            const s = section('Asignaciones', advancedContent);
            const candidates=users.filter(u=>!u.protected);
            if(!candidates.some(u=>u.id===selectedUser)) selectedUser='';
            table(s,candidates,[['Usuario',u=>u.email],['Estado',u=>u.is_active?'Activo':'Inactivo']],user=>{selectedUser=user.id;drawAssignment();});
            function drawAssignment() {
            const panel=openEditor(users.find(u=>u.id===selectedUser)?.email||'Asignación');
            const editable = candidates.filter(u=>u.id===selectedUser);
            if (!editable.length) { panel.append(el('p', 'Buscá un usuario administrable.')); return; }
            const org = tenantOrg();
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
            if (!org) panel.append(el('p', 'Las membresías requieren el contexto operativo de la empresa.'));
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
                user_profile_id: fd.get('user'), kind: fd.get('kind'), organization_id: fd.get('kind') === 'platform' ? null : fd.get('kind') === 'platform_org' ? managementOrg() : org,
                capability: fd.get('capability'), effect: fd.get('effect')
            }));
            const who = field(of, 'user', 'Usuario', '', options(editable, 'email'));
            const kind = field(of, 'kind', 'Tipo', '', r.global_users ?
                [['platform', 'Plataforma'], ...(org ? [['membership', 'Membership']] : []), ...(managementOrg() ? [['platform_org', 'Plataforma en organización']] : [])] : [['membership', 'Membership']]);
            const cap = field(of, 'capability', 'Permiso', '', []);
            field(of, 'effect', 'Excepción individual', 'INHERITED', Object.entries(PERMISSION_STATES));
            const preview = el('p'); of.append(preview);
            function showPreview() {
                const state = assignmentPermissionPreview(data, who.value, kind.value === 'platform_org' ? managementOrg() : org,
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
                for (const scope of ['PLATFORM','ORGANIZATION']) {
                results.append(el('h4', scope === 'PLATFORM' ? 'Permisos de plataforma' : 'Permisos de organización'));
                if (scope === 'ORGANIZATION' && !org) {
                    results.append(el('p', 'Seleccioná una organización para consultar sus permisos efectivos.'));
                    continue;
                }
                list(results, capabilities.filter(c => editableCapabilities([c],c.scope,'PLATFORM_BRIDGE').length &&
                    c.scope === scope &&
                    (c.code + ' ' + capabilityPresentation(c).label).toLowerCase().includes(filter.value.toLowerCase())), c => {
                    const state = assignmentPermissionPreview(data, selectedUser, org, c);
                    return capabilityPresentation(c).label + ' · Efectivo: ' +
                        (state.unknown ? 'No calculado' : state.effective ? 'Permitido' : 'Denegado') + ' · ' + PERMISSION_STATES[state.effect];
                });
                }
            };
            filter.oninput = drawEffective; drawEffective();
            }
            if(selectedUser) drawAssignment();
        }
    }
    async function load(route = {}) {
        syncTargetIdentity();
        if (['Empresas', 'Usuarios', 'Categorización'].includes(route.section)) activeSection = route.section;
        const token = ++epoch; contextKey = context(); snapshot = null;
        clear('Cargando administración…');
        if (!ready()) { clear('Esperá a que el contexto esté confirmado.'); return; }
        try {
            const data = await service.read(store.activeOrganizationId, search);
            if (token !== epoch || contextKey !== context()) return;
            if (adminTargetOrg && !data.organizations.some(o => o.id === adminTargetOrg && o.is_active)) adminTargetOrg = '';
            if (service.invitation && mayInvite(data.rights)) {
                const target = tenantOrg();
                data.invitations = [];
                try {
                    data.invitations = (await Promise.all([...(data.rights.global_users?[null]:[]),...(target?[target]:[])].map(org=>service.invitation('list',org)))).flat();
                } catch (error) { data.invitationError = error.message; }
            }
            if (token !== epoch || contextKey !== context()) return;
            snapshot = data; render(data);
        } catch (error) { if (token === epoch) clear(error.message); }
    }
    store.subscribe(() => {
        if (contextKey !== context()) { syncTargetIdentity(); root.dataset ||= {}; root.dataset.catalogTarget = ''; root.dataset.catalogManagement = 'false'; ++epoch; snapshot = null; clear('El contexto cambió.'); if (ready()) load(); }
    });
    return { load, get snapshot() { return snapshot; } };
}

let mounted;
export function openAdministration(store, route = { section: 'Empresas' }) {
    const root = document.getElementById('mica-administration');
    if (!root) return;
    mounted ||= createAdministrationView(root, store);
    return mounted.load(route);
}
