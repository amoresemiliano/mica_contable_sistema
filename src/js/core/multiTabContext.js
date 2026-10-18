// Backend context is per user, not per tab. Never pretend two independent tenants are safe.
export function mountContextInvalidation(store, window) {
    const channel = typeof window.BroadcastChannel === 'function' ? new window.BroadcastChannel('mica-operational-context') : null;
    const key='mica-context-invalidation';
    const invalidate = message => {
        if(!message || !store.sessionUserId || message.user!==store.sessionUserId)return;
        ++store.contextGeneration;store.clearTenantState();store.contextState='ERROR';
        store.contextError='La empresa cambió en otra pestaña. Recargá el contexto antes de continuar.';store.notify();
    };
    if(channel)channel.onmessage=event=>invalidate(event.data);
    window.addEventListener('storage',event=>{if(!channel && event.key===key){try{invalidate(JSON.parse(event.newValue));}catch{}}});
    let previous=store.contextState;
    store.subscribe(()=>{
        const switching=store.contextState==='SWITCHING' && previous!=='SWITCHING';previous=store.contextState;
        if(switching){const message={user:store.sessionUserId,at:Date.now()};
            if(channel)channel.postMessage(message);else try{window.localStorage.setItem(key,JSON.stringify(message));}catch{}
        }
    });
    return {invalidate,close:()=>channel?.close()};
}
