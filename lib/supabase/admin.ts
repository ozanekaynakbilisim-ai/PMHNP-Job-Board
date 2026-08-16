import { createClient } from '@supabase/supabase-js'
import { getServerSupabaseUrl } from './url'

/**
 * Creates a Supabase admin client with the service role key.
 * This bypasses Row Level Security and should ONLY be used server-side.
 */
export function createAdminClient() {
  const supabaseUrl = getServerSupabaseUrl()
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

  if (!serviceRoleKey) {
    throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY')
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}
