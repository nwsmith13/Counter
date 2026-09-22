import { describe, expect, it } from 'vitest'
import { validateRuntimeConfiguration } from './runtime-config'

const shared = { VITE_OPEN_PLAY_SHARED: 'true', VITE_SUPABASE_URL: 'https://project.supabase.co', VITE_SUPABASE_ANON_KEY: 'sb_publishable_browser_safe_key' }

describe('runtime production configuration', () => {
  it('requires an explicit operating mode so production cannot silently become local-only', () => {
    expect(validateRuntimeConfiguration({}).error).toMatch(/explicitly set/)
  })

  it('fails shared mode closed when configuration is absent or malformed', () => {
    expect(validateRuntimeConfiguration({ VITE_OPEN_PLAY_SHARED: 'true' }).error).toMatch(/requires a Supabase/)
    expect(validateRuntimeConfiguration({ ...shared, VITE_SUPABASE_URL: 'http://project.supabase.co' }).error).toMatch(/HTTPS/)
    expect(validateRuntimeConfiguration({ ...shared, VITE_SUPABASE_ANON_KEY: 'sb_secret_server_key' }).error).toMatch(/not browser-safe/)
    expect(validateRuntimeConfiguration({ ...shared, VITE_SUPABASE_ANON_KEY: 'header.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature' }).error).toMatch(/not browser-safe/)
  })

  it('accepts browser-safe shared configuration', () => {
    expect(validateRuntimeConfiguration(shared)).toMatchObject({ shared: true, error: null })
  })

  it('preserves explicitly selected local-only development mode without Supabase settings', () => {
    expect(validateRuntimeConfiguration({ VITE_OPEN_PLAY_SHARED: 'false' })).toMatchObject({ shared: false, error: null })
  })
})
