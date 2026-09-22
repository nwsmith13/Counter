export const ENROLLMENT_CODE_LENGTH = 16

export const normalizeEnrollmentCode = (input: string) => input.toUpperCase().replace(/[^0-9A-F]/g, '').slice(0, ENROLLMENT_CODE_LENGTH)

export const formatEnrollmentCode = (input: string) => {
  const normalized = normalizeEnrollmentCode(input)
  return normalized.length > 8 ? `${normalized.slice(0, 8)}-${normalized.slice(8)}` : normalized
}

export const isCompleteEnrollmentCode = (input: string) => normalizeEnrollmentCode(input).length === ENROLLMENT_CODE_LENGTH

export const enrollmentSetupUrl = (code: string, origin: string) => {
  const url = new URL('/setup', origin)
  url.searchParams.set('code', formatEnrollmentCode(code))
  return url.toString()
}

export const setupCodeFromUrl = (href: string) => {
  try {
    const url = new URL(href)
    return url.pathname === '/setup' ? formatEnrollmentCode(url.searchParams.get('code') ?? '') : ''
  } catch { return '' }
}

export const consumeSetupCode = (href: string, replaceUrl: (url: string) => void) => {
  const code = setupCodeFromUrl(href)
  if (isCompleteEnrollmentCode(code)) replaceUrl(new URL(href).pathname)
  return isCompleteEnrollmentCode(code) ? code : ''
}

export const setupShareText = (code: string, origin: string) => `Blue Springs Bowl — Open Play Book\n\nSet up this device:\n${enrollmentSetupUrl(code, origin)}\n\nSetup code: ${formatEnrollmentCode(code)}\n\nExpires in 15 minutes.`

type ClipboardLike = { writeText: (text: string) => Promise<void> }
type ShareLike = { share: (data: { title: string; text: string; url: string }) => Promise<void> }
export type SetupTransport = { clipboard?: ClipboardLike; share?: ShareLike }

export const shareOrCopySetup = async (code: string, origin: string, transport: SetupTransport): Promise<'shared'|'copied'|'unavailable'|'cancelled'> => {
  const url = enrollmentSetupUrl(code, origin)
  const text = setupShareText(code, origin)
  if (transport.share) {
    try { await transport.share.share({ title: 'Blue Springs Bowl — Open Play Book', text, url }); return 'shared' }
    catch (error) { if (error instanceof DOMException && error.name === 'AbortError') return 'cancelled' }
  }
  if (!transport.clipboard) return 'unavailable'
  await transport.clipboard.writeText(text)
  return 'copied'
}
