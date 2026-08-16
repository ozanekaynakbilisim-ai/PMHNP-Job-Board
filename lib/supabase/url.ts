export function getServerSupabaseUrl(): string {
  const url = process.env.SUPABASE_INTERNAL_URL || process.env.NEXT_PUBLIC_SUPABASE_URL

  if (!url) {
    throw new Error('Missing SUPABASE_INTERNAL_URL or NEXT_PUBLIC_SUPABASE_URL')
  }

  return url
}
