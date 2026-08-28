import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = 'https://ourzapkjykzlwsjunzmd.supabase.co';
const supabasePublishableKey = 'sb_publishable_CS0gCapefFxuRrw-gG2svw_lSmhggsu';

export const supabase = createClient(
  supabaseUrl,
  supabasePublishableKey
);