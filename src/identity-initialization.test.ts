import { describe, expect, it, vi } from 'vitest'
import { initializeDevice } from './identity-initialization'
import { DEVICE_ACCESS_REMOVED_CODE, IdentityApiError } from './identity-api'
import { DEVICE_TOKEN_KEY, IDENTITY_SESSION_KEY, type Employee } from './identity'

const employee: Employee = { id:'employee', organizationId:'org', displayName:'Employee', role:'EMPLOYEE', active:true }
const memoryStorage = (values: Record<string,string>={}) => {
  const data=new Map(Object.entries(values))
  return { getItem:(key:string)=>data.get(key)??null, removeItem:(key:string)=>void data.delete(key), data }
}

describe('trusted device startup initialization', () => {
  it('routes a missing device credential to NEW_DEVICE and ignores a cached employee session', async () => {
    const storage=memoryStorage({[IDENTITY_SESSION_KEY]:'cached-session'});const validate=vi.fn()
    await expect(initializeDevice(storage,validate)).resolves.toEqual({status:'NEW_DEVICE'})
    expect(validate).not.toHaveBeenCalled();expect(storage.getItem(IDENTITY_SESSION_KEY)).toBeNull()
  })

  it('validates a present credential before returning TRUSTED', async () => {
    const storage=memoryStorage({[DEVICE_TOKEN_KEY]:'existing-device'});const validate=vi.fn().mockResolvedValue([employee])
    await expect(initializeDevice(storage,validate)).resolves.toEqual({status:'TRUSTED',employees:[employee]})
    expect(validate).toHaveBeenCalledWith('existing-device')
  })

  it('routes a removed device to ACCESS_REMOVED and clears only its employee session', async () => {
    const storage=memoryStorage({[DEVICE_TOKEN_KEY]:'removed-device',[IDENTITY_SESSION_KEY]:'cached-session'})
    const validate=vi.fn().mockRejectedValue(new IdentityApiError('Device access removed',DEVICE_ACCESS_REMOVED_CODE))
    await expect(initializeDevice(storage,validate)).resolves.toEqual({status:'ACCESS_REMOVED'})
    expect(storage.getItem(IDENTITY_SESSION_KEY)).toBeNull();expect(storage.getItem(DEVICE_TOKEN_KEY)).toBe('removed-device')
  })

  it('routes network failure to OFFLINE without deleting either credential', async () => {
    const storage=memoryStorage({[DEVICE_TOKEN_KEY]:'existing-device',[IDENTITY_SESSION_KEY]:'cached-session'})
    await expect(initializeDevice(storage,()=>Promise.reject(new TypeError('Failed to fetch')))).resolves.toEqual({status:'OFFLINE'})
    expect(storage.getItem(DEVICE_TOKEN_KEY)).toBe('existing-device');expect(storage.getItem(IDENTITY_SESSION_KEY)).toBe('cached-session')
  })
})
