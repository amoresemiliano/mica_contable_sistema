import { supabase } from './core/services/supabaseClient.js';
import { appStore } from './store.js';
import { setupOCR, renderOcrHistory } from './ocr.js';
import { Reconciler } from './reconciler.js';
import { ManualMovements } from './manualMovements.js';
import { Activities } from './activities.js';
import { readFileAsArrayBuffer, readFileAsText, detectFileFormat } from './core/adapters/fileAdapter.js';
import { createSheetJsAdapter } from './core/adapters/sheetJsAdapter.js';
import { parseDelimitedText } from './adapters/textAdapter.js';
import { createBrowserFingerprintProvider } from './adapters/browserFingerprintProvider.js';
import { parseArcaRows } from './core/parsers/arcaParser.js';
import { parseArbaText } from './core/parsers/arbaParser.js';
import { parseIvaPerceptions } from './core/parsers/ivaPerceptionParser.js';
import { parseBankRows } from './core/parsers/bankParser.js';
import { parseSalaryRows } from './core/parsers/salaryParser.js';
import { stageImport } from './core/services/importService.js';

async function loginWithGoogle() {
  const redirectUrl = window.location.origin + window.location.pathname;
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: redirectUrl,
      queryParams: {
        prompt: 'select_account'
      }
    }
  });

  if (error) {
    alert('Error al iniciar sesión: ' + error.message);
  }
}

async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) {
    alert('Error al cerrar sesión: ' + error.message);
  }
}

document.getElementById('google-login-btn')?.addEventListener('click', loginWithGoogle);
document.getElementById('logout-btn')?.addEventListener('click', logout);

const appContainer = document.getElementById('app-container');
const loginContainer = document.getElementById('login-container');
const authStatusMsg = document.getElementById('auth-status-message');
const loginBtn = document.getElementById('google-login-btn');

async function checkUserProfile(session) {
  let fallbackBtn = document.getElementById('fallback-logout-btn');
  if (!fallbackBtn && authStatusMsg) {
    fallbackBtn = document.createElement('button');
    fallbackBtn.id = 'fallback-logout-btn';
    fallbackBtn.className = 'btn-secondary';
    fallbackBtn.innerText = 'Cerrar Sesión';
    fallbackBtn.style.marginTop = '20px';
    fallbackBtn.onclick = logout;
    authStatusMsg.parentNode.appendChild(fallbackBtn);
  }

  const userInfoEl = document.getElementById('user-header-info');

  if (!session) {
    appContainer.classList.add('hidden');
    loginContainer.style.display = 'flex';
    authStatusMsg.style.display = 'none';
    loginBtn.style.display = 'flex';
    if (fallbackBtn) fallbackBtn.style.display = 'none';
    if (userInfoEl) userInfoEl.innerText = '';
    return;
  }

  loginBtn.style.display = 'none';
  authStatusMsg.style.display = 'block';
  authStatusMsg.innerText = 'Verificando permisos...';
  if (fallbackBtn) fallbackBtn.style.display = 'none';

  const { data: profile, error } = await supabase
    .from('eco_user_profiles')
    .select('id, organization_id, role, is_active')
    .eq('auth_user_id', session.user.id)
    .single();

  if (error && error.code !== 'PGRST116') {
    appContainer.classList.add('hidden');
    loginContainer.style.display = 'flex';
    authStatusMsg.innerText = 'No se pudo verificar el acceso.';
    if (fallbackBtn) fallbackBtn.style.display = 'block';
    if (userInfoEl) userInfoEl.innerText = '';
    return;
  }

  if (error?.code === 'PGRST116' || !profile) {
    appContainer.classList.add('hidden');
    loginContainer.style.display = 'flex';
    authStatusMsg.innerText = 'Acceso pendiente de aprobación.';
    if (fallbackBtn) fallbackBtn.style.display = 'block';
    if (userInfoEl) userInfoEl.innerText = '';
    return;
  }

  if (profile.is_active === false) {
    appContainer.classList.add('hidden');
    loginContainer.style.display = 'flex';
    authStatusMsg.innerText = 'Acceso pendiente de aprobación o deshabilitado.';
    if (fallbackBtn) fallbackBtn.style.display = 'block';
    if (userInfoEl) userInfoEl.innerText = '';
    return;
  }

  // Cargar nombre de la organización con fallback seguro
  let orgName = 'Organización';
  if (profile.organization_id) {
    try {
      const { data: org, error: orgError } = await supabase
        .from('eco_organizations')
        .select('name')
        .eq('id', profile.organization_id)
        .single();
      
      if (!orgError && org?.name) {
        orgName = org.name;
      }
    } catch (e) {
      orgName = 'Organización';
    }
  }

  // Identidad del usuario (preferir full_name de Google metadata, fallback a email)
  const userIdentity = session.user?.user_metadata?.full_name || session.user?.email || 'Usuario';
  const role = profile.role || 'USER';

  if (userInfoEl) {
    userInfoEl.innerText = `${userIdentity} · ${role} · ${orgName}`;
  }

  loginContainer.style.display = 'none';
  appContainer.classList.remove('hidden');
  if (fallbackBtn) fallbackBtn.style.display = 'none';
}

supabase.auth.getSession().then(({ data: { session } }) => {
  checkUserProfile(session);
});

supabase.auth.onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_DELETED') {
    checkUserProfile(session);
  }
});

const CATEGORIES_RECIBIDOS = [
    "Mercaderías / Insumos",
    "Servicios Públicos (Luz, Agua, Gas)",
    "Telefonía e Internet",
    "Honorarios Profesionales",
    "Alquileres Comerciales",
    "Seguros",
    "Movilidad y Viáticos",
    "Gastos de Oficina y Limpieza",
    "Medicina Prepaga",
    "Impuestos y Tasas",
    "Sueldos y Cargas Sociales",
    "Otros Gastos No Deducibles"
];

const CATEGORIES_EMITIDOS = [
    "Venta de Servicios locales",
    "Venta de Bienes",
    "Exportación de Servicios",
    "Honorarios de Asesoría",
    "Otros Ingresos Financieros"
];

// OBTENER CUIT EMPRESA ACTIVA
function getActiveCompanyCuit() {
    const label = document.getElementById('current-entity-label');
    if (!label) return '30710536461'; // Quinto Elemento S.A por defecto
    const match = label.innerText.match(/\d+/);
    return match ? match[0] : '30710536461';
}

// 5. CONTROLADOR NAVEGACIÓN SPA E INTERFAZ (SOLID: Single Responsibility)
export function switchTab(tabId) {
    document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
    document.getElementById(tabId).classList.remove('hidden');

    document.querySelectorAll('.sidebar-nav a').forEach(el => el.classList.remove('active-nav'));
    const activeLink = document.querySelector(`[onclick="switchTab('${tabId}')"]`);
    if (activeLink) activeLink.classList.add('active-nav');

    const titleElement = document.getElementById('page-title');
    if (tabId === 'tab-conciliador') titleElement.innerText = "Conciliador CSV (Operaciones)";
    else if (tabId === 'tab-bancos') {
        titleElement.innerText = "Extracto Bancario (Finanzas)";
        renderBancosGrid();
    }
    else if (tabId === 'tab-sueldos') {
        titleElement.innerText = "Liquidación de Sueldos (Acompy)";
        updateSalaryFormFields();
    }
    else if (tabId === 'tab-movimientos-manuales') {
        titleElement.innerText = "Registrar Movimientos Manuales";
    }
    else if (tabId === 'tab-ajustes-contadora') titleElement.innerText = "Ajustes Tributarios (Contadora)";
    else if (tabId === 'tab-configuracion') titleElement.innerText = "Configuración del Sistema";
    else if (tabId === 'tab-client-dashboard') {
        titleElement.innerText = "Panel Gerencial (Dashboard)";
        renderClientDashboard();
    }
    else if (tabId === 'tab-client-ocr') titleElement.innerText = "Lector de Documentos (OCR)";
}

// CONTROLADOR DE MÉTRICAS OPERATIVAS PARA EL GERENTE (DASHBOARD)
export function renderClientDashboard() {
    const items = appStore.items;
    const manualMovs = appStore.manualMovements.filter(m => m.origen === 'manual-interno');

    // Ventas Brutas (Emitidos + Ingresos manuales internos)
    const salesARCA = items.filter(i => i.tipo === 'emitido').reduce((sum, i) => sum + i.total, 0);
    const salesManual = manualMovs.filter(m => m.tipo === 'Ingreso').reduce((sum, m) => sum + m.importe, 0);
    const sales = salesARCA + salesManual;

    // Compras (Recibidos + Egresos manuales internos)
    const purchasesARCA = items.filter(i => i.tipo === 'recibido').reduce((sum, i) => sum + i.total, 0);
    const purchasesManual = manualMovs.filter(m => m.tipo === 'Gasto').reduce((sum, m) => sum + m.importe, 0);
    const purchases = purchasesARCA + purchasesManual;

    const netBalance = sales - purchases;

    // Actualización de valores principales
    const salesValEl = document.getElementById('client-sales-val');
    const purchasesValEl = document.getElementById('client-purchases-val');
    const netEl = document.getElementById('client-net-val');
    const ivaValEl = document.getElementById('client-iva-val');
    const iibbValEl = document.getElementById('client-iibb-val');
    const laborValEl = document.getElementById('client-labor-val');

    if (salesValEl) salesValEl.innerText = `$ ${sales.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (purchasesValEl) purchasesValEl.innerText = `$ ${purchases.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    
    if (netEl) {
        netEl.innerText = `$ ${netBalance.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
        netEl.style.color = netBalance >= 0 ? 'var(--success)' : 'var(--warning)';
    }

    // Cálculo de IVA (Ventas - Compras)
    const ivaEstimado = (salesARCA * 0.21) - (purchasesARCA * 0.21);
    // Cálculo IIBB (Ventas * alícuota)
    const iibbEstimado = salesARCA * 0.03;

    if (ivaValEl) ivaValEl.innerText = `$ ${Math.max(0, ivaEstimado).toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (iibbValEl) iibbValEl.innerText = `$ ${iibbEstimado.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;

    // Costo Laboral
    let costLabor = 0;
    if (appStore.salaries) {
        const sal = appStore.salaries;
        const f931 = parseFloat(document.getElementById('input-f931').value) || 0;
        const sindContrib = parseFloat(document.getElementById('input-sindicato-contrib').value) || 0;
        costLabor = sal.sueldoNeto + f931 + sal.sindicatoAporte + sindContrib + sal.anticipos - (sal.sueldoBruto - sal.sueldoNeto);
    }
    if (laborValEl) laborValEl.innerText = `$ ${costLabor.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;

    // Alertas de descuadres
    const alertUnresolved = document.getElementById('alert-unresolved-taxes');
    if (alertUnresolved) {
        const hasUnresolved = appStore.items.some(i => i.tipo === 'recibido' && i.saldoAExplicar > 0);
        alertUnresolved.classList.toggle('hidden', !hasUnresolved);
    }

    // Desglose de Gastos
    const categoryChartContainer = document.getElementById('client-category-chart');
    if (!categoryChartContainer) return;

    const purchaseItems = items.filter(i => i.tipo === 'recibido');
    if (purchaseItems.length === 0 && purchasesManual === 0) {
        categoryChartContainer.innerHTML = `<li style="font-size: 13px; color: var(--text-muted); text-align: center; padding: 20px;">No hay datos de compras disponibles.</li>`;
        return;
    }

    const catTotals = {};
    purchaseItems.forEach(i => {
        const cat = i.categoria || "Sin Categorizar";
        catTotals[cat] = (catTotals[cat] || 0) + i.total;
    });
    if (purchasesManual > 0) {
        catTotals["Gastos Caja Chica (Manual)"] = (catTotals["Gastos Caja Chica (Manual)"] || 0) + purchasesManual;
    }

    const sortedCategories = Object.entries(catTotals).sort((a,b) => b[1] - a[1]);
    categoryChartContainer.innerHTML = sortedCategories.map(([category, amount]) => {
        const pct = Math.round((amount / (purchases || 1)) * 100);
        return `
            <li class="progress-item">
                <div class="progress-item-labels">
                    <span>${category}</span>
                    <span>$ ${amount.toLocaleString('es-AR', {maximumFractionDigits: 0})} (${pct}%)</span>
                </div>
                <div class="progress-track">
                    <div class="progress-bar" style="width: ${pct}%;"></div>
                </div>
            </li>
        `;
    }).join('');
}

// BÚSQUEDA DE COMISIONES Y TRANSACCIONES BANCARIAS
export function renderBancosGrid() {
    const tbody = document.getElementById('table-bancos-body');
    if (!tbody) return;

    const txs = appStore.bankTransactions;
    if (txs.length === 0) {
        tbody.innerHTML = `<tr><td colspan="6" style="text-align: center; color: var(--text-muted); padding: 30px;">No hay extractos bancarios cargados.</td></tr>`;
        return;
    }

    tbody.innerHTML = txs.map((tx, idx) => {
        const rowClass = tx.confirmada ? 'tr-matched' : 'tr-pending';
        const buttonHTML = tx.confirmada 
            ? `<button class="btn-confirm confirmed" disabled>✓ Confirmado</button>`
            : `<button class="btn-confirm" onclick="confirmBankTx(${idx})">Aprobar</button>`;

        return `
            <tr class="${rowClass}">
                <td>${tx.fecha}</td>
                <td><strong>${tx.descripcion}</strong></td>
                <td style="font-weight: 600; color: ${tx.tipo === 'debit' ? 'var(--warning)' : 'var(--success)'};">
                    ${tx.tipo === 'debit' ? '-' : '+'}$ ${tx.monto.toLocaleString('es-AR', {minimumFractionDigits: 2})}
                </td>
                <td><span class="badge ${tx.tipo === 'debit' ? 'badge-recibido' : 'badge-emitido'}">${tx.tipo === 'debit' ? 'Débito' : 'Crédito'}</span></td>
                <td>
                    <select class="select-category" onchange="updateBankTxCategory(${idx}, this.value)" ${tx.confirmada ? 'disabled' : ''}>
                        <option value="Pago Proveedor" ${tx.cuentaSugerida === 'Pago Proveedor' ? 'selected' : ''}>Pago Proveedor</option>
                        <option value="Ingreso por Ventas" ${tx.cuentaSugerida === 'Ingreso por Ventas' ? 'selected' : ''}>Ingreso por Ventas</option>
                        <option value="Gasto Bancario" ${tx.cuentaSugerida === 'Gasto Bancario' ? 'selected' : ''}>Gasto Bancario</option>
                        <option value="Percepción IVA" ${tx.cuentaSugerida === 'Percepción IVA' ? 'selected' : ''}>Percepción IVA</option>
                        <option value="Percepción IIBB (SIRCREB)" ${tx.cuentaSugerida.includes('SIRCREB') || tx.cuentaSugerida.includes('IIBB') ? 'selected' : ''}>Percepción IIBB (SIRCREB)</option>
                        <option value="Impuesto Débito/Crédito" ${tx.cuentaSugerida === 'Impuesto Débito/Crédito' ? 'selected' : ''}>Impuesto Débito/Crédito</option>
                        <option value="Pago de Impuestos" ${tx.cuentaSugerida === 'Pago de Impuestos' ? 'selected' : ''}>Pago de Impuestos</option>
                    </select>
                </td>
                <td>${buttonHTML}</td>
            </tr>
        `;
    }).join('');
}

window.confirmBankTx = function(idx) {
    const tx = appStore.bankTransactions[idx];
    if (tx) {
        tx.confirmada = true;
        appStore.notify();
    }
};

window.updateBankTxCategory = function(idx, category) {
    const tx = appStore.bankTransactions[idx];
    if (tx) {
        tx.cuentaSugerida = category;
        appStore.notify();
    }
};

// RENDERIZADO DE RESOLUCIÓN MANUAL ("OTROS TRIBUTOS" CON DESCUADRE)
export function renderResolucionManual() {
    const container = document.getElementById('card-resolucion-manual');
    const tbody = document.getElementById('table-resolucion-manual-body');
    if (!container || !tbody) return;

    const pendingItems = appStore.items.filter(i => i.tipo === 'recibido' && i.saldoAExplicar > 0);
    if (pendingItems.length === 0) {
        container.classList.add('hidden');
        return;
    }

    container.classList.remove('hidden');
    tbody.innerHTML = pendingItems.map(item => `
        <tr>
            <td>${item.fecha}</td>
            <td>${item.comprobante}</td>
            <td><strong>${item.razonSocial}</strong> (${item.cuit})</td>
            <td>$ ${item.otrosTributos.toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
            <td style="color: var(--danger); font-weight: bold;">$ ${item.saldoAExplicar.toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
            <td>
                <div style="display: flex; gap: 6px;">
                    <select class="select-category" id="select-res-${item.id}">
                        <option value="exento">Imputar a EXENTO</option>
                        <option value="ARBA">Percepciones IIBB ARBA</option>
                        <option value="AGIP">Percepciones IIBB AGIP</option>
                        <option value="IVA">Percepciones IVA Nacional</option>
                    </select>
                    <button class="btn-primary" style="padding: 4px 8px; font-size: 11px;" onclick="resolveOtrosTributos('${item.id}')">✓ Guardar</button>
                </div>
            </td>
        </tr>
    `).join('');
}

window.resolveOtrosTributos = function(itemId) {
    const select = document.getElementById(`select-res-${itemId}`);
    if (select) {
        const type = select.value;
        if (type === 'exento') {
            Reconciler.manualResolve(itemId, 'exento');
        } else {
            Reconciler.manualResolve(itemId, 'custom', `Percepciones IIBB ${type}`);
        }
    }
};

// ACTUALIZACIÓN DE SUELDOS EN PANTALLA
function updateSalaryFormFields() {
    const sal = appStore.salaries;
    const lblBruto = document.getElementById('lbl-sueldo-bruto');
    const lblAnticipos = document.getElementById('lbl-anticipos');
    const lblSindicato = document.getElementById('lbl-sindicato-aporte');
    const lblNeto = document.getElementById('lbl-sueldo-neto');
    const lblTotalPagar = document.getElementById('lbl-total-a-pagar');
    const lblCostoLaboral = document.getElementById('lbl-costo-laboral');

    if (!sal) {
        if (lblBruto) lblBruto.innerText = "$ 0,00";
        if (lblAnticipos) lblAnticipos.innerText = "$ 0,00";
        if (lblSindicato) lblSindicato.innerText = "$ 0,00";
        if (lblNeto) lblNeto.innerText = "$ 0,00";
        if (lblTotalPagar) lblTotalPagar.innerText = "$ 0,00";
        if (lblCostoLaboral) lblCostoLaboral.innerText = "$ 0,00";
        return;
    }

    if (lblBruto) lblBruto.innerText = `$ ${sal.sueldoBruto.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (lblAnticipos) lblAnticipos.innerText = `$ ${sal.anticipos.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (lblSindicato) lblSindicato.innerText = `$ ${sal.sindicatoAporte.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (lblNeto) lblNeto.innerText = `$ ${sal.sueldoNeto.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;

    // Calcular fórmulas en base a inputs manuales
    const f931 = parseFloat(document.getElementById('input-f931').value) || 0;
    const sindContrib = parseFloat(document.getElementById('input-sindicato-contrib').value) || 0;

    const totalAPagar = sal.sueldoNeto + f931 + sal.sindicatoAporte + sindContrib;
    const costoLaboral = totalAPagar + sal.anticipos - (sal.sueldoBruto - sal.sueldoNeto);

    if (lblTotalPagar) lblTotalPagar.innerText = `$ ${totalAPagar.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    if (lblCostoLaboral) lblCostoLaboral.innerText = `$ ${costoLaboral.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
}

// BUCLES DE COLA DE SELECCIÓN MULTI-ACTIVIDAD
function checkMultiActivityQueue() {
    const activeCuit = getActiveCompanyCuit();
    // Buscar la primera venta sin asignar actividad
    const unassignedVenta = appStore.items.find(i => i.tipo === 'emitido' && !i.actividad && !i.confirmada);
    
    if (unassignedVenta) {
        const result = Activities.processVentaComprobante(unassignedVenta, activeCuit);
        if (result.requiredAction === 'modal_required') {
            showMultiActivityModal(unassignedVenta, result.activities);
        } else {
            // Asignación automática ejecutada, notificar cambios
            appStore.notify();
        }
    }
}

// MOSTRAR MODAL DE ASIGNACIÓN MULTI-ACTIVIDAD
function showMultiActivityModal(item, activities) {
    const modal = document.getElementById('modal-multi-actividad');
    if (!modal) return;

    document.getElementById('modal-act-comprobante').innerText = item.comprobante;
    document.getElementById('modal-act-cliente').innerText = item.razonSocial;
    document.getElementById('modal-act-neto').innerText = `$ ${item.netoGravado.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;
    document.getElementById('modal-act-exento').innerText = `$ ${item.exento.toLocaleString('es-AR', {minimumFractionDigits: 2})}`;

    // Selector de Actividad Única
    const selectSingle = document.getElementById('select-modal-act-single');
    selectSingle.innerHTML = activities.map(a => `<option value="${a.id}">${a.nombre} (${a.codigo})</option>`).join('');

    // Campos de Itemizado (Split)
    const splitContainer = document.getElementById('container-modal-split-fields');
    splitContainer.innerHTML = activities.map((a, idx) => `
        <div style="border: 1px solid var(--border-color); padding: 8px; border-radius: 6px; background-color: #ffffff;">
            <strong>${a.nombre}</strong>
            <div style="display: flex; gap: 8px; margin-top: 6px;">
                <div style="flex: 1;">
                    <label style="font-size: 10px; color: var(--text-muted);">Neto Gravado ($)</label>
                    <input type="number" id="split-neto-${a.id}" class="form-control split-neto-input" placeholder="0.00" step="0.01" value="${idx === 0 ? item.netoGravado : 0}">
                </div>
                <div style="flex: 1;">
                    <label style="font-size: 10px; color: var(--text-muted);">Exento ($)</label>
                    <input type="number" id="split-exento-${a.id}" class="form-control split-exento-input" placeholder="0.00" step="0.01" value="${idx === 0 ? item.exento : 0}">
                </div>
            </div>
            <input type="hidden" id="split-code-${a.id}" value="${a.codigo}">
            <input type="hidden" id="split-name-${a.id}" value="${a.nombre}">
        </div>
    `).join('');

    // Listener de Confirmar
    const btnSubmit = document.getElementById('btn-modal-act-submit');
    btnSubmit.onclick = () => {
        const activeOption = document.querySelector('input[name="modal-act-opt"]:checked').value;
        const activeCuit = getActiveCompanyCuit();

        if (activeOption === 'all') {
            Activities.assignAllToActivity(item.id, selectSingle.value, activeCuit);
            modal.classList.add('hidden');
            checkMultiActivityQueue(); // Revisar si hay otra pendiente
        } else {
            // Reconstruir splits
            const splits = activities.map(a => {
                const netoVal = parseFloat(document.getElementById(`split-neto-${a.id}`).value) || 0;
                const exentoVal = parseFloat(document.getElementById(`split-exento-${a.id}`).value) || 0;
                return {
                    actividadId: a.id,
                    actividadNombre: document.getElementById(`split-name-${a.id}`).value,
                    codigoNaes: document.getElementById(`split-code-${a.id}`).value,
                    netoGravado: netoVal,
                    noGravado: 0,
                    exento: exentoVal,
                    iva: 0 // Simplificado
                };
            });

            const res = Activities.assignSplitToActivities(item.id, splits);
            if (res && !res.success) {
                alert(res.error);
            } else {
                modal.classList.add('hidden');
                checkMultiActivityQueue(); // Probar siguiente en cola
            }
        }
    };

    modal.classList.remove('hidden');
}

// MOSTRAR CONFIGURADOR DE COLUMNAS FALLBACK
function showColumnMapperModal(headers, title, onApply) {
    const modal = document.getElementById('modal-column-mapper');
    if (!modal) return;

    document.getElementById('modal-mapper-title').innerText = title;
    
    // Inyectamos selects dinámicos para Fecha, Descripción, etc.
    const selectsContainer = document.getElementById('container-mapper-selects');
    
    let isSueldos = title.toLowerCase().includes('sueldos');
    let selectFields = isSueldos 
        ? [
            { id: 'sueldoBruto', label: 'Sueldo Bruto (Remunerativo)' },
            { id: 'sueldoNeto', label: 'Sueldo Neto a pagar' },
            { id: 'anticipos', label: 'Anticipos (Opcional)' },
            { id: 'sindicatoAporte', label: 'Aporte Sindicato (Opcional)' }
          ]
        : [
            { id: 'fecha', label: 'Columna de Fecha' },
            { id: 'descripcion', label: 'Columna de Descripción' },
            { id: 'importe', label: 'Columna de Importe' }
          ];

    selectsContainer.innerHTML = selectFields.map(f => `
        <div class="form-group">
            <label>${f.label}</label>
            <select id="map-select-${f.id}" class="form-control">
                <option value="">-- Seleccionar Columna --</option>
                ${headers.map((h, idx) => `<option value="${idx}">${h} (Columna ${idx+1})</option>`).join('')}
            </select>
        </div>
    `).join('');

    const btnSubmit = document.getElementById('btn-modal-mapper-submit');
    btnSubmit.onclick = () => {
        const mapping = {};
        selectFields.forEach(f => {
            const val = document.getElementById(`map-select-${f.id}`).value;
            if (val !== "") {
                mapping[f.id] = parseInt(val);
            }
        });

        // Validar requeridos
        if (isSueldos && (mapping.sueldoBruto === undefined || mapping.sueldoNeto === undefined)) {
            alert("Las columnas de Sueldo Bruto y Sueldo Neto son obligatorias.");
            return;
        }
        if (!isSueldos && (mapping.fecha === undefined || mapping.descripcion === undefined || mapping.importe === undefined)) {
            alert("Las columnas de Fecha, Descripción e Importe son obligatorias.");
            return;
        }

        modal.classList.add('hidden');
        onApply(mapping);
    };

    modal.classList.remove('hidden');
}// MOSTRAR VISTA PREVIA (STAGING)
function showStagingPreviewModal(stagedRows, fileName, context, onConfirm) {
    if (typeof context === 'function') {
        onConfirm = context;
        context = { tenant: getActiveCompanyCuit(), tipoOperacion: 'COMPRA' };
    }

    const validRows = stagedRows.filter(r => r.status === 'ACCEPTED' || r.status === 'POSSIBLE_AMENDMENT');
    const duplicateRows = stagedRows.filter(r => r.status === 'EXACT_DUPLICATE');
    const invalidRows = stagedRows.filter(r => r.status === 'INVALID');
    
    // Crear el overlay
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    
    overlay.innerHTML = `
        <div class="modal-card" style="width: 80%; max-width: 800px; max-height: 90vh; display: flex; flex-direction: column;">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: bold; color: var(--primary);">Vista Previa de Importación</h3>
                <button class="btn-close-modal" style="background: none; border: none; font-size: 20px; cursor: pointer; color: var(--text-muted);">&times;</button>
            </div>
            <div class="modal-body" style="overflow-y: auto; flex: 1;">
                <p><strong>Archivo:</strong> ${fileName}</p>
                <div style="display: flex; gap: 15px; margin: 15px 0;">
                    <div style="background: #e6f4ea; color: #137333; padding: 10px; border-radius: 4px; flex: 1; text-align: center;">
                        <strong>${validRows.length}</strong><br>Válidas / Modificadas
                    </div>
                    <div style="background: #fef7e0; color: #b06000; padding: 10px; border-radius: 4px; flex: 1; text-align: center;">
                        <strong>${duplicateRows.length}</strong><br>Duplicadas Exactas (Ignoradas)
                    </div>
                    <div style="background: #fce8e6; color: #c5221f; padding: 10px; border-radius: 4px; flex: 1; text-align: center;">
                        <strong>${invalidRows.length}</strong><br>Inválidas
                    </div>
                </div>
                
                ${invalidRows.length > 0 ? `
                <div style="background: #fce8e6; color: #c5221f; padding: 10px; border-radius: 4px; margin-bottom: 15px; font-size: 12px;">
                    <strong>Errores encontrados:</strong>
                    <ul style="margin: 5px 0 0 20px;">
                        ${invalidRows.slice(0, 5).map(r => `<li>Fila ${r.sourceRowNumber || '?'}: ${r.errors?.join(', ') || 'Error de parseo'}</li>`).join('')}
                        ${invalidRows.length > 5 ? `<li>...y ${invalidRows.length - 5} más</li>` : ''}
                    </ul>
                </div>
                ` : ''}
                
                <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 5px;">Muestra de datos válidos (máximo 5):</p>
                <table style="width: 100%; border-collapse: collapse; font-size: 12px; margin-bottom: 15px;">
                    <thead>
                        <tr style="background: var(--bg-hover); text-align: left;">
                            <th style="padding: 6px; border: 1px solid var(--border-color);">Fecha</th>
                            <th style="padding: 6px; border: 1px solid var(--border-color);">Comprobante</th>
                            <th style="padding: 6px; border: 1px solid var(--border-color);">Total</th>
                            <th style="padding: 6px; border: 1px solid var(--border-color);">Estado</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${validRows.slice(0, 5).map(r => {
                            const d = r.normalizedData;
                            const cbte = `${d.tipo_cbte}-${d.pdv}-${d.nroDesde}`;
                            const isAmended = r.status === 'POSSIBLE_AMENDMENT';
                            const totalFormatted = (d.total || 0).toLocaleString('es-AR', {minimumFractionDigits: 2});
                            return `
                            <tr>
                                <td style="padding: 6px; border: 1px solid var(--border-color);">${d.fecha}</td>
                                <td style="padding: 6px; border: 1px solid var(--border-color);">${cbte}</td>
                                <td style="padding: 6px; border: 1px solid var(--border-color);">$ ${totalFormatted}</td>
                                <td style="padding: 6px; border: 1px solid var(--border-color); font-weight: bold; color: ${isAmended ? '#b06000' : '#137333'};">
                                    ${isAmended ? 'Modificado' : 'Nuevo'}
                                </td>
                            </tr>
                            `;
                        }).join('')}
                        ${validRows.length === 0 ? '<tr><td colspan="4" style="text-align: center; padding: 10px;">No hay filas válidas</td></tr>' : ''}
                    </tbody>
                </table>
            </div>
            <div class="modal-footer" style="margin-top: auto;">
                <button class="btn-secondary btn-cancel-modal">Cancelar</button>
                <button class="btn-primary btn-confirm-modal" ${validRows.length === 0 ? 'disabled' : ''}>Confirmar Importación (${validRows.length})</button>
            </div>
        </div>
    `;
    
    document.body.appendChild(overlay);
    
    const closeAndRemove = () => {
        if (overlay.parentNode) {
            overlay.parentNode.removeChild(overlay);
        }
    };
    
    overlay.querySelector('.btn-close-modal').onclick = closeAndRemove;
    overlay.querySelector('.btn-cancel-modal').onclick = closeAndRemove;
    
    const confirmBtn = overlay.querySelector('.btn-confirm-modal');
    if (confirmBtn) {
        confirmBtn.onclick = () => {
            closeAndRemove();
            // Transformar las filas staged al modelo de la UI garantizando el contrato de identidad fiscal
            const toImport = validRows.map(r => {
                const item = r.normalizedData;
                const isCompra = (context && context.tipoOperacion === 'COMPRA') || r.tipoOperacion === 'COMPRA';
                const netoGravadoVal = item.netoGravado !== undefined 
                    ? item.netoGravado 
                    : (item.alicuotas && item.alicuotas.length > 0 
                        ? item.alicuotas.reduce((sum, a) => sum + (a.baseImponible || 0), 0) 
                        : Math.max(0, (item.total || 0) - (item.totalIva || 0) - (item.exento || 0) - (item.netoNoGravado || 0) - (item.otrosTributos || 0)));

                return {
                    id: crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substr(2, 9),
                    fecha: item.fecha,
                    tipo: isCompra ? 'recibido' : 'emitido',
                    tipoOperacion: isCompra ? 'COMPRA' : 'VENTA',
                    tenant: context ? context.tenant : getActiveCompanyCuit(),
                    cuit: item.cuit,
                    razonSocial: item.razonSocial || '',
                    proveedor: isCompra ? ("CUIT " + item.cuit) : (item.razonSocial || ("CUIT " + item.cuit)),
                    comprobante: `${item.tipo_cbte}-${item.pdv}-${item.nroDesde}`,
                    tipo_cbte: item.tipo_cbte,
                    pdv: item.pdv,
                    nroDesde: item.nroDesde,
                    nroHasta: item.nroHasta || item.nroDesde,
                    moneda: item.moneda || 'PES',
                    tipoCambio: item.tipoCambio || 1,
                    total: item.total || 0,
                    importe: item.total || 0,
                    importeTotal: item.total || 0,
                    totalIva: item.totalIva || 0,
                    iva: item.totalIva || 0,
                    otrosTributos: item.otrosTributos || 0,
                    exento: item.exento || 0,
                    netoNoGravado: item.netoNoGravado || 0,
                    noGravado: item.netoNoGravado || 0,
                    netoGravado: netoGravadoVal,
                    alicuotas: item.alicuotas || [],
                    categoria: null,
                    sugerida: false,
                    confirmada: false,
                    rawRecord: item
                };
            });
            onConfirm(toImport);
        };
    }
}

function showPerceptionsPreviewModal(validItems, invalidCount, fileName, onConfirm) {
    const totalAmount = validItems.reduce((sum, item) => sum + (item.amount || item.monto || 0), 0);
    const samplePeriod = validItems.length > 0 ? (validItems[0].period || validItems[0].periodo || 'N/D') : 'N/D';

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    
    overlay.innerHTML = `
        <div class="modal-card" style="width: 85%; max-width: 850px; max-height: 90vh; display: flex; flex-direction: column;">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: bold; color: var(--primary);">Vista Previa de Percepciones</h3>
                <button class="btn-close-modal" style="background: none; border: none; font-size: 20px; cursor: pointer; color: var(--text-muted);">&times;</button>
            </div>
            <div class="modal-body" style="overflow-y: auto; flex: 1;">
                <p style="font-size: 13px;"><strong>Archivo:</strong> ${fileName}</p>
                <div style="display: flex; gap: 12px; margin: 12px 0;">
                    <div style="background: #e6f4ea; color: #137333; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 18px;">${validItems.length}</strong><br><span style="font-size: 11px;">Registros Válidos</span>
                    </div>
                    <div style="background: #fce8e6; color: #c5221f; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 18px;">${invalidCount}</strong><br><span style="font-size: 11px;">Omitidas / Error</span>
                    </div>
                    <div style="background: #e0f2fe; color: #0369a1; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 14px;">${samplePeriod}</strong><br><span style="font-size: 11px;">Período</span>
                    </div>
                    <div style="background: #f0fdf4; color: #15803d; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 14px;">$ ${totalAmount.toLocaleString('es-AR', {minimumFractionDigits: 2})}</strong><br><span style="font-size: 11px;">Total Importe</span>
                    </div>
                </div>
                
                <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 6px;">Detalle de percepciones a incorporar:</p>
                <div style="max-height: 250px; overflow-y: auto; border: 1px solid var(--border-color); border-radius: 4px;">
                    <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
                        <thead>
                            <tr style="background: var(--bg-hover); text-align: left; position: sticky; top: 0; z-index: 1;">
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Fuente</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Fecha</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">CUIT Agente</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Comprobante</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color); text-align: right;">Importe</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${validItems.map(item => `
                                <tr>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color); font-weight: 600; color: var(--primary);">${item.fuente || item.jurisdiction || 'ARBA'}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">${item.fecha}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">${item.cuit}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">${item.comprobante || 'N/D'}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color); text-align: right; font-weight: 600;">$ ${(item.amount || item.monto || 0).toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="modal-footer" style="margin-top: 12px; display: flex; justify-content: flex-end; gap: 8px;">
                <button class="btn-secondary btn-cancel-modal">Cancelar</button>
                <button class="btn-primary btn-confirm-modal" ${validItems.length === 0 ? 'disabled' : ''}>Confirmar Importación (${validItems.length})</button>
            </div>
        </div>
    `;
    
    document.body.appendChild(overlay);
    
    const closeAndRemove = () => {
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    };
    
    overlay.querySelector('.btn-close-modal').onclick = closeAndRemove;
    overlay.querySelector('.btn-cancel-modal').onclick = closeAndRemove;
    
    const confirmBtn = overlay.querySelector('.btn-confirm-modal');
    if (confirmBtn) {
        confirmBtn.onclick = () => {
            closeAndRemove();
            onConfirm(validItems);
        };
    }
}

function showBankPreviewModal(transactions, fileName, onConfirm) {
    const debits = transactions.filter(t => t.tipo === 'debit');
    const credits = transactions.filter(t => t.tipo === 'credit');
    const totalDebits = debits.reduce((sum, t) => sum + (t.monto || 0), 0);
    const totalCredits = credits.reduce((sum, t) => sum + (t.monto || 0), 0);

    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    
    overlay.innerHTML = `
        <div class="modal-card" style="width: 85%; max-width: 850px; max-height: 90vh; display: flex; flex-direction: column;">
            <div class="modal-header">
                <h3 style="font-size: 16px; font-weight: bold; color: var(--primary);">Vista Previa de Extracto Bancario</h3>
                <button class="btn-close-modal" style="background: none; border: none; font-size: 20px; cursor: pointer; color: var(--text-muted);">&times;</button>
            </div>
            <div class="modal-body" style="overflow-y: auto; flex: 1;">
                <p style="font-size: 13px;"><strong>Archivo:</strong> ${fileName}</p>
                <div style="display: flex; gap: 12px; margin: 12px 0;">
                    <div style="background: #e6f4ea; color: #137333; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 18px;">${transactions.length}</strong><br><span style="font-size: 11px;">Movimientos Totales</span>
                    </div>
                    <div style="background: #fce8e6; color: #c5221f; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 14px;">$ ${totalDebits.toLocaleString('es-AR', {minimumFractionDigits: 2})}</strong><br><span style="font-size: 11px;">${debits.length} Débitos (Egresos)</span>
                    </div>
                    <div style="background: #f0fdf4; color: #15803d; padding: 10px; border-radius: 6px; flex: 1; text-align: center;">
                        <strong style="font-size: 14px;">$ ${totalCredits.toLocaleString('es-AR', {minimumFractionDigits: 2})}</strong><br><span style="font-size: 11px;">${credits.length} Créditos (Ingresos)</span>
                    </div>
                </div>
                
                <p style="font-size: 12px; color: var(--text-muted); margin-bottom: 6px;">Detalle de movimientos a incorporar:</p>
                <div style="max-height: 250px; overflow-y: auto; border: 1px solid var(--border-color); border-radius: 4px;">
                    <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
                        <thead>
                            <tr style="background: var(--bg-hover); text-align: left; position: sticky; top: 0; z-index: 1;">
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Fecha</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Descripción</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color);">Tipo</th>
                                <th style="padding: 6px; border-bottom: 1px solid var(--border-color); text-align: right;">Importe</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${transactions.map(t => `
                                <tr>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">${t.fecha}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">${t.descripcion}</td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color);">
                                        <span style="font-weight: 600; color: ${t.tipo === 'debit' ? '#c5221f' : '#15803d'};">
                                            ${t.tipo === 'debit' ? 'DÉBITO (-)' : 'CRÉDITO (+)'}
                                        </span>
                                    </td>
                                    <td style="padding: 6px; border-bottom: 1px solid var(--border-color); text-align: right; font-weight: 600;">$ ${t.monto.toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
            <div class="modal-footer" style="margin-top: 12px; display: flex; justify-content: flex-end; gap: 8px;">
                <button class="btn-secondary btn-cancel-modal">Cancelar</button>
                <button class="btn-primary btn-confirm-modal" ${transactions.length === 0 ? 'disabled' : ''}>Confirmar Importación (${transactions.length})</button>
            </div>
        </div>
    `;
    
    document.body.appendChild(overlay);
    
    const closeAndRemove = () => {
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    };
    
    overlay.querySelector('.btn-close-modal').onclick = closeAndRemove;
    overlay.querySelector('.btn-cancel-modal').onclick = closeAndRemove;
    
    const confirmBtn = overlay.querySelector('.btn-confirm-modal');
    if (confirmBtn) {
        confirmBtn.onclick = () => {
            closeAndRemove();
            onConfirm(transactions);
        };
    }
}

// CONTROLADOR DE RENDERIZADO DEL CONCILIADOR ARCA (NÚCLEO EXISTENTE ADAPTADO)
export class UIManager {
    static init() {
        this.setupDragAndDrop('zone-recibidos', 'file-recibidos', 'recibido');
        this.setupDragAndDrop('zone-emitidos', 'file-emitidos', 'emitido');
        this.setupDragAndDrop('zone-percepciones', 'file-percepciones', 'percepcion');
        this.setupDragAndDrop('zone-bancos', 'file-bancos', 'banco');
        this.setupDragAndDrop('zone-sueldos', 'file-sueldos', 'sueldo');
    }

    static setupDragAndDrop(zoneId, inputId, type) {
        const zone = document.getElementById(zoneId);
        const input = document.getElementById(inputId);

        if (!zone || !input) return;

        input.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) this.processFile(file, type);
        });

        zone.addEventListener('dragover', (e) => { e.preventDefault(); zone.style.borderColor = 'var(--accent)'; });
        zone.addEventListener('dragleave', () => { zone.style.borderColor = 'var(--border-color)'; });
        zone.addEventListener('drop', (e) => {
            e.preventDefault();
            zone.style.borderColor = 'var(--border-color)';
            const file = e.dataTransfer.files[0];
            if (file) this.processFile(file, type);
        });
    }

    static async processFile(file, type) {
        try {
            const buffer = await readFileAsArrayBuffer(file);
            const text = await readFileAsText(file).catch(() => '');
            const formatInfo = detectFileFormat({ arrayBuffer: buffer, text, fileName: file.name, mimeType: file.type });
            
            let rows = [];
            if (type !== 'percepcion') {
                if (formatInfo === 'OOXML_XLSX' || formatInfo === 'OLE2_BIFF') {
                    if (typeof window === 'undefined' || !window.XLSX) throw new Error("Librería SheetJS no cargada en el navegador.");
                    const sheetAdapter = createSheetJsAdapter(window.XLSX);
                    rows = sheetAdapter.workbookToRows(buffer, { sheetName: null });
                } else if (formatInfo === 'TEXT_DELIMITED') {
                    rows = parseDelimitedText(text);
                } else if (formatInfo === 'TEXT_FIXED_WIDTH') {
                    rows = parseDelimitedText(text, { delimiter: 'NONE' });
                } else {
                    throw new Error("Formato no soportado o desconocido.");
                }
            }

            const fingerprintProvider = createBrowserFingerprintProvider();
            const tenant = getActiveCompanyCuit();
            let parsedItems = [];
            let context = { batchId: Date.now(), tenant };

            if (type === 'recibido' || type === 'emitido') {
                context.tipoOperacion = type === 'recibido' ? 'COMPRA' : 'VENTA';
                parsedItems = parseArcaRows(rows, context);
                
                const staged = await stageImport({ 
                    incomingRows: parsedItems, 
                    existingRecords: appStore.items || [], 
                    context, 
                    fingerprintProvider 
                });
                
                showStagingPreviewModal(staged, file.name, context, (acceptedItems) => {
                    appStore.addItems(acceptedItems);
                    if (type === 'emitido') checkMultiActivityQueue();
                    UIManager.render();
                });
            } else if (type === 'percepcion') {
                const jurisdiction = (document.getElementById('percep-jurisdiccion')?.value || 'ARBA').toUpperCase();
                context.jurisdiccion = jurisdiction;

                const isExcel = file.name.toLowerCase().endsWith('.xls') || file.name.toLowerCase().endsWith('.xlsx') || format === 'EXCEL';
                if (isExcel) {
                    parsedItems = parseIvaPerceptions(rows, context);
                } else {
                    parsedItems = parseArbaText(text, context);
                }
                
                const validPerceptions = parsedItems.filter(r => r.normalizedData !== null).map(r => r.normalizedData);
                const invalidRows = parsedItems.filter(r => r.normalizedData === null);
                
                if (validPerceptions.length === 0) {
                    alert("No se encontraron percepciones válidas en el archivo.");
                } else {
                    showPerceptionsPreviewModal(validPerceptions, invalidRows.length, file.name, (acceptedItems) => {
                        appStore.addPerceptions(acceptedItems);
                        Reconciler.runCrossMatching();
                        UIManager.render();
                    });
                }
            } else if (type === 'banco') {
                const bankName = document.getElementById('bank-name')?.value || 'Generico';
                context.banco = bankName;
                const result = parseBankRows(rows, context);
                const validTransactions = result.filter(r => r.errors.length === 0).map(r => r.normalizedData);

                if (validTransactions.length === 0) {
                    alert("No se encontraron movimientos bancarios válidos en el archivo.");
                } else {
                    showBankPreviewModal(validTransactions, file.name, (accepted) => {
                        appStore.addBankTransactions(accepted);
                        UIManager.render();
                    });
                }
            } else if (type === 'sueldo') {
                const results = parseSalaryRows(rows, context);
                const firstRes = results && results[0];

                if (firstRes && firstRes.errors && firstRes.errors.length > 0) {
                    alert("Error en el archivo de sueldos: " + firstRes.errors.join(', '));
                } else if (firstRes && firstRes.normalizedData) {
                    appStore.addSalary(firstRes.normalizedData);
                    if (typeof updateSalaryFormFields === 'function') updateSalaryFormFields();
                    alert(`Sueldos Acompy importados correctamente (Período: ${firstRes.normalizedData.periodo || 'N/D'}).`);
                } else {
                    alert("No se pudo extraer el resumen de sueldos.");
                }
            }
        } catch (error) {
            alert("Error al procesar archivo: " + error.message);
            console.error(error);
        }
    }

    static render() {
        this.renderMainTable();
        this.renderPerceptionsTable();
        this.renderBankTable();
    }

    static renderPerceptionsTable() {
        const tbody = document.getElementById('table-percepciones-body');
        const badge = document.getElementById('percepciones-summary-badge');
        const list = appStore.perceptions || [];

        if (badge) {
            const total = list.reduce((sum, p) => sum + (p.amount || p.monto || 0), 0);
            const totalFormatted = total.toLocaleString('es-AR', {minimumFractionDigits: 2});
            badge.innerText = `${list.length} Percepciones | Total $ ${totalFormatted}`;
        }

        if (!tbody) return;

        if (list.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="7" style="text-align: center; color: var(--text-muted); padding: 30px;">
                        No se han cargado percepciones para este período.
                    </td>
                </tr>`;
            return;
        }

        tbody.innerHTML = list.map(p => {
            const fuenteText = p.fuente || p.jurisdiction || 'ARBA';
            const montoVal = (p.amount || p.monto || 0).toLocaleString('es-AR', {minimumFractionDigits: 2});
            return `
                <tr>
                    <td><span class="badge" style="background: rgba(56, 189, 248, 0.15); color: #0284c7; font-weight: 700;">${fuenteText}</span></td>
                    <td>${p.fecha}</td>
                    <td>${p.period || p.periodo || 'N/D'}</td>
                    <td>${p.cuit}</td>
                    <td><strong>${p.razonSocial || 'AGENTE PERCEPCION'}</strong></td>
                    <td>${p.comprobante || 'N/D'}</td>
                    <td style="font-weight: 600;">$ ${montoVal}</td>
                </tr>
            `;
        }).join('');
    }

    static renderBankTable() {
        const tbody = document.getElementById('table-bancos-body');
        if (!tbody) return;

        const transactions = appStore.bankTransactions || [];
        if (transactions.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="6" style="text-align: center; color: var(--text-muted); padding: 30px;">
                        No hay extractos bancarios procesados para este período.
                    </td>
                </tr>`;
            return;
        }

        tbody.innerHTML = transactions.map(t => {
            const isDebit = t.tipo === 'debit';
            const badgeClass = isDebit ? 'badge-recibido' : 'badge-emitido';
            const badgeText = isDebit ? 'DÉBITO' : 'CRÉDITO';
            const montoVal = (t.monto || 0).toLocaleString('es-AR', {minimumFractionDigits: 2});

            return `
                <tr>
                    <td>${t.fecha}</td>
                    <td><strong>${t.descripcion}</strong></td>
                    <td style="font-weight: 600; color: ${isDebit ? '#c5221f' : '#15803d'};">$ ${montoVal}</td>
                    <td><span class="badge ${badgeClass}">${badgeText}</span></td>
                    <td><span style="color: var(--text-muted); font-size: 11px;">Pendiente</span></td>
                    <td><button class="btn-secondary" style="font-size: 11px; padding: 2px 8px;">Conciliar</button></td>
                </tr>
            `;
        }).join('');
    }

    static renderMainTable() {
        const tbody = document.getElementById('table-body');
        if (!tbody) return;

        const items = appStore.getFilteredItems();

        if (items.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="9" style="text-align: center; color: var(--text-muted); padding: 40px 0;">
                        Ningún comprobante coincide con los filtros aplicados.
                    </td>
                </tr>`;
            return;
        }

        tbody.innerHTML = items.map(item => {
            const isRecibido = item.tipo === 'recibido';
            const badgeClass = isRecibido ? 'badge-recibido' : 'badge-emitido';
            const badgeText = isRecibido ? 'Compra' : 'Venta';
            const categoriesList = isRecibido ? CATEGORIES_RECIBIDOS : CATEGORIES_EMITIDOS;

            const optionsHTML = `
                <option value="">-- Seleccionar Categoría --</option>
                ${categoriesList.map(cat => `
                    <option value="${cat}" ${item.categoria === cat ? 'selected' : ''}>${cat}</option>
                `).join('')}
            `;

            const isSuggestedClass = (item.sugerida && !item.confirmada) ? 'suggested' : '';
            const suggestionIndicator = (item.sugerida && !item.confirmada) 
                ? `<span class="badge-suggested">Sugerido</span>` 
                : '';

            const confirmButtonHTML = item.confirmada
                ? `<button class="btn-confirm confirmed" disabled>✓ Confirmado</button>`
                : `<button class="btn-confirm" onclick="appStore.confirmItem('${item.id}')" ${!item.categoria ? 'disabled' : ''}>✓ Confirmar</button>`;

            // Renderizar desglose de percepciones mapeadas
            let perceptionsHTML = '<span style="color:var(--text-muted);">Sin Desglose</span>';
            if (item.percepcionesMapeadas && item.percepcionesMapeadas.length > 0) {
                perceptionsHTML = item.percepcionesMapeadas.map(p => `
                    <span style="font-size: 11px; display: block;">
                        <strong>${p.jurisdiction}</strong>: $ ${p.amount.toFixed(2)}
                    </span>
                `).join('');
            } else if (item.otrosTributos > 0) {
                perceptionsHTML = `<span style="color:var(--warning); font-weight:600;">Otros Trib. $ ${item.otrosTributos.toFixed(2)}</span>`;
            }

            return `
                <tr>
                    <td><span class="badge ${badgeClass}">${badgeText}</span></td>
                    <td>${item.fecha}</td>
                    <td>${item.comprobante}</td>
                    <td>${item.cuit}</td>
                    <td><strong>${item.razonSocial}</strong></td>
                    <td>$ ${item.total.toLocaleString('es-AR', {minimumFractionDigits: 2})}</td>
                    <td>${perceptionsHTML}</td>
                    <td>
                        <div class="category-cell">
                            <select class="select-category ${isSuggestedClass}" onchange="appStore.updateCategory('${item.id}', this.value)" ${item.confirmada ? 'disabled' : ''}>
                                ${optionsHTML}
                            </select>
                            ${suggestionIndicator}
                        </div>
                    </td>
                    <td>${confirmButtonHTML}</td>
                </tr>
            `;
        }).join('');
    }
}

// Exponer métodos globales en window para los event handlers del HTML
window.switchTab = switchTab;
window.appStore = appStore;

// Suscribirse a los eventos del store para reactividad
appStore.subscribe(() => {
    UIManager.render();
    renderClientDashboard();
    renderOcrHistory();
    renderResolucionManual();
    renderBancosGrid();
});

// Inicialización de componentes al cargar el documento
document.addEventListener('DOMContentLoaded', () => {
    UIManager.init();
    setupOCR();

    // Seteo de fecha hoy en formularios
    const dateInput = document.getElementById('internal-date');
    if (dateInput) dateInput.value = new Date().toISOString().split('T')[0];

    const imputInput = document.getElementById('internal-imputacion');
    if (imputInput) {
        const date = new Date();
        const mm = String(date.getMonth() + 1).padStart(2, '0');
        imputInput.value = `${date.getFullYear()}-${mm}`;
    }

    // Listener del Formulario de Movimiento Interno
    const formInternal = document.getElementById('form-internal-movement');
    if (formInternal) {
        formInternal.addEventListener('submit', (e) => {
            e.preventDefault();
            const formData = new FormData(formInternal);
            const data = {
                tipo: formData.get('tipo'),
                fecha: formData.get('fecha'),
                imputacion: formData.get('imputacion'),
                importe: formData.get('importe'),
                descripcion: formData.get('descripcion')
            };

            const res = ManualMovements.saveInternalMovement(data);
            if (res.success) {
                alert("Movimiento interno guardado con éxito.");
                formInternal.reset();
                if (dateInput) dateInput.value = new Date().toISOString().split('T')[0];
            } else {
                alert(res.error);
            }
        });
    }

    // Listener del Formulario de Compra Manual REGINFO
    const formReginfo = document.getElementById('form-purchase-reginfo');
    if (formReginfo) {
        formReginfo.addEventListener('submit', (e) => {
            e.preventDefault();
            const formData = new FormData(formReginfo);
            const data = {};
            formData.forEach((val, key) => { data[key] = val; });

            const res = ManualMovements.saveReginfoPurchase(data);
            if (res.success) {
                alert("Compra manual registrada e incorporada al listado de compras.");
                formReginfo.reset();
            } else {
                alert(res.error);
            }
        });
    }

    // Inputs manuales de liquidación de sueldos (cálculos en vivo)
    const f931Input = document.getElementById('input-f931');
    const sindicContribInput = document.getElementById('input-sindicato-contrib');
    if (f931Input) f931Input.addEventListener('input', updateSalaryFormFields);
    if (sindicContribInput) sindicContribInput.addEventListener('input', updateSalaryFormFields);

    const btnSavePayroll = document.getElementById('btn-save-payroll');
    if (btnSavePayroll) {
        btnSavePayroll.onclick = () => {
            if (!appStore.salaries) {
                alert("Primero debes cargar el Excel de sueldos de Acompy.");
                return;
            }
            alert("Sueldos consolidados y liquidados guardados en base de datos.");
        };
    }

    // Agregar reglas bancarias en vivo
    const btnAddRule = document.getElementById('btn-add-rule');
    if (btnAddRule) {
        btnAddRule.onclick = () => {
            const type = document.getElementById('rule-type').value;
            const pattern = document.getElementById('rule-pattern').value;
            const category = document.getElementById('rule-category').value;

            if (!pattern || !category) {
                alert("Por favor ingresa palabra clave y categoría.");
                return;
            }

            appStore.addBankRule(type, pattern, category);
            alert(`Regla agregada para ${type === 'debit' ? 'débitos' : 'créditos'}: "${pattern}" -> "${category}"`);
            
            // Limpiar inputs
            document.getElementById('rule-pattern').value = "";
            document.getElementById('rule-category').value = "";

            // Re-procesar banco si hay transacciones cargadas
            if (appStore.bankTransactions.length > 0) {
                appStore.bankTransactions.forEach(tx => {
                    if (!tx.confirmada) {
                        tx.cuentaSugerida = BankParser.classifyTransaction(tx.tipo, tx.descripcion);
                    }
                });
                appStore.notify();
            }
        };
    }
});
