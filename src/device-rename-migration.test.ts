import { describe, expect, it } from 'vitest'
import migration from '../supabase/migrations/202609220003_device_rename.sql?raw'

describe('device rename migration', () => {
  it('authorizes Owner and Manager but denies Employee for names only', () => {
    expect(migration).toContain("v_employee.role not in ('OWNER','MANAGER')")
    expect(migration).toContain('bsb_owner_rename_device')
    expect(migration).toContain('char_length(v_name) not between 1 and 80')
  })

  it('identifies the current device from the current hashed session credential', () => {
    expect(migration).toContain('bsb_owner_list_devices_with_current')
    expect(migration).not.toContain('create or replace function public.bsb_owner_list_devices(p_session_token text)')
    expect(migration).toContain('token_hash=encode(extensions.digest(p_session_token')
    expect(migration).toContain('(d.id=v_device_id)')
  })

  it('updates only display metadata and does not rotate credentials, sessions, or access status', () => {
    expect(migration).toContain('set display_name=v_name,updated_at=now()')
    expect(migration).not.toMatch(/set\s+token_hash\s*=/i)
    expect(migration).not.toMatch(/employee_terminal_sessions\s+set/)
    expect(migration).not.toMatch(/active\s*=/)
    expect(migration).not.toMatch(/delete\s+from/i)
  })

  it('does not attempt the PostgreSQL-incompatible replacement of the existing five-column list RPC', () => {
    expect(migration).toContain('five-column OUT row type')
    expect(migration).toContain('add a current-aware companion RPC instead')
    expect(migration).toContain('grant execute on function public.bsb_owner_list_devices_with_current(text) to anon')
  })
})
