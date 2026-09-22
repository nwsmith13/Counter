import { describe, expect, it } from 'vitest'
import migration from '../supabase/migrations/202609210001_bsb_identity_foundation.sql?raw'
import bootstrap from '../supabase/bootstrap.sql?raw'

const pgcryptoCalls = /(?<!extensions\.)\b(?:digest|crypt|gen_salt|gen_random_bytes)\s*\(/g

describe('Supabase identity migration safety', () => {
  it('installs pgcrypto in extensions and requires that schema', () => {
    expect(migration).toContain('create extension if not exists pgcrypto with schema extensions;')
    expect(migration).toContain("n.nspname='extensions'")
  })

  it('schema-qualifies every pgcrypto call in the migration and bootstrap script', () => {
    expect(migration.match(pgcryptoCalls)).toBeNull()
    expect(bootstrap.match(pgcryptoCalls)).toBeNull()
  })

  it('keeps SECURITY DEFINER paths limited to public and pg_temp', () => {
    expect(migration).not.toContain('set search_path = public, extensions')
    expect(migration).toContain('set search_path = public, pg_temp')
  })
})

