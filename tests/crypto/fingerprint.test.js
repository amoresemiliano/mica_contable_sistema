import { createNodeFingerprintProvider } from '../../tests/helpers/nodeFingerprintProvider.js';
import { createBrowserFingerprintProvider } from '../../src/js/adapters/browserFingerprintProvider.js';
import { buildFiscalFingerprint, buildCanonicalFiscalPayload } from '../../src/js/core/services/fiscalFingerprint.js';

// We use standard webcrypto fallback if needed (Jest 29+ usually provides it in standard globals if configured)
import { webcrypto } from 'crypto';
if (typeof globalThis.crypto === 'undefined') {
    globalThis.crypto = webcrypto;
}

describe('Fingerprint Providers', () => {
    it('Node and Browser providers should generate identical hashes', async () => {
        const payload = {
            cuit: "30111111118",
            fecha: "2026-08-01",
            total: 100
        };

        const nodeProvider = createNodeFingerprintProvider();
        const browserProvider = createBrowserFingerprintProvider();

        const hash1 = await buildFiscalFingerprint(payload, nodeProvider);
        const hash2 = await buildFiscalFingerprint(payload, browserProvider);

        expect(hash1).toBe(hash2);
        expect(hash1).toHaveLength(64); // SHA-256 in hex
    });

    it('buildFiscalFingerprint throws if provider is missing', async () => {
        const normalizedData = { total: 100 };
        await expect(buildFiscalFingerprint(normalizedData)).rejects.toThrow(/digest/);
        await expect(buildFiscalFingerprint({ test: 1 }, null)).rejects.toThrow(/obligatorio/);
        await expect(buildFiscalFingerprint({ test: 1 }, {})).rejects.toThrow(/digest/);
    });

    it('buildCanonicalFiscalPayload sorts keys deterministically', () => {
        const obj1 = { total: 100, moneda: 'PES', tipoCambio: 1 };
        const obj2 = { tipoCambio: 1, total: 100, moneda: 'PES' };
        expect(buildCanonicalFiscalPayload(obj1)).toBe(buildCanonicalFiscalPayload(obj2));
        expect(buildCanonicalFiscalPayload(obj1)).toContain('"PES"');
    });
});
