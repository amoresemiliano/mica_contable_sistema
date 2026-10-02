// 1. MOTOR DE CATEGORIZACIÓN INTELIGENTE (SOLID: Single Responsibility)
export class CategorizationEngine {
    constructor() {
        this.storageKey = null;
        this.history = {};
    }

    setContext(userId, orgId) {
        this.storageKey = userId && orgId ? `mica:v2:${userId}:${orgId}:category_history` : null;
        try { this.history = this.storageKey ? JSON.parse(localStorage.getItem(this.storageKey)) || {} : {}; }
        catch { this.history = {}; }
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
        if (!this.storageKey || !cuit || cuit === "S/D") return;
        this.history[cuit] = category;
        localStorage.setItem(this.storageKey, JSON.stringify(this.history));
    }
}

export const categorizer = new CategorizationEngine();
