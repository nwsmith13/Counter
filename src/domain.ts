export type SessionType = 'OPEN_BOWLING' | 'PRE_POST' | 'PARTY'
export type SessionStatus = 'ACTIVE' | 'AWAITING_CLOSE' | 'COMPLETED'
export type LaneConditionKind = 'AVAILABLE' | 'DOWN' | 'WATCH'
export type LaneNumber = number

export type LaneCondition = { laneNumber: LaneNumber; condition: LaneConditionKind; note: string | null; updatedAt: string }
export type League = { id: string; name: string; active: boolean; sortOrder: number; deleted?: boolean }
export type Night = { id: string; businessDate: string; openedAt: string; closedAt: string | null; status: 'OPEN' | 'ARCHIVED' }
export type LaneAssignment = { id: string; sessionId: string; laneNumber: LaneNumber; startedAt: string; billableStartedAt?: string | null; endedAt: string | null; endReason: 'RELEASED' | 'SESSION_ENDED' | null; downOverrideConfirmed: boolean }
export type Pricing = { laneRateCentsPerHour: number; shoeRateCents: number; gracePeriodMinutes: number; minimumChargeCents: number; calculatedTotalCents: number | null; roundedTotalCents: number | null; chargedTotalCents: number | null; adjustmentNote: string | null }
export type SessionBase = { id: string; nightId: string; type: SessionType; status: SessionStatus; startedAt: string; endedAt: string | null; createdAt: string; updatedAt: string; notes: string | null }
export type OpenSession = SessionBase & { type: 'OPEN_BOWLING'; partyName: string | null; bowlerCount: number; shoeCount: number; pricing: Pricing }
export type PrePostSession = SessionBase & { type: 'PRE_POST'; leagueId: string; leagueNameSnapshot: string; designation: 'PRE' | 'POST'; teamDescription: string | null; bowlerCount?: number }
export type PartySession = SessionBase & { type: 'PARTY'; partyName: string; bowlerCount?: number; partyAmountCents?: number }
export type Session = OpenSession | PrePostSession | PartySession
export type ActivityEvent = { id: string; nightId: string; occurredAt: string; type: string; sessionId: string | null; laneNumbers: number[]; summary: string }
export type Settings = { timezone: string; laneCount: number; openBowlingLaneRateCents: number; shoeRentalRateCents: number; openBowlingGracePeriodMinutes: number; openBowlingMinimumChargeCents: number; showFactsAndJokes: boolean; soundEffectsEnabled: boolean }
export type AppState = { schemaVersion: 1; settings: Settings; currentNightId: string | null; nights: Record<string, Night>; sessions: Record<string, Session>; laneAssignments: Record<string, LaneAssignment>; leagues: Record<string, League>; laneConditions: Record<string, LaneCondition>; activity: ActivityEvent[] }

const id = () => crypto.randomUUID()
export const iso = (date = new Date()) => date.toISOString()
export const defaults = (): AppState => ({ schemaVersion: 1, settings: { timezone: 'America/Chicago', laneCount: 12, openBowlingLaneRateCents: 2500, shoeRentalRateCents: 300, openBowlingGracePeriodMinutes: 5, openBowlingMinimumChargeCents: 500, showFactsAndJokes: true, soundEffectsEnabled: false }, currentNightId: null, nights: {}, sessions: {}, laneAssignments: {}, leagues: Object.fromEntries(['Tuesday', 'Wednesday Early', 'Wednesday Late', 'Thursday Match Point', 'Friday Early', 'Friday Late'].map((name, sortOrder) => { const league = { id: id(), name, active: true, sortOrder }; return [league.id, league] })), laneConditions: Object.fromEntries(Array.from({ length: 12 }, (_, i) => [String(i + 1), { laneNumber: i + 1, condition: 'AVAILABLE', note: null, updatedAt: iso() }])), activity: [] })
export const activeAssignments = (state: AppState, sessionId?: string) => Object.values(state.laneAssignments).filter(a => !a.endedAt && (!sessionId || a.sessionId === sessionId))
export const assignmentsFor = (state: AppState, sessionId: string) => Object.values(state.laneAssignments).filter(a => a.sessionId === sessionId)
export const currentNight = (state: AppState) => state.currentNightId ? state.nights[state.currentNightId] : undefined
export const occupiedBy = (state: AppState, lane: number) => activeAssignments(state).find(a => a.laneNumber === lane)
export const cents = (value: number) => `$${(value / 100).toFixed(2)}`
export const whole = (value: number) => `$${Math.round(value / 100)}`
export const laneDurationMs = (assignment: LaneAssignment, now: string) => Math.max(0, new Date(assignment.endedAt ?? now).getTime() - new Date(assignment.startedAt).getTime())
export const OPEN_BOWLING_GRACE_MS = 5 * 60 * 1000
export const OPEN_BOWLING_MINIMUM_CENTS = 500
export const gracePeriodMs = (minutes: number | undefined) => Math.max(0, (minutes ?? 5) * 60 * 1000)
export const graceRemainingMs = (assignment: LaneAssignment, graceMinutes: number | undefined, now: string) => assignment.billableStartedAt ? 0 : Math.max(0, new Date(assignment.startedAt).getTime() + gracePeriodMs(graceMinutes) - new Date(now).getTime())
export const billableLaneDurationMs = (assignment: LaneAssignment, graceMinutes: number | undefined, now: string) => {
  const naturalStart = new Date(assignment.startedAt).getTime() + gracePeriodMs(graceMinutes)
  const billableStart = assignment.billableStartedAt ? new Date(assignment.billableStartedAt).getTime() : naturalStart
  return Math.max(0, new Date(assignment.endedAt ?? now).getTime() - billableStart)
}
export const calculatePricing = (state: AppState, session: OpenSession, now = iso()) => {
  // Grace is assignment-specific so lanes added later receive their own five minutes.
  const duration = assignmentsFor(state, session.id).reduce((total, assignment) => total + billableLaneDurationMs(assignment, session.pricing.gracePeriodMinutes, now), 0)
  const laneTimeCents = Math.round(duration * session.pricing.laneRateCentsPerHour / 3_600_000)
  const shoeCents = session.shoeCount * session.pricing.shoeRateCents
  const calculatedTotalCents = laneTimeCents + shoeCents
  return { duration, laneTimeCents, shoeCents, calculatedTotalCents, roundedTotalCents: Math.round(calculatedTotalCents / 100) * 100 }
}
export const defaultChargeCents = (roundedTotalCents: number, minimumChargeCents = OPEN_BOWLING_MINIMUM_CENTS) => Math.max(minimumChargeCents, roundedTotalCents)
export const formatDuration = (ms: number) => { const seconds = Math.max(0, Math.floor(ms / 1000)); return `${Math.floor(seconds / 3600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}` }
export const displayName = (session: Session) => session.type === 'OPEN_BOWLING' ? session.partyName || 'Open Bowling' : session.type === 'PARTY' ? session.partyName : session.teamDescription || session.leagueNameSnapshot
export const completedPartyRevenueCents = (state: AppState, nightId: string | undefined) => Object.values(state.sessions).filter((session): session is PartySession => session.nightId === nightId && session.type === 'PARTY' && session.status === 'COMPLETED').reduce((total, session) => total + (session.partyAmountCents ?? 0), 0)
export type NightRevenueSummary = { calculatedOpenBowlingCents: number; openBowlingCollectedCents: number; shoeRentalCount: number; shoeComponentCents: number; partyCollectedCents: number; totalCollectedCents: number; openBowlingAdjustmentCents: number }
export const nightRevenueSummary = (state: AppState, nightId: string | undefined): NightRevenueSummary => {
  const completedOpen = Object.values(state.sessions).filter((session): session is OpenSession => session.nightId === nightId && session.type === 'OPEN_BOWLING' && session.status === 'COMPLETED')
  const calculatedOpenBowlingCents = completedOpen.reduce((total, session) => total + (session.pricing.calculatedTotalCents ?? 0), 0)
  const openBowlingCollectedCents = completedOpen.reduce((total, session) => total + (session.pricing.chargedTotalCents ?? 0), 0)
  const shoeRentalCount = completedOpen.reduce((total, session) => total + session.shoeCount, 0)
  const shoeComponentCents = completedOpen.reduce((total, session) => total + session.shoeCount * session.pricing.shoeRateCents, 0)
  const partyCollectedCents = completedPartyRevenueCents(state, nightId)
  return { calculatedOpenBowlingCents, openBowlingCollectedCents, shoeRentalCount, shoeComponentCents, partyCollectedCents, totalCollectedCents: openBowlingCollectedCents + partyCollectedCents, openBowlingAdjustmentCents: openBowlingCollectedCents - calculatedOpenBowlingCents }
}
export const makeId = id
export const toLocalDateTimeInput = (utc: string) => { const d = new Date(utc); const offset = d.getTimezoneOffset() * 60_000; return new Date(d.getTime() - offset).toISOString().slice(0, 16) }
export const fromLocalDateTimeInput = (value: string) => new Date(value).toISOString()
