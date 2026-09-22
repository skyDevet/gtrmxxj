import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.warn('⚠️  SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing — DB calls will fail');
}

export const supabase = createClient(url || 'http://localhost', key || 'anon', {
  auth: { persistSession: false, autoRefreshToken: false }
});
