export const createClient = () => ({
    auth: {
        getSession: async () => ({ data: { session: null } }),
        onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } })
    },
    from: () => ({
        select: () => ({ order: () => ({}) }),
        insert: () => ({ select: () => ({}) }),
        update: () => ({ eq: () => ({ select: () => ({}) }) })
    }),
    rpc: async () => ({ data: null, error: null })
});
