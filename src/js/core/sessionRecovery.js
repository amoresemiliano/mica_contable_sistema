// Retry only the transient verifier error. Never rewrite or inspect token timestamps.
export async function initializeWithSessionRecovery({ session, auth, initialize, isCurrent = () => true,
    wait = ms => new Promise(resolve => setTimeout(resolve, ms)), delays = [400, 1000, 2000] }) {
    for (let attempt = 0; isCurrent(); attempt++) {
        try { await initialize(session.user); return; }
        catch (error) {
            if (!isCurrent()) return;
            if (error.message !== 'JWT issued at future' || attempt >= delays.length) throw error;
            await wait(delays[attempt]);
            if (!isCurrent()) return;
            const recovered = attempt === 0 ? await auth.refreshSession() : await auth.getSession();
            if (!isCurrent()) return;
            if (recovered.error) throw recovered.error;
            const next = recovered.data?.session;
            if (!next || next.user.id !== session.user.id) throw new Error('La sesión cambió. Volvé a iniciar sesión.');
            session = next;
        }
    }
}
