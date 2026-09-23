import { describe, expect, it } from 'vitest'
import mainSource from './main.tsx?raw'
import verifier from '../supabase/verify-production-readiness.sql?raw'

describe('closed-night defense in depth', () => {
  it('routes archived sessions to a read-only view with no mutation callbacks', () => {
    expect(mainSource).toContain("status==='ARCHIVED'?<ArchivedSessionSheet")
    const archived = mainSource.slice(mainSource.indexOf('function ArchivedSessionSheet'), mainSource.indexOf('function VoidControls'))
    expect(archived).toContain('view only')
    for (const mutation of ['reopenSession(', 'reinstateSession(', 'voidSession(', 'closeSession(', 'editActiveSession(', 'addLane(', 'moveLane(', 'releaseLane(']) {
      expect(archived).not.toContain(mutation)
    }
  })

  it('maps the database closed-night rejection to non-connectivity operator copy', () => {
    expect(mainSource).toContain('isClosedNightFailure(e)?CLOSED_NIGHT_MESSAGE')
  })

  it('keeps the production verifier read only while covering the new barrier and device RPCs', () => {
    expect(verifier).toContain("('bsb_owner_list_devices_with_current(text)')")
    expect(verifier).toContain("('bsb_owner_rename_device(text,uuid,text)')")
    expect(verifier).toContain('bsb_open_play_sessions_open_night_barrier')
    expect(verifier).toContain('no unresolved sessions in closed nights')
    expect(verifier).toContain('no active assignments in closed nights')
    expect(verifier).not.toMatch(/(?:^|\n)\s*(insert|update|delete|alter|create|drop|truncate)\b/im)
  })
})
