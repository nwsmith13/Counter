import { describe, expect, it } from 'vitest'
import { sessionData } from './open-play-api'
import { openPlaySnapshotToState, readSharedOpenPlayCache, SHARED_OPEN_PLAY_CACHE_KEY, writeSharedOpenPlayCache } from './open-play-shared'
import { startSession } from './store'
import { currentNight, sessionOperationalMilestoneAt, sortSessionsByMilestoneNewestFirst } from './domain'

const snapshot = {
  settings: { timezone: 'America/Chicago', laneCount: 12, openBowlingLaneRateCents: 2500, shoeRentalRateCents: 300, openBowlingGracePeriodMinutes: 5, openBowlingMinimumChargeCents: 500, openBowlingTaxRate: 0.08725, showFactsAndJokes: true, soundEffectsEnabled: false },
  leagues: [{ id: 'league-1', name: 'Tuesday', active: true, sortOrder: 0 }],
  laneConditions: Array.from({ length: 12 }, (_, index) => ({ laneNumber: index + 1, condition: 'AVAILABLE', note: null, updatedAt: '2026-09-21T00:00:00Z' })),
  currentNight: { id: 'night-1', businessDate: '2026-09-21', openedAt: '2026-09-21T18:00:00Z', closedAt: null, status: 'OPEN' },
  previousNight: null,
  sessions: [{ id: 'session-1', nightId: 'night-1', type: 'OPEN_BOWLING', status: 'ACTIVE', startedAt: '2026-09-21T18:00:00Z', endedAt: null, createdAt: '2026-09-21T18:00:00Z', updatedAt: '2026-09-21T18:00:00Z', version: 3, data: { partyName: 'Smith', bowlerCount: 2, shoeCount: 1, notes: null, pricing: { laneRateCentsPerHour: 2500, shoeRateCents: 300, gracePeriodMinutes: 5, minimumChargeCents: 500, taxRate: 0.08725, calculatedTotalCents: null, roundedTotalCents: null, chargedTotalCents: null, adjustmentNote: null } } }],
  laneAssignments: [{ id: 'assignment-1', sessionId: 'session-1', laneNumber: 7, startedAt: '2026-09-21T18:00:00Z', billingStartedAt: '2026-09-21T18:00:00Z', billingGroupId: 'assignment-1', billableStartedAt: null, endedAt: null, endReason: null, downOverrideConfirmed: false }],
  activity: [
    { id: 'activity-1', nightId: 'night-1', occurredAt: '2026-09-21T18:02:00Z', type: 'SESSION_STARTED', sessionId: 'session-1', laneNumbers: [7], summary: 'Started Open Bowling', employeeId: 'employee-1', employeeName: 'Matthew Smith', deviceId: 'device-1', details: { sessionType: 'OPEN_BOWLING' } },
    { id: 'legacy-activity', nightId: 'night-1', occurredAt: '2026-09-21T18:01:00Z', type: 'LEGACY', sessionId: null, laneNumbers: [], summary: 'Legacy activity' },
  ],
}

describe('shared Open Play snapshot adapter', () => {
  it('maps a shared snapshot into the existing AppState shape', () => {
    const state = openPlaySnapshotToState(snapshot)
    expect(state.currentNightId).toBe('night-1')
    expect(currentNight(state)).toMatchObject({ id: 'night-1', status: 'OPEN' })
    expect(state.sessions['session-1'].type).toBe('OPEN_BOWLING')
    expect(state.laneAssignments['assignment-1'].laneNumber).toBe(7)
    expect(Object.keys(state.laneConditions)).toHaveLength(12)
    expect((state.sessions['session-1'] as { version?: number }).version).toBe(3)
  })

  it('preserves an open night across repeated authoritative hydration', () => {
    const first = openPlaySnapshotToState(snapshot)
    const refreshed = openPlaySnapshotToState(snapshot)
    expect(currentNight(first)?.id).toBe('night-1')
    expect(currentNight(refreshed)?.id).toBe('night-1')
    expect(first.currentNightId).not.toBeNull()
  })

  it('maps authoritative attribution and keeps legacy activity readable', () => {
    const state = openPlaySnapshotToState(snapshot)
    expect(state.activity[0]).toMatchObject({ employeeId: 'employee-1', employeeName: 'Matthew Smith', deviceId: 'device-1', details: { sessionType: 'OPEN_BOWLING' } })
    expect(state.activity[1]).toMatchObject({ summary: 'Legacy activity', employeeName: null })
  })

  it('retains stored name snapshots across hydration regardless of employee lifecycle changes', () => {
    const renamedElsewhere = { ...snapshot, employees: [{ id: 'employee-1', displayName: 'Renamed', active: false }] }
    expect(openPlaySnapshotToState(renamedElsewhere).activity[0].employeeName).toBe('Matthew Smith')
  })

  it('hydrates and caches authoritative void metadata for other terminals', () => {
    const voidedSnapshot={...snapshot,sessions:[{...snapshot.sessions[0],status:'VOIDED',version:4,voidedAt:'2026-09-21T19:00:00Z',voidedBy:'employee-1',voidedByName:'Matthew Smith',voidCategory:'TRAINING_TEST',voidNote:'George learning lane moves',preVoidStatus:'COMPLETED'}]}
    const state=openPlaySnapshotToState(voidedSnapshot)
    expect(state.sessions['session-1']).toMatchObject({status:'VOIDED',voidedByName:'Matthew Smith',voidCategory:'TRAINING_TEST',voidNote:'George learning lane moves',preVoidStatus:'COMPLETED'})
    const values=new Map<string,string>();const storage={getItem:(key:string)=>values.get(key)??null,setItem:(key:string,value:string)=>values.set(key,value)}
    writeSharedOpenPlayCache(voidedSnapshot,storage)
    expect(readSharedOpenPlayCache(storage)?.sessions['session-1'].status).toBe('VOIDED')
  })

  it('hydrates persisted lifecycle timestamps used for session history ordering', () => {
    const completed={...snapshot.sessions[0],status:'COMPLETED',endedAt:'2026-09-21T18:30:00Z',checkedOutAt:'2026-09-21T18:47:00Z',reopenedAt:'2026-09-21T18:40:00Z'}
    const state=openPlaySnapshotToState({...snapshot,sessions:[completed]})
    expect(state.sessions['session-1']).toMatchObject({checkedOutAt:'2026-09-21T18:47:00Z',reopenedAt:'2026-09-21T18:40:00Z'})
    expect(sessionOperationalMilestoneAt(state.sessions['session-1'])).toBe('2026-09-21T18:47:00Z')
  })

  it('uses the current-state milestone and sorts regular and voided session history newest first', () => {
    const base=openPlaySnapshotToState(snapshot).sessions['session-1']
    const active={...base,id:'active',status:'ACTIVE' as const,startedAt:'2026-09-21T18:00:00Z',reopenedAt:'2026-09-21T18:50:00Z'}
    const awaiting={...base,id:'awaiting',status:'AWAITING_CLOSE' as const,endedAt:'2026-09-21T18:55:00Z'}
    const paid={...base,id:'paid',status:'COMPLETED' as const,endedAt:'2026-09-21T18:30:00Z',checkedOutAt:'2026-09-21T19:00:00Z'}
    const voided={...base,id:'voided',status:'VOIDED' as const,voidedAt:'2026-09-21T19:05:00Z'}
    expect(sortSessionsByMilestoneNewestFirst([active,awaiting,paid,voided]).map(session=>session.id)).toEqual(['voided','paid','awaiting','active'])
    expect(sessionOperationalMilestoneAt(awaiting)).toBe('2026-09-21T18:55:00Z')
    expect(sessionOperationalMilestoneAt(active)).toBe('2026-09-21T18:50:00Z')
  })

  it('keeps database metadata out of the pricing payload sent by existing domain actions', () => {
    const state = openPlaySnapshotToState(snapshot)
    const data = sessionData(state.sessions['session-1'])
    expect(data).toMatchObject({ partyName: 'Smith', pricing: { minimumChargeCents: 500 } })
    expect(data).not.toHaveProperty('id')
    expect(data).not.toHaveProperty('version')
    expect(sessionData({...state.sessions['session-1'],voidedAt:'2026-09-21T19:00:00Z',voidedByName:'Matthew Smith',voidNote:'test reason'})).not.toHaveProperty('voidedAt')
  })

  it('uses only the dedicated shared cache key', () => {
    const values = new Map<string, string>()
    const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => values.set(key, value) }
    writeSharedOpenPlayCache(snapshot, storage)
    expect(values.has(SHARED_OPEN_PLAY_CACHE_KEY)).toBe(true)
    expect(values.has('bsb-counter:v1')).toBe(false)
    expect(readSharedOpenPlayCache(storage)?.currentNightId).toBe('night-1')
    expect(readSharedOpenPlayCache(storage)?.activity[0].employeeName).toBe('Matthew Smith')
  })

  it('round-trips the migration-seeded settings into a valid Open Bowling pricing payload', () => {
    const state = openPlaySnapshotToState(snapshot)
    const started = startSession(state, { type: 'OPEN_BOWLING', lanes: [8], partyName: 'Test', bowlerCount: 1, shoeCount: 0 }, '2026-09-21T18:01:00Z')
    const session = Object.values(started.sessions).find(value => value.id !== 'session-1')!
    const pricing = sessionData(session).pricing as Record<string, unknown>
    expect(pricing).toMatchObject({ laneRateCentsPerHour: 2500, shoeRateCents: 300, gracePeriodMinutes: 5, minimumChargeCents: 500, taxRate: 0.08725 })
    for (const key of ['laneRateCentsPerHour', 'shoeRateCents', 'minimumChargeCents']) expect(pricing[key]).toSatisfy(value => Number.isInteger(value) && Number(value) >= 0)
  })
})
