import { readDeviceToken, writeDeviceToken } from './identity'
import { CANONICAL_APPLICATION_PATH } from './enrollment-setup'

type DeviceStorage = Pick<Storage, 'getItem' | 'setItem'>

export type EnrollmentCompletion = {
  storage: DeviceStorage
  clearSetupCode: () => void
  replaceUrl: (url: string) => void
}

// The enrollment secret is single-use transport data. Only the opaque device
// credential returned by the redemption RPC is allowed to survive completion.
export const completeDeviceEnrollment = (deviceToken: string, completion: EnrollmentCompletion) => {
  completion.clearSetupCode()
  writeDeviceToken(deviceToken, completion.storage)
  if (readDeviceToken(completion.storage) !== deviceToken) throw new Error('This browser could not save its device credential. Use a non-private browser and ask an OWNER for a new setup code.')
  completion.replaceUrl(CANONICAL_APPLICATION_PATH)
}
