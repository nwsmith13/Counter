export type RuntimeEnvironment = Record<string, string | boolean | undefined>

export type RuntimeConfiguration = {
  shared: boolean
  supabaseUrl: string
  supabaseAnonKey: string
  error: string | null
}

const placeholder = (value: string) => !value || /YOUR_|CHANGEME|EXAMPLE/i.test(value)
const jwtRole = (value: string) => {
  try {
    const payload = value.split('.')[1]
    if (!payload) return ''
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(payload.length / 4) * 4, '=')
    return String((JSON.parse(atob(normalized)) as { role?: unknown }).role ?? '')
  } catch { return '' }
}

export const validateRuntimeConfiguration = (env: RuntimeEnvironment): RuntimeConfiguration => {
  const mode = String(env.VITE_OPEN_PLAY_SHARED ?? '')
  const supabaseUrl = String(env.VITE_SUPABASE_URL ?? '').trim()
  const supabaseAnonKey = String(env.VITE_SUPABASE_ANON_KEY ?? '').trim()

  if (mode !== 'true' && mode !== 'false') {
    return { shared: false, supabaseUrl, supabaseAnonKey, error: 'VITE_OPEN_PLAY_SHARED must be explicitly set to true or false.' }
  }
  if (mode === 'false') return { shared: false, supabaseUrl, supabaseAnonKey, error: null }
  if (placeholder(supabaseUrl) || placeholder(supabaseAnonKey)) {
    return { shared: true, supabaseUrl, supabaseAnonKey, error: 'Shared Open Play requires a Supabase project URL and browser-safe publishable/anon key.' }
  }
  try {
    const url = new URL(supabaseUrl)
    const localDevelopment = url.hostname === 'localhost' || url.hostname === '127.0.0.1'
    if (url.protocol !== 'https:' && !(localDevelopment && url.protocol === 'http:')) throw new Error('unsafe protocol')
  } catch {
    return { shared: true, supabaseUrl, supabaseAnonKey, error: 'VITE_SUPABASE_URL must be a valid HTTPS URL (HTTP is allowed only for local development).' }
  }
  if (/service[_-]?role|sb_secret_/i.test(supabaseAnonKey) || jwtRole(supabaseAnonKey) === 'service_role') {
    return { shared: true, supabaseUrl, supabaseAnonKey, error: 'The configured Supabase key is not browser-safe. Use a publishable/anon key.' }
  }
  return { shared: true, supabaseUrl, supabaseAnonKey, error: null }
}

export const runtimeConfiguration = validateRuntimeConfiguration(import.meta.env)
