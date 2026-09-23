export const LANE_EIGHT_COMPLETE_MS = 5700
export const LANE_POWER_COMPLETE_MS = 5950
export const OPEN_SIGN_DARK_MS = LANE_POWER_COMPLETE_MS
export const OPEN_NEON_POST_LANE_DELAY_MS = 1000
export const OPEN_NEON_POWER_ON_MS = OPEN_SIGN_DARK_MS + OPEN_NEON_POST_LANE_DELAY_MS
export const OPEN_NEON_STARTUP_DURATION_MS = 1180
export const OPEN_NEON_STABLE_MS = OPEN_NEON_POWER_ON_MS + OPEN_NEON_STARTUP_DURATION_MS

export type NeonPresentation = 'HIDDEN'|'DARK'|'STARTUP'|'LIT'
export const neonPresentationAt = (elapsedMs:number, reducedMotion=false):NeonPresentation =>
  reducedMotion || elapsedMs >= OPEN_NEON_STABLE_MS ? 'LIT' : elapsedMs >= OPEN_NEON_POWER_ON_MS ? 'STARTUP' : elapsedMs >= OPEN_SIGN_DARK_MS ? 'DARK' : 'HIDDEN'
