import { describe, expect, it, vi } from 'vitest'
import { consumeSetupCode, enrollmentSetupUrl, formatEnrollmentCode, isCompleteEnrollmentCode, normalizeEnrollmentCode, setupCodeFromUrl, setupShareText, shareOrCopySetup } from './enrollment-setup'

const code = '9B87F241-678E1403'
const origin = 'https://open.bluespringsbowl.com'

describe('fast device enrollment transport', () => {
  it('normalizes lowercase, hyphenless, whitespace, and pasted formats into one canonical code', () => {
    for (const input of [code, code.toLowerCase(), '9B87F241678E1403', '9B87 F241 678E 1403']) expect(formatEnrollmentCode(input)).toBe(code)
    expect(normalizeEnrollmentCode('9b87 f241-678e 1403')).toBe('9B87F241678E1403')
    expect(isCompleteEnrollmentCode(code)).toBe(true)
    expect(isCompleteEnrollmentCode('9B87F241')).toBe(false)
  })

  it('extracts only complete setup-link codes and scrubs the visible URL after capture', () => {
    const replace = vi.fn()
    expect(consumeSetupCode(`${origin}/setup?code=9b87%20f241-678e%201403`, replace)).toBe(code)
    expect(replace).toHaveBeenCalledWith('/')
    expect(setupCodeFromUrl(`${origin}/setup?code=bad`)).toBe('BAD')
    expect(consumeSetupCode(`${origin}/setup?code=bad`, replace)).toBe('')
  })

  it('creates QR/setup payloads containing only the one-time setup URL and code', () => {
    const url = enrollmentSetupUrl(code, origin)
    const text = setupShareText(code, origin)
    expect(url).toBe(`${origin}/setup?code=${code}`)
    expect(text).toContain(url)
    expect(text).toContain(code)
    expect(`${url}\n${text}`).not.toMatch(/device_token|session_token|pin|sb_secret/i)
  })

  it('uses native sharing when available and clipboard fallback when it is not', async () => {
    const share = vi.fn().mockResolvedValue(undefined)
    const clipboard = { writeText: vi.fn().mockResolvedValue(undefined) }
    await expect(shareOrCopySetup(code, origin, { share: { share }, clipboard })).resolves.toBe('shared')
    expect(clipboard.writeText).not.toHaveBeenCalled()
    await expect(shareOrCopySetup(code, origin, { clipboard })).resolves.toBe('copied')
    expect(clipboard.writeText).toHaveBeenCalledWith(expect.stringContaining('/setup?code='))
    const failingShare = vi.fn().mockRejectedValue(new Error('share unavailable'))
    await expect(shareOrCopySetup(code, origin, { share: { share: failingShare }, clipboard })).resolves.toBe('copied')
    await expect(shareOrCopySetup(code, origin, {})).resolves.toBe('unavailable')
  })
})
