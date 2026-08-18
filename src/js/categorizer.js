// 1. MOTOR DE CATEGORIZACIÓN INTELIGENTE (SOLID: Single Responsibility)
export class CategorizationEngine {
    constructor() {
        this.storageKey = 'mica_category_history';
        const raw = (typeof localStorage !== 'undefined' && localStorage.getItem) ? localStorage.getItem(this.storageKey) : null;
        this.history = JSON.parse(raw) || {};
    }

    // Busca si ya hay un patrón registrado para este CUIT
    getSuggestion(cuit) {
        if (this.history[cuit]) {
            return { category: this.history[cuit], exists: true };
        }
        return { category: "", exists: false };
    }

    // Registra una nueva regla persistente
    saveMapping(cuit, category) {
        if (!cuit || cuit === "S/D") return;
        this.history[cuit] = category;
        localStorage.setItem(this.storageKey, JSON.stringify(this.history));
    }
}

export const categorizer = new CategorizationEngine();
