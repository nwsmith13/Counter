import { describe, expect, it } from 'vitest'
import ui from './identity-ui.tsx?raw'

describe('trusted device employee-facing language', () => {
  it('contains the approved setup, recovery, and PIN copy', () => {
    for (const copy of [
      'SET UP THIS DEVICE', "This computer hasn't been set up for Blue Springs Bowl yet.", "You'll only need to do this once.",
      'I HAVE A SETUP CODE', 'ENTER SETUP CODE', 'FINISH SETUP', 'THIS DEVICE IS READY', 'ACCESS REMOVED',
      'THAT CODE NO LONGER WORKS', 'INTERNET CONNECTION NEEDED', "That PIN didn't work.", 'Center Devices',
      'Add Device', 'Device Name', 'Create Setup Code', 'Copy Code', 'Remove Access', 'Last Used',
    ]) expect(ui).toContain(copy)
  })

  it('does not offer PIN-only setup or use security jargon in setup and device management copy', () => {
    expect(ui).not.toContain('Yes — Set It Up Now')
    expect(ui).not.toContain('AUTHORIZE DEVICE')
    expect(ui).not.toContain('Authorize New Device')
    expect(ui).not.toContain('ready to enroll')
  })
})
