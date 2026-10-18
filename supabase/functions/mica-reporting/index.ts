import { createClient } from 'npm:@supabase/supabase-js@2.112.3';
import { createReportingHandler } from '../../../src/js/core/reporting/server.js';

const url = Deno.env.get('SUPABASE_URL')!;
const publicKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const verifier = createClient(url, publicKey, options);
const serviceClient = createClient(url, secret, options);
Deno.serve(createReportingHandler({
    authenticate: async (token: string) => {
        const { data, error } = await verifier.auth.getUser(token);
        return error ? null : data.user;
    },
    userClient: (authorization: string) => createClient(url, publicKey, {
        ...options, global: { headers: { Authorization: authorization } }
    }),
    serviceClient,
    allowedOrigins: (Deno.env.get('MICA_REPORTING_ALLOWED_ORIGINS') || '').split(',').map(s => s.trim()).filter(Boolean)
}));
