import { describe, expect, it } from 'vitest'
import app from './main.tsx?raw'
import { APP_VERSION } from './app-info'

describe('Slice 8 counter presentation', () => {
  it('uses the promoted Open Play Book panel wordmark and preserves the release version', () => {
    expect(app).toContain('function OpenPlayBookWordmark()')
    expect(app).toContain('<OpenPlayBookWordmark/>')
    expect(app).not.toContain('<b>Open Play Board</b>')
    expect(APP_VERSION).toBe('1.0.0')
  })

  it('keeps connected quiet while retaining reconnecting and offline operational states', () => {
    expect(app).toContain("connection==='RECONNECTING'")
    expect(app).toContain('● OFFLINE — VIEW ONLY')
  })

  it('keeps modal-owned errors inside the active sheet and retains the modal', () => {
    expect(app).toContain('const ModalErrorContext = createContext')
    expect(app).toContain('className="sheet-error"')
  })

  it('keeps Fit 12 presentation local and does not change lane interaction routing', () => {
    expect(app).toContain("density==='FIT_12'?'fit-12':''")
    expect(app).toContain('const primary=()=>session?open({session:session.id}):open({start:lane})')
  })

  it('has an accessible reduced-motion path for the irregular neon flicker', () => {
    expect(app).toContain("prefers-reduced-motion: reduce")
    expect(app).toContain("15_000+Math.random()*20_000")
  })

  it('keeps the footer identity and removes the standalone PLAY header label', () => {
    expect(app).toContain('className="footer-bsb"')
    expect(app).toContain('BLUE SPRINGS BOWL')
    expect(app).toContain('className="footer-meta"')
    expect(app).not.toContain("}>PLAY</p>")
  })

  it('keeps the promoted 4/4/4 panel wordmark in one horizontal sign line', () => {
    expect(app).toContain("const wordmarkWords = ['OPEN', 'PLAY', 'BOOK']")
    expect(app).toContain('wordmark-sections')
    expect(app).not.toContain('DEVELOPMENT — WORDMARK CONCEPTS')
    expect(app).not.toContain('function WordmarkPreview()')
  })

  it('keeps date/time in the subordinate right-side chrome above Connected', () => {
    expect(app).toContain('className="header-chrome"')
    expect(app).toContain('className="chrome-clock"')
    expect(app).toContain('className="shared-connection connected chrome-connection"')
  })

  it('keeps the production panel wordmark as an explicitly selected header component', () => {
    expect(app).toContain('className="production-wordmark wordmark-concept bowling-alley"')
  })

  it('keeps the production mark in three clean four-letter groups', () => {
    expect(app).toContain("const wordmarkWords = ['OPEN', 'PLAY', 'BOOK']")
    expect(app).toContain('className="production-wordmark wordmark-concept bowling-alley"')
  })

  it('uses custom stroked SVG tubing for the OPEN fixture rather than text lettering', () => {
    expect(app).toContain('function OpenNeonSign')
    expect(app).toContain('className="open-neon-tube"')
    expect(app).not.toContain('aria-label="Open">OPEN</span>')
    expect(app).toContain('transform="translate(-8 0) scale(1.1 1)"')
  })

  it('keeps exactly five decorative approach markers above the Condition control', () => {
    expect(app).toContain('<span className="lane-approach-dots"')
    expect((app.match(/<i>•<\/i>/g) ?? []).length).toBe(5)
  })
})
