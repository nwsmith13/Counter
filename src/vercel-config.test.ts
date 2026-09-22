import { describe, expect, it } from 'vitest'
import configText from '../vercel.json?raw'

describe('Vercel SPA fallback', () => {
  it('routes unmatched SPA paths to the Vite entry point', () => {
    const config = JSON.parse(configText) as { rewrites?: Array<{ source: string; destination: string }> }
    expect(config.rewrites).toEqual([{ source: '/(.*)', destination: '/index.html' }])
  })
})
