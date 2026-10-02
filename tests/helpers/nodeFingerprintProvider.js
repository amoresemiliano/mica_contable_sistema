import crypto from 'crypto';

export function createNodeFingerprintProvider() {
    return {
        async digest(dataString) {
            return crypto.createHash('sha256').update(dataString).digest('hex');
        }
    };
}
