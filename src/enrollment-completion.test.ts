import { describe, expect, it } from 'vitest'
import { completeDeviceEnrollment } from './enrollment-completion'
import { DEVICE_TOKEN_KEY, IDENTITY_SESSION_KEY, clearTerminalSession, readDeviceToken, writeTerminalSession, type TerminalSession } from './identity'

const memoryStorage = () => {
  const values = new Map<string, string>()
  return { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => void values.set(key, value), removeItem: (key: string) => void values.delete(key), values }
}

describe('device enrollment completion', () => {
  it('stores only the opaque device credential, clears the transient setup code, and returns to the canonical URL', () => {
    const storage = memoryStorage(); let setupCode = '9B87F241678E1403'; let path = '/setup'
    completeDeviceEnrollment('opaque-device-credential', { storage, clearSetupCode: () => { setupCode = '' }, replaceUrl: url => { path = url } })
    expect(storage.getItem(DEVICE_TOKEN_KEY)).toBe('opaque-device-credential')
    expect(setupCode).toBe('')
    expect(path).toBe('/')
    expect([...storage.values.values()]).not.toContain('9B87F241678E1403')
    expect(storage.getItem(IDENTITY_SESSION_KEY)).toBeNull()
  })

  it('uses the persisted credential after a simulated refresh or browser relaunch instead of setup data', () => {
    const storage = memoryStorage()
    completeDeviceEnrollment('opaque-device-credential', { storage, clearSetupCode: () => {}, replaceUrl: () => {} })
    expect(readDeviceToken(storage)).toBe('opaque-device-credential')
  })

  it('does not leave a credential behind when browser storage cannot retain it', () => {
    const storage = { getItem: () => null, setItem: () => {} }; let cleared = false
    expect(() => completeDeviceEnrollment('opaque-device-credential', { storage, clearSetupCode: () => { cleared = true }, replaceUrl: () => {} })).toThrow(/could not save/i)
    expect(cleared).toBe(true)
  })

  it('keeps a device credential through employee logout and session expiry cleanup', () => {
    const storage = memoryStorage()
    completeDeviceEnrollment('opaque-device-credential', { storage, clearSetupCode: () => {}, replaceUrl: () => {} })
    const expired: TerminalSession = { token: 'session', employee: { id: 'employee', organizationId: 'org', displayName: 'Employee', role: 'EMPLOYEE', active: true }, expiresAt: '2020-01-01T00:00:00.000Z' }
    writeTerminalSession(expired, storage)
    clearTerminalSession(storage)
    expect(storage.getItem(IDENTITY_SESSION_KEY)).toBeNull()
    expect(readDeviceToken(storage)).toBe('opaque-device-credential')
  })
})
