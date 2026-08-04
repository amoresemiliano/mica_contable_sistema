import { appStore } from './store.js';

// 4. LÓGICA DE PROCESAMIENTO OCR (SOLID: Single Responsibility / Interface Segregation)
export function setupOCR() {
    const ocrInput = document.getElementById('ocr-input');
    if (!ocrInput) return;

    ocrInput.addEventListener('change', function(e) {
        const file = e.target.files[0];
        if (!file) return;

        const progressContainer = document.getElementById('ocr-progress-container');
        const progressBar = document.getElementById('ocr-progressbar');
        const statusText = document.getElementById('ocr-status-text');

        progressContainer.style.display = 'block';
        progressBar.style.width = '0%';
        
        // Secuencias del simulador en tiempo real
        const steps = [
            { pct: 20, txt: "Leyendo archivo digital..." },
            { pct: 50, txt: "Aplicando OCR / Identificando patrones fiscales..." },
            { pct: 80, txt: "Verificando CUITs de proveedor en ARCA/AFIP..." },
            { pct: 100, txt: "Extracción completa exitosa." }
        ];

        let stepIdx = 0;
        const interval = setInterval(() => {
            if (stepIdx < steps.length) {
                progressBar.style.width = `${steps[stepIdx].pct}%`;
                statusText.innerText = steps[stepIdx].txt;
                stepIdx++;
            } else {
                clearInterval(interval);
                
                // Incorporación del ticket detectado al flujo general del sistema
                const randomAmount = Math.floor(Math.random() * (15000 - 3000 + 1)) + 3000;
                const mockInvoice = {
                    id: `ocr-${Date.now()}`,
                    tipo: "recibido",
                    fecha: new Date().toISOString().split('T')[0],
                    comprobante: "C - Factura",
                    cuit: "30506733524",
                    razonSocial: "ESTACION DE SERVICIO YPF SA",
                    total: randomAmount,
                    categoria: "Movilidad y Viáticos",
                    sugerida: true,
                    confirmada: false
                };

                // Agrega la carga al listado e historial del sistema
                appStore.items.push(mockInvoice);
                appStore.ocrHistory.unshift({
                    fecha: mockInvoice.fecha,
                    proveedor: mockInvoice.razonSocial,
                    cuit: mockInvoice.cuit,
                    total: mockInvoice.total,
                    estado: "✓ Procesado"
                });

                // Notificamos el cambio de estado para actualizar las vistas reactivamente
                appStore.notify();
                
                alert(`OCR procesado: Se detectó un ticket de ${mockInvoice.razonSocial} por $ ${mockInvoice.total}. Se sumó como gasto pendiente en tu bandeja.`);
                
                progressContainer.style.display = 'none';
                statusText.innerText = "";
            }
        }, 800);
    });
}

export function renderOcrHistory() {
    const tableBody = document.getElementById('ocr-history-table');
    if (!tableBody) return;
    
    if (appStore.ocrHistory.length === 0) {
        tableBody.innerHTML = `<tr><td colspan="5" style="text-align: center; color: var(--text-muted); padding: 20px;">No hay documentos escaneados recientemente.</td></tr>`;
        return;
    }

    tableBody.innerHTML = appStore.ocrHistory.map(doc => `
        <tr>
            <td>${doc.fecha}</td>
            <td><strong>${doc.proveedor}</strong></td>
            <td>${doc.cuit}</td>
            <td>$ ${doc.total.toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
            <td style="color: var(--success); font-weight: 600;">${doc.estado}</td>
        </tr>
    `).join('');
}
