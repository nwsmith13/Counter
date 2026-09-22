export type SharedConnectionState = 'CONNECTED' | 'RECONNECTING' | 'OFFLINE'

export const OFFLINE_FAILURE_THRESHOLD = 3
export const OFFLINE_MUTATION_MESSAGE = 'Connection unavailable. Changes are paused until Open Play Book reconnects.'

let currentSharedConnectionState: SharedConnectionState = 'CONNECTED'
export const publishSharedConnectionState = (state: SharedConnectionState) => { currentSharedConnectionState = state }
export const assertConnectedBackendMutationAllowed = () => {
  if (currentSharedConnectionState === 'OFFLINE') throw new Error(OFFLINE_MUTATION_MESSAGE)
}

export class SharedConnectionTracker {
  private failures = 0
  private connectionState: SharedConnectionState

  constructor(initialState: SharedConnectionState = 'RECONNECTING', private readonly threshold = OFFLINE_FAILURE_THRESHOLD) {
    this.connectionState = initialState
  }

  get state() { return this.connectionState }
  get consecutiveFailures() { return this.failures }

  succeeded() {
    this.failures = 0
    this.connectionState = 'CONNECTED'
    return this.connectionState
  }

  failed() {
    this.failures += 1
    this.connectionState = this.failures >= this.threshold ? 'OFFLINE' : 'RECONNECTING'
    return this.connectionState
  }
}

export const isIdentityFailure = (error: unknown) => {
  const message = error instanceof Error ? error.message : String(error)
  return /unauthorized (terminal session|device)|session (expired|revoked)|device (deactivated|revoked)|authorization revoked/i.test(message)
}

export const isConnectivityFailure = (error: unknown) => {
  const message = error instanceof Error ? error.message : String(error)
  return error instanceof TypeError || /failed to fetch|networkerror|network request|load failed|fetch failed|connection (refused|closed)|timeout|timed out/i.test(message)
}

export const assertSharedMutationAllowed = (shared: boolean, state: SharedConnectionState, hasAuthoritativeState: boolean) => {
  if (!shared) return
  if (state === 'OFFLINE') throw new Error(OFFLINE_MUTATION_MESSAGE)
  if (!hasAuthoritativeState) throw new Error('Shared Open Play is reconnecting. Changes will be available after the board refreshes.')
}

export const canDisplaySharedBoard = (hasAuthoritativeState: boolean, hasCachedState: boolean) => hasAuthoritativeState || hasCachedState
