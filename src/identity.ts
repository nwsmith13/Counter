export type EmployeeRole = 'OWNER' | 'MANAGER' | 'EMPLOYEE'

export type Employee = {
  id: string
  organizationId: string
  displayName: string
  role: EmployeeRole
  active: boolean
}

export type TerminalSession = {
  token: string
  employee: Employee
  expiresAt: string
}

export const IDENTITY_SESSION_KEY = 'bsb-identity:session:v1'
export const DEVICE_TOKEN_KEY = 'bsb-identity:device:v1'
export const readDeviceToken = (storage: Pick<Storage, 'getItem'> = localStorage) => storage.getItem(DEVICE_TOKEN_KEY) || ''
export const writeDeviceToken = (token: string, storage: Pick<Storage, 'setItem'> = localStorage) => storage.setItem(DEVICE_TOKEN_KEY, token)

export const isSessionUsable = (session: TerminalSession | null, now = Date.now()) =>
  !!session && session.employee.active && new Date(session.expiresAt).getTime() > now

export const readTerminalSession = (storage: Pick<Storage, 'getItem'> = localStorage): TerminalSession | null => {
  try {
    const value = storage.getItem(IDENTITY_SESSION_KEY)
    if (!value) return null
    const parsed = JSON.parse(value) as TerminalSession
    return isSessionUsable(parsed) ? parsed : null
  } catch { return null }
}

export const writeTerminalSession = (session: TerminalSession, storage: Pick<Storage, 'setItem'> = localStorage) =>
  storage.setItem(IDENTITY_SESSION_KEY, JSON.stringify(session))

export const clearTerminalSession = (storage: Pick<Storage, 'removeItem'> = localStorage) =>
  storage.removeItem(IDENTITY_SESSION_KEY)

export const canManageEmployees = (employee: Employee | null) => employee?.role === 'OWNER'
export const canManageDevices = (employee: Employee | null) => employee?.role === 'OWNER' || employee?.role === 'MANAGER'
export const canRenameDevices = canManageDevices
export const canRemoveDeviceAccess = (employee: Employee | null) => employee?.role === 'OWNER'
export const isValidPinFormat = (pin: string) => /^\d{4}$/.test(pin)
export const isValidDeviceName = (name: string) => { const trimmed=name.trim(); return trimmed.length > 0 && trimmed.length <= 80 }
