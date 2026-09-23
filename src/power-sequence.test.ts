import { describe,expect,it } from 'vitest'
import { LANE_EIGHT_COMPLETE_MS,LANE_POWER_COMPLETE_MS,OPEN_NEON_POST_LANE_DELAY_MS,OPEN_NEON_POWER_ON_MS,OPEN_NEON_STARTUP_DURATION_MS,OPEN_NEON_STABLE_MS,OPEN_SIGN_DARK_MS,neonPresentationAt } from './power-sequence'

describe('open neon power-up sequence',()=>{
  it('keeps the entire sign visually hidden through lane power-up, including Lane 8',()=>{expect(neonPresentationAt(0)).toBe('HIDDEN');expect(neonPresentationAt(LANE_EIGHT_COMPLETE_MS)).toBe('HIDDEN');expect(neonPresentationAt(LANE_POWER_COMPLETE_MS-1)).toBe('HIDDEN')})
  it('reveals a dark sign only after the complete lane sequence',()=>{expect(OPEN_SIGN_DARK_MS).toBe(LANE_POWER_COMPLETE_MS);expect(neonPresentationAt(OPEN_SIGN_DARK_MS)).toBe('DARK')})
  it('holds DARK for a beat, then enters a distinct startup flicker',()=>{expect(OPEN_NEON_POWER_ON_MS).toBe(OPEN_SIGN_DARK_MS+OPEN_NEON_POST_LANE_DELAY_MS);expect(neonPresentationAt(OPEN_NEON_POWER_ON_MS-1)).toBe('DARK');expect(neonPresentationAt(OPEN_NEON_POWER_ON_MS)).toBe('STARTUP')})
  it('keeps startup flicker separate from stable LIT and settles after 1.18 seconds',()=>{expect(OPEN_NEON_STARTUP_DURATION_MS).toBe(1180);expect(neonPresentationAt(OPEN_NEON_STABLE_MS-1)).toBe('STARTUP');expect(neonPresentationAt(OPEN_NEON_STABLE_MS)).toBe('LIT')})
  it('uses a distinct whole-sign HIDDEN state rather than treating it as neon-off',()=>{expect(neonPresentationAt(0)).toBe('HIDDEN');expect(neonPresentationAt(OPEN_SIGN_DARK_MS)).not.toBe('HIDDEN')})
  it('keeps reduced-motion presentation immediate',()=>{expect(neonPresentationAt(0,true)).toBe('LIT')})
})
