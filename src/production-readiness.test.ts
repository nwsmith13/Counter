import { describe, expect, it } from 'vitest'
import identitySource from './identity.ts?raw'
import identityApiSource from './identity-api.ts?raw'
import openPlayApiSource from './open-play-api.ts?raw'
import exampleEnvironment from '../.env.example?raw'
import readinessSql from '../supabase/verify-production-readiness.sql?raw'

describe('production credential hygiene', () => {
  it('does not support a browser-bundled device credential', () => {
    expect(identitySource).not.toContain('VITE_BSB_DEVICE_TOKEN')
    expect(exampleEnvironment).not.toContain('VITE_BSB_DEVICE_TOKEN')
  })

  it('does not log credentials from identity or shared-state clients', () => {
    for (const source of [identitySource, identityApiSource, openPlayApiSource]) expect(source).not.toMatch(/console\.(log|debug|info|warn|error)/)
  })

  it('documents explicit shared/local mode and browser-safe configuration only', () => {
    expect(exampleEnvironment).toContain('VITE_OPEN_PLAY_SHARED=false')
    expect(exampleEnvironment).toContain('VITE_SUPABASE_URL=')
    expect(exampleEnvironment).toContain('VITE_SUPABASE_ANON_KEY=')
    expect(exampleEnvironment).not.toMatch(/SERVICE_ROLE|PIN=/)
  })

  it('keeps the production database verifier read-only and human-readable', () => {
    expect(readinessSql).toContain("case when ok then 'PASS' else 'FAIL' end")
    expect(readinessSql).toContain('Blue Springs Bowl organization')
    expect(readinessSql).not.toMatch(/^\s*(insert|update|delete|alter|create|drop|truncate|grant|revoke)\b/im)
  })
})
