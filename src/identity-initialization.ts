import { clearTerminalSession, readDeviceToken, type Employee } from './identity'
import { isDeviceAccessRemoved } from './identity-api'

export type DeviceStartupState =
  | { status: 'CHECKING' }
  | { status: 'TRUSTED'; employees: Employee[] }
  | { status: 'NEW_DEVICE' }
  | { status: 'ACCESS_REMOVED' }
  | { status: 'OFFLINE' }

type IdentityStorage = Pick<Storage, 'getItem' | 'removeItem'>

export const initializeDevice = async (
  storage: IdentityStorage,
  validate: (deviceToken: string) => Promise<Employee[]>,
): Promise<DeviceStartupState> => {
  const deviceToken = readDeviceToken(storage)
  if (!deviceToken) {
    clearTerminalSession(storage)
    return { status: 'NEW_DEVICE' }
  }

  try {
    return { status: 'TRUSTED', employees: await validate(deviceToken) }
  } catch (error) {
    if (isDeviceAccessRemoved(error)) {
      clearTerminalSession(storage)
      return { status: 'ACCESS_REMOVED' }
    }
    return { status: 'OFFLINE' }
  }
}
