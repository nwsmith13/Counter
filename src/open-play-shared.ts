import { defaults, type ActivityEvent, type AppState, type Booking, type LaneAssignment, type LaneCondition, type League, type Night, type Session } from './domain'
import type { SharedOpenPlaySnapshot, VersionedSession } from './open-play-api'
import { runtimeConfiguration } from './runtime-config'

export const SHARED_OPEN_PLAY_CACHE_KEY = 'bsb-open-play-shared-cache:v1'
export const sharedOpenPlayEnabled = runtimeConfiguration.shared

const object = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
const array = (value: unknown): Record<string, unknown>[] => Array.isArray(value) ? value.map(object) : []
const text = (value: unknown) => String(value ?? '')
const nullableText = (value: unknown) => value == null ? null : String(value)

const nightFrom = (value: unknown): Night | null => {
  const row = object(value)
  if (!row.id) return null
  return { id: text(row.id), businessDate: text(row.businessDate), openedAt: text(row.openedAt), closedAt: nullableText(row.closedAt), status: row.status === 'ARCHIVED' ? 'ARCHIVED' : 'OPEN' }
}

const sessionFrom = (value: Record<string, unknown>): VersionedSession | null => {
  const data = object(value.data)
  if (!value.id || !value.nightId || !value.type) return null
  return {
    ...data,
    id: text(value.id), nightId: text(value.nightId), type: value.type as Session['type'], status: value.status as Session['status'],
    startedAt: text(value.startedAt), endedAt: nullableText(value.endedAt), checkedOutAt: nullableText(value.checkedOutAt), reopenedAt: nullableText(value.reopenedAt), createdAt: text(value.createdAt), updatedAt: text(value.updatedAt),
    voidedAt: nullableText(value.voidedAt), voidedBy: nullableText(value.voidedBy), voidedByName: nullableText(value.voidedByName), voidCategory: nullableText(value.voidCategory), voidNote: nullableText(value.voidNote), preVoidStatus: nullableText(value.preVoidStatus), reinstatedAt: nullableText(value.reinstatedAt), reinstatedBy: nullableText(value.reinstatedBy), reinstatedByName: nullableText(value.reinstatedByName), reinstatementNote: nullableText(value.reinstatementNote),
    version: Number(value.version ?? 1),
  } as VersionedSession
}

export const openPlaySnapshotToState = (snapshot: SharedOpenPlaySnapshot): AppState => {
  const baseline = defaults()
  const settings = { ...baseline.settings, ...object(snapshot.settings) } as AppState['settings']
  const current = nightFrom(snapshot.currentNight)
  const previous = nightFrom(snapshot.previousNight)
  const nights = Object.fromEntries([current, previous].filter((night): night is Night => Boolean(night)).map(night => [night.id, night]))
  const sessions = Object.fromEntries(array(snapshot.sessions).map(sessionFrom).filter((session): session is VersionedSession => session !== null).map(session => [session.id, session]))
  const laneAssignments = Object.fromEntries(array(snapshot.laneAssignments).map(row => {
    const assignment: LaneAssignment = { id: text(row.id), sessionId: text(row.sessionId), laneNumber: Number(row.laneNumber), startedAt: text(row.startedAt), billingStartedAt: text(row.billingStartedAt), billingGroupId: text(row.billingGroupId), billableStartedAt: nullableText(row.billableStartedAt), endedAt: nullableText(row.endedAt), endReason: row.endReason as LaneAssignment['endReason'], downOverrideConfirmed: Boolean(row.downOverrideConfirmed) }
    return [assignment.id, assignment]
  }))
  const laneConditions = Object.fromEntries(array(snapshot.laneConditions).map(row => {
    const condition: LaneCondition = { laneNumber: Number(row.laneNumber), condition: row.condition as LaneCondition['condition'], note: nullableText(row.note), updatedAt: text(row.updatedAt) }
    return [String(condition.laneNumber), condition]
  }))
  const leagues = Object.fromEntries(array(snapshot.leagues).map(row => {
    const active = Boolean(row.active)
    const league: League = { id: text(row.id), name: text(row.name), active, sortOrder: Number(row.sortOrder), deleted: !active }
    return [league.id, league]
  }))
  const activity: ActivityEvent[] = array(snapshot.activity).map(row => ({ id: text(row.id), nightId: nullableText(row.nightId), occurredAt: text(row.occurredAt), type: text(row.type), sessionId: nullableText(row.sessionId), laneNumbers: Array.isArray(row.laneNumbers) ? row.laneNumbers.map(Number) : [], summary: text(row.summary), employeeId: nullableText(row.employeeId), employeeName: nullableText(row.employeeName), deviceId: nullableText(row.deviceId), details: object(row.details) }))
  const bookings = Object.fromEntries(array(snapshot.bookings).map(row => { const booking={...row,id:text(row.id),scheduledAt:text(row.scheduledAt),leagueId:nullableText(row.leagueId),leagueNameSnapshot:nullableText(row.leagueNameSnapshot),teamDescription:nullableText(row.teamDescription),partyName:nullableText(row.partyName),partyAmountCents:row.partyAmountCents==null?null:Number(row.partyAmountCents),customerName:nullableText(row.customerName),expectedBowlers:row.expectedBowlers==null?null:Number(row.expectedBowlers),lanesNeeded:Number(row.lanesNeeded),notes:nullableText(row.notes),version:Number(row.version),startedAt:nullableText(row.startedAt),startedBy:nullableText(row.startedBy),startedByName:nullableText(row.startedByName),cancelledAt:nullableText(row.cancelledAt),cancelledBy:nullableText(row.cancelledBy),cancelledByName:nullableText(row.cancelledByName),cancellationNote:nullableText(row.cancellationNote),resultingSessionId:nullableText(row.resultingSessionId)} as Booking; return [booking.id,booking] }))
  return { ...baseline, settings, currentNightId: current?.id ?? null, nights, sessions, laneAssignments, leagues, laneConditions, activity, bookings }
}

export const readSharedOpenPlayCache = (storage: Pick<Storage, 'getItem'> = localStorage): AppState | null => {
  try { const value = storage.getItem(SHARED_OPEN_PLAY_CACHE_KEY); return value ? openPlaySnapshotToState(JSON.parse(value) as SharedOpenPlaySnapshot) : null } catch { return null }
}

export const writeSharedOpenPlayCache = (snapshot: SharedOpenPlaySnapshot, storage: Pick<Storage, 'setItem'> = localStorage) =>
  storage.setItem(SHARED_OPEN_PLAY_CACHE_KEY, JSON.stringify(snapshot))
