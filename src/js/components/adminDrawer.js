export function openAdminDrawer(root, title, document = globalThis.document) {
    const opener = document.activeElement;
    const dialog = document.createElement('dialog');
    dialog.className = 'mica-admin-drawer';
    dialog.setAttribute?.('aria-label', title);
    const header = document.createElement('header');
    const heading = document.createElement('h3'); heading.textContent = title;
    const close = document.createElement('button'); close.type = 'button'; close.textContent = 'Cerrar';
    close.setAttribute?.('aria-label', 'Cerrar panel');
    const body = document.createElement('div'); body.className = 'mica-admin-editor';
    header.append(heading, close); dialog.append(header, body); root.append(dialog);
    function dismiss() { dialog.close?.(); dialog.remove?.(); opener?.focus?.(); }
    close.onclick = dismiss;
    dialog.addEventListener('cancel', event => { event.preventDefault(); dismiss(); });
    // Native modal supplies inert background; explicitly cycle focus for keyboard navigation.
    dialog.addEventListener('keydown', event => {
        if (event.key === 'Escape') { event.preventDefault(); dismiss(); return; }
        if (event.key !== 'Tab') return;
        const focusable = [...dialog.querySelectorAll('button,input,select,textarea,a[href],[tabindex="0"]')]
            .filter(node => !node.disabled && !node.closest('[hidden]') && node.getClientRects().length);
        const first = focusable[0], last = focusable.at(-1);
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    });
    dialog.showModal?.(); close.focus?.();
    return { body, close: dismiss };
}
