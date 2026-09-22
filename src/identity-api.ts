import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { Employee, EmployeeRole, TerminalSession } from './identity'
import { runtimeConfiguration } from './runtime-config'

const url = runtimeConfiguration.supabaseUrl
const anonKey = runtimeConfiguration.supabaseAnonKey
export const identityConfigured = Boolean(url && anonKey && !runtimeConfiguration.error)
const client: SupabaseClient | null = url && anonKey ? createClient(url, anonKey, { auth: { persistSession: false } }) : null

const rpc = async <T>(name: string, args: Record<string, unknown>): Promise<T> => {
  if (!client) throw new Error('Identity service is not configured on this terminal.')
  const { data, error } = await client.rpc(name, args)
  if (error) throw new Error(error.message)
  return data as T
}

const employeeFrom = (value: Record<string, unknown>): Employee => ({
  id: String(value.id), organizationId: String(value.organization_id), displayName: String(value.display_name),
  role: value.role as EmployeeRole, active: Boolean(value.active),
})

export const identityApi = {
  async listActive(deviceToken: string): Promise<Employee[]> {
    const rows = await rpc<Record<string, unknown>[]>('bsb_list_active_employees', { p_device_token: deviceToken })
    return rows.map(employeeFrom)
  },
  async verifyPin(deviceToken: string, employeeId: string, pin: string): Promise<TerminalSession> {
    const value = await rpc<Record<string, unknown>>('bsb_verify_employee_pin', { p_device_token: deviceToken, p_employee_id: employeeId, p_pin: pin })
    return { token: String(value.session_token), expiresAt: String(value.expires_at), employee: employeeFrom(value.employee as Record<string, unknown>) }
  },
  async listAll(sessionToken: string): Promise<Employee[]> {
    const rows = await rpc<Record<string, unknown>[]>('bsb_owner_list_employees', { p_session_token: sessionToken })
    return rows.map(employeeFrom)
  },
  async saveEmployee(sessionToken: string, input: { id?: string; displayName: string; role: EmployeeRole; active: boolean; pin?: string }): Promise<Employee> {
    const value = await rpc<Record<string, unknown>>('bsb_owner_save_employee', { p_session_token: sessionToken, p_employee_id: input.id ?? null, p_display_name: input.displayName, p_role: input.role, p_active: input.active, p_pin: input.pin ?? null })
    return employeeFrom(value)
  },
  listDevices: (sessionToken: string) => rpc<{ id:string; display_name:string; active:boolean; last_seen_at:string|null; created_at:string }[]>('bsb_owner_list_devices',{p_session_token:sessionToken}),
  createDeviceEnrollment: (sessionToken:string, deviceName:string) => rpc<{code:string;expires_at:string;device_name:string}>('bsb_owner_create_device_enrollment',{p_session_token:sessionToken,p_device_name:deviceName}),
  redeemDeviceEnrollment: (code:string) => rpc<{device_token:string;device_name:string}>('bsb_redeem_device_enrollment',{p_code:code}),
  setDeviceActive: (sessionToken:string,id:string,active:boolean) => rpc<void>('bsb_owner_set_device_active',{p_session_token:sessionToken,p_device_id:id,p_active:active}),
}
