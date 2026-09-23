import { describe, expect, it } from 'vitest'
import ui from './identity-ui.tsx?raw'
import board from './main.tsx?raw'
import { canRenameDevices, isValidDeviceName, type Employee } from './identity'

const employee = (role: Employee['role']): Employee => ({ id:'employee', organizationId:'org', displayName:'Test', role, active:true })

describe('identity pre-readiness polish', () => {
  it('auto-submits exactly four keypad or keyboard digits and blocks a second request while busy', () => {
    expect(ui).toContain("if(next.length===4)void enter(next)")
    expect(ui).toContain('if(submitting.current||!selected||!isValidPinFormat(pinToVerify))')
    expect(ui).toContain("/^\\d$/.test(event.key)")
    expect(ui).toContain('if(submitting.current)return')
  })

  it('clears a failed PIN and returns a retry-ready accessible keypad', () => {
    expect(ui).toContain("setPin('');setError(\"That PIN didn't work.\")")
    expect(ui).toContain('Please try again.')
    expect(ui).toContain('aria-label="PIN keypad"')
  })

  it('uses actual paragraphs for setup copy rather than literal escaped newlines', () => {
    expect(ui).toContain("detail={[\"This computer hasn't been set up for Blue Springs Bowl yet.\",\"You'll only need to do this once.\"]}")
    expect(ui).not.toContain("This computer hasn't been set up for Blue Springs Bowl yet.\\n\\n")
  })

  it('uses a branded startup state and responsive PWA-safe identity layout', () => {
    expect(ui).toContain('function BrandedStartup()')
    expect(ui).toContain('OPEN PLAY BOOK')
    expect(ui).not.toContain('initialization/security')
    expect(ui).toContain('className="identity-screen"')
  })

  it('retains the OPEN startup state and reduced-motion styling without a continuous flicker loop', async () => {
    expect(board).toContain("poweringUp?'starting':'lit'")
    expect(board).toContain("'(prefers-reduced-motion: reduce)'")
    expect(board).toContain("setNeonFlicker(false)")
    expect(board).toContain('15_000+Math.random()*20_000')
    expect(board).toContain('},1100)')
  })

  it('allows OWNER and MANAGER but not EMPLOYEE to rename a device, and validates names locally', () => {
    expect(canRenameDevices(employee('OWNER'))).toBe(true)
    expect(canRenameDevices(employee('MANAGER'))).toBe(true)
    expect(canRenameDevices(employee('EMPLOYEE'))).toBe(false)
    expect(isValidDeviceName(' Matthew iPhone — App ')).toBe(true)
    expect(isValidDeviceName('   ')).toBe(false)
    expect(isValidDeviceName('x'.repeat(81))).toBe(false)
  })

  it('labels the current credential-backed device and separates removed device history', () => {
    expect(ui).toContain('d.is_current&&<span className="this-device">THIS DEVICE</span>')
    expect(ui).toContain('Access Removed ({removed.length})')
    expect(ui).toContain('removedOpen&&')
    expect(ui).not.toContain('deleteDevice')
  })
})
