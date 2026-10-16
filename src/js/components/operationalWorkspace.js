const modules = {
    'tab-conciliador': {id:'comprobantes',title:'Comprobantes',imports:[['recibidos','Recibidos / Compras'],['emitidos','Emitidos / Ventas']]},
    'tab-percepciones': {id:'percepciones',title:'Percepciones',imports:[['percepciones','ARBA / IVA (TXT, CSV, XLS, XLSX)']]},
    'tab-bancos': {id:'bancos',title:'Bancos / Extractos',imports:[['bancos','Extracto bancario (XLS, XLSX)']]},
    'tab-sueldos': {id:'sueldos',title:'Sueldos',imports:[['sueldos','Nómina consolidada (XLS, XLSX)']]}
};
export function mountOperationalWorkspaces(store, document) {
    for (const [sectionId, config] of Object.entries(modules)) {
        const section = document.getElementById(sectionId);
        if (!section || section.dataset.workspace) continue;
        section.dataset.workspace = config.id;
        const context = section.querySelector('.operational-context-toolbar');
        const title = document.createElement('h2'); title.textContent=config.title;
        context?.prepend(title);
        const identity = document.createElement('span'); identity.className='workspace-user';context?.append(identity);
        const body = section.querySelector('.operational-module-body') || section;
        if(config.id==='sueldos') {
            const detail=document.getElementById('salary-detail-container')?.closest('.card');
            if(detail)body.prepend(detail);
        }
        let toolbar = body.querySelector('.operational-toolbar');
        if (!toolbar) { toolbar=document.createElement('div');toolbar.className='operational-toolbar';body.prepend(toolbar); }
        toolbar.classList.add('workspace-toolbar');
        // Preserve existing input elements, IDs and drop listeners inside a compact panel.
        const importer = document.createElement('details');importer.className='workspace-menu workspace-import';
        const summary=document.createElement('summary');summary.className='btn-primary';summary.textContent='Importar';importer.append(summary);
        const panel=document.createElement('div');panel.className='workspace-menu-panel';importer.append(panel);
        for (const [zoneId,label] of config.imports) {
            const zone=document.getElementById('zone-'+zoneId),input=document.getElementById('file-'+zoneId);
            if (!zone || !input) continue;
            const button=document.createElement('button');button.type='button';button.className='btn-secondary';button.textContent=label;
            button.dataset.importInput=input.id;
            button.onclick=()=>{ if(!input.disabled)input.click(); };
            zone.prepend(button); panel.append(zone);
        }
        for (const empty of body.querySelectorAll('.import-section')) if (!empty.querySelector('.drop-zone')) empty.remove();
        const download=document.createElement('details');download.className='workspace-menu workspace-download';
        const label=document.createElement('summary');label.className='btn-secondary';label.textContent='Descargar';download.append(label);
        const options=document.createElement('div');options.className='workspace-menu-panel';download.append(options);
        for (const [format,text] of [['csv','CSV'],['xlsx','Excel'],['pdf','PDF']]) {
            const button=document.createElement('button');button.type='button';button.className='btn-secondary';
            button.textContent=text;button.dataset.moduleExport=config.id;button.dataset.exportFormat=format;button.disabled=true;
            button.onclick=()=>globalThis.window.downloadOperationalModule(config.id,format);options.append(button);
        }
        body.querySelectorAll('.module-export-actions').forEach(el=>el.remove());
        if(config.id==='bancos')body.querySelector('[onclick="appStore.exportBankMovements()"]')?.remove();
        toolbar.children[0]?.classList.add('workspace-filters');
        toolbar.children[1]?.classList.add('workspace-search');
        const actions=document.createElement('div');actions.className='workspace-actions';actions.append(importer,download);
        toolbar.append(actions);
        // Filters come first; data follows immediately, retaining existing summaries and bulk controls.
        body.prepend(toolbar);
        body.querySelectorAll('.data-table-container').forEach(el=>el.classList.add('workspace-table-viewport'));
    }
    const render=()=>{
        for(const section of document.querySelectorAll('[data-workspace]')) {
            const badge=section.querySelector('.workspace-user');
            if(badge)badge.textContent=store.sessionUserId ? `${store.sessionEmail} · ${store.effectiveProfileName || 'Permisos personalizados'}` : '';
            const importer=section.querySelector('.workspace-import');
            if(importer)importer.hidden=![...importer.querySelectorAll('input[type=file]')].some(input=>!input.disabled);
            const download=section.querySelector('.workspace-download');
            if(download)download.hidden=!store.canOperationalAction('export');
            section.querySelectorAll('[data-import-input]').forEach(button=>button.disabled=document.getElementById(button.dataset.importInput).disabled);
        }
    };
    store.subscribe(render);render();
    return render;
}

export function nativeModuleClick(event, navigate, id) {
    if(event.button!==0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)return;
    event.preventDefault();navigate(id);
}
export function mountModuleLinks(document, navigate, window) {
    for(const link of document.querySelectorAll('.sidebar-nav a[onclick]')) {
        const id=link.getAttribute('onclick')?.match(/switchTab\(['"]([^'"]+)/)?.[1];if(!id)continue;
        link.href='#'+id;link.dataset.tab=id;link.removeAttribute('onclick');
        link.onclick=event=>nativeModuleClick(event,navigate,id);
    }
    const route=()=>{const id=window.location.hash.slice(1);const target=document.getElementById(id);if(target?.classList.contains('tab-content') && target.classList.contains('hidden'))navigate(id);};
    window.addEventListener('hashchange',route);return route;
}
