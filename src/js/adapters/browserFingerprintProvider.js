export function createBrowserFingerprintProvider() {
    return {
        async digest(dataString) {
            if (!globalThis.crypto || !globalThis.crypto.subtle) {
                throw new Error("Web Crypto API no está disponible en este entorno.");
            }
            const encoder = new TextEncoder();
            const data = encoder.encode(dataString);
            const hashBuffer = await globalThis.crypto.subtle.digest('SHA-256', data);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        }
    };
}
