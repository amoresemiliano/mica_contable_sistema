import { appStore } from './store.js';

// The previous implementation fabricated invoice amounts and providers.
// There is no real OCR upload/process/verify contract in this repository.
// Keep each action fail-closed until an approved backend is connected.
export function requireOcrAction(action, store = appStore) {
    if (!store.canOcrAction(action)) throw new Error('No tenés permiso para esta acción OCR en el contexto actual.');
    throw new Error('OCR pendiente de conexión al servicio real. No se generó ningún comprobante.');
}
export function setupOCR() {
    const input = document.getElementById('ocr-input');
    const status = document.getElementById('ocr-status-text');
    if (status) status.textContent = 'OCR pendiente de conexión al servicio real; no se procesan ni confirman documentos.';
    const select = file => {
        if (!appStore.canOcrAction('upload') || !file) return;
        if (status) status.textContent = `${file.name} seleccionado. OCR próximamente; el archivo no se subió ni procesó.`;
    };
    if (input) input.onchange = () => select(input.files?.[0]);
    const zone = document.getElementById('ocr-dropzone');
    if (zone) {
        zone.ondragover = event => event.preventDefault();
        zone.ondrop = event => { event.preventDefault(); select(event.dataTransfer.files?.[0]); };
    }
    appStore.tenantResetListeners.push(() => {
        if (input) input.value = '';
        if (status) status.textContent = 'OCR próximamente. Seleccioná una imagen o PDF.';
    });
}
export function renderOcrHistory() {
    const body = document.getElementById('ocr-history-table');
    if (!body) return;
    body.replaceChildren();
    const row = document.createElement('tr'), cell = document.createElement('td');
    cell.colSpan = 5;
    cell.textContent = 'Sin documentos OCR persistidos. Servicio pendiente de conexión.';
    row.append(cell); body.append(row);
}
