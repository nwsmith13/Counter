import { describe, expect, it } from 'vitest'
import { assertConnectedBackendMutationAllowed, assertSharedMutationAllowed, canDisplaySharedBoard, CLOSED_NIGHT_MESSAGE, isClosedNightFailure, isConnectivityFailure, isIdentityFailure, OFFLINE_MUTATION_MESSAGE, publishSharedConnectionState, SharedConnectionTracker } from './connection-safety'

describe('shared connection safety', () => {
  it('becomes connected after a successful authoritative request', () => {
    const tracker = new SharedConnectionTracker()
    expect(tracker.succeeded()).toBe('CONNECTED')
  })

  it('uses reconnecting for transient failures and offline after three consecutive failures', () => {
    const tracker = new SharedConnectionTracker('CONNECTED')
    expect(tracker.failed()).toBe('RECONNECTING')
    expect(tracker.failed()).toBe('RECONNECTING')
    expect(tracker.failed()).toBe('OFFLINE')
    expect(tracker.consecutiveFailures).toBe(3)
  })

  it('recovers only after an authoritative success', () => {
    const tracker = new SharedConnectionTracker('CONNECTED')
    tracker.failed(); tracker.failed(); tracker.failed()
    expect(tracker.state).toBe('OFFLINE')
    expect(tracker.succeeded()).toBe('CONNECTED')
    expect(tracker.consecutiveFailures).toBe(0)
  })

  it('blocks shared mutations offline and before initial hydration but leaves local-only mode unchanged', () => {
    expect(() => assertSharedMutationAllowed(true, 'OFFLINE', true)).toThrow(OFFLINE_MUTATION_MESSAGE)
    expect(() => assertSharedMutationAllowed(true, 'RECONNECTING', false)).toThrow(/after the board refreshes/)
    expect(() => assertSharedMutationAllowed(false, 'OFFLINE', false)).not.toThrow()
  })

  it('applies the offline guard to Supabase-backed administration writes', () => {
    publishSharedConnectionState('OFFLINE')
    expect(() => assertConnectedBackendMutationAllowed()).toThrow(OFFLINE_MUTATION_MESSAGE)
    publishSharedConnectionState('CONNECTED')
    expect(() => assertConnectedBackendMutationAllowed()).not.toThrow()
  })

  it('never presents an invented empty board during fresh shared startup', () => {
    expect(canDisplaySharedBoard(false, false)).toBe(false)
    expect(canDisplaySharedBoard(false, true)).toBe(true)
    expect(canDisplaySharedBoard(true, false)).toBe(true)
  })

  it('does not misclassify identity failures as connectivity failures', () => {
    expect(isIdentityFailure(new Error('Unauthorized terminal session'))).toBe(true)
    expect(isIdentityFailure(new Error('Unauthorized device'))).toBe(true)
    expect(isIdentityFailure(new TypeError('Failed to fetch'))).toBe(false)
    expect(isConnectivityFailure(new TypeError('Failed to fetch'))).toBe(true)
    expect(isConnectivityFailure(new Error('Stale session'))).toBe(false)
  })

  it('classifies a closed-night rejection separately from connectivity failures', () => {
    const error = new Error(CLOSED_NIGHT_MESSAGE)
    expect(isClosedNightFailure(error)).toBe(true)
    expect(isConnectivityFailure(error)).toBe(false)
  })
})
