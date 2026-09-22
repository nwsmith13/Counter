import { describe, expect, it } from 'vitest'
import migration from '../supabase/migrations/202609220002_trusted_device_experience.sql?raw'
import originalEnrollment from '../supabase/migrations/202609210005_device_enrollment.sql?raw'

describe('trusted device experience migration', () => {
  it('allows active Owner or Manager sessions to list devices and create setup codes', () => {
    expect(migration.match(/role not in \('OWNER','MANAGER'\)/g)).toHaveLength(2)
    expect(migration).toContain('bsb_owner_list_devices')
    expect(migration).toContain('bsb_owner_create_device_enrollment')
    expect(migration).toContain('v_employee:=public.bsb_session_employee(p_session_token)')
  })

  it('does not replace the Owner-only removal RPC or its current-device safety check', () => {
    expect(migration).not.toMatch(/create or replace function public\.bsb_owner_set_device_active/)
    expect(originalEnrollment).toContain("v.role<>'OWNER'")
    expect(originalEnrollment).toContain("d.id=(select device_id from public.employee_terminal_sessions")
  })

  it('preserves short-lived hashed one-use codes and concurrent redemption safety', () => {
    expect(migration).toContain("now()+interval '15 minutes'")
    expect(migration).toContain("extensions.digest(c,'sha256')")
    expect(migration).toContain('used_at is not null')
    expect(migration).toContain('for update')
    expect(migration).toContain('update public.device_enrollment_codes set used_at=now()')
  })

  it('creates a new independent hashed device credential and returns it only at redemption', () => {
    expect(migration).toContain("token:=encode(extensions.gen_random_bytes(32),'hex')")
    expect(migration).toContain("extensions.digest(token,'sha256')")
    expect(migration).toContain("jsonb_build_object('device_token',token")
  })

  it('uses stable classifications and keeps hardened function boundaries', () => {
    expect(migration).toContain("errcode='BSB01'")
    expect(migration).toContain("errcode='BSB02'")
    expect(migration.match(/security definer set search_path = public, pg_temp/g)).toHaveLength(4)
    expect(migration).not.toMatch(/(?<!extensions\.)\b(?:digest|crypt|gen_salt|gen_random_bytes)\s*\(/)
  })
})
