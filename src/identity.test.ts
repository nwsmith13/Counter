import { describe, expect, it } from 'vitest'
import { canManageDevices, canManageEmployees, canRemoveDeviceAccess, clearTerminalSession, DEVICE_TOKEN_KEY, IDENTITY_SESSION_KEY, isSessionUsable, isValidPinFormat, readTerminalSession, writeDeviceToken, writeTerminalSession, type Employee, type TerminalSession } from './identity'
import { STORAGE_KEY } from './store'
import { ownerEdit, preservesActiveOwner } from './owner-safety'

const employee = (role: Employee['role']='EMPLOYEE', active=true): Employee => ({ id:'employee-1', organizationId:'org-1', displayName:'Matthew', role, active })
const session = (patch: Partial<TerminalSession>={}): TerminalSession => ({ token:'opaque-session-token', employee:employee(), expiresAt:'2099-01-01T00:00:00.000Z', ...patch })
const memoryStorage = () => { const values=new Map<string,string>(); return { getItem:(key:string)=>values.get(key)??null,setItem:(key:string,value:string)=>void values.set(key,value),removeItem:(key:string)=>void values.delete(key),values } }

describe('shared employee identity', () => {
  it('accepts only a four digit PIN representation', () => {
    expect(isValidPinFormat('1234')).toBe(true)
    expect(isValidPinFormat('123')).toBe(false)
    expect(isValidPinFormat('12a4')).toBe(false)
  })

  it('restores an unexpired active terminal user', () => {
    const storage=memoryStorage(); writeTerminalSession(session(),storage)
    expect(readTerminalSession(storage)?.employee.displayName).toBe('Matthew')
  })

  it('rejects expired and inactive persisted sessions', () => {
    expect(isSessionUsable(session({expiresAt:'2026-09-22T03:00:00.000Z'}),new Date('2026-09-22T03:00:00.000Z').getTime())).toBe(false)
    expect(isSessionUsable(session({employee:employee('EMPLOYEE',false)}),new Date('2026-09-21').getTime())).toBe(false)
  })

  it('lock and switch storage clearing do not alter Open Play data', () => {
    const storage=memoryStorage(); storage.setItem(STORAGE_KEY,'{"protected":true}');writeTerminalSession(session(),storage)
    clearTerminalSession(storage)
    expect(storage.getItem(IDENTITY_SESSION_KEY)).toBeNull()
    expect(storage.getItem(STORAGE_KEY)).toBe('{"protected":true}')
  })

  it('allows only OWNER to manage employees', () => {
    expect(canManageEmployees(employee('OWNER'))).toBe(true)
    expect(canManageEmployees(employee('MANAGER'))).toBe(false)
    expect(canManageEmployees(employee('EMPLOYEE'))).toBe(false)
  })

  it('allows OWNER and MANAGER to view/add devices but only OWNER to remove access', () => {
    const storage=memoryStorage(); writeDeviceToken('new-device-token',storage)
    expect(storage.getItem(DEVICE_TOKEN_KEY)).toBe('new-device-token')
    expect(storage.getItem(STORAGE_KEY)).toBeNull()
    expect(canManageDevices(employee('OWNER'))).toBe(true)
    expect(canManageDevices(employee('MANAGER'))).toBe(true)
    expect(canManageDevices(employee('EMPLOYEE'))).toBe(false)
    expect(canRemoveDeviceAccess(employee('OWNER'))).toBe(true)
    expect(canRemoveDeviceAccess(employee('MANAGER'))).toBe(false)
    expect(canRemoveDeviceAccess(employee('EMPLOYEE'))).toBe(false)
  })

  describe('active owner safety invariant', () => {
    const owner = (id: string): Employee => ({ ...employee('OWNER'), id })
    const manager = (id: string): Employee => ({ ...employee('MANAGER'), id })

    it('does not allow the sole active owner to deactivate themselves', () => {
      expect(preservesActiveOwner([owner('owner-1')], 'owner-1', ownerEdit('OWNER', false))).toBe(false)
    })

    it('does not allow the sole active owner to demote themselves', () => {
      expect(preservesActiveOwner([owner('owner-1')], 'owner-1', ownerEdit('MANAGER', true))).toBe(false)
    })

    it('allows one of two active owners to be deactivated', () => {
      expect(preservesActiveOwner([owner('owner-1'), owner('owner-2')], 'owner-1', ownerEdit('OWNER', false))).toBe(true)
    })

    it('allows one of two active owners to be demoted', () => {
      expect(preservesActiveOwner([owner('owner-1'), owner('owner-2')], 'owner-1', ownerEdit('EMPLOYEE', true))).toBe(true)
    })

    it('allows normal OWNER editing of manager and employee records', () => {
      expect(preservesActiveOwner([owner('owner-1'), manager('manager-1')], 'manager-1', ownerEdit('EMPLOYEE', false))).toBe(true)
    })
  })
})
