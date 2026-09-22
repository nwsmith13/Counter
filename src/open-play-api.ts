import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import type { LaneConditionKind, Session, SessionType, Settings } from './domain'
import { runtimeConfiguration } from './runtime-config'

const url = runtimeConfiguration.supabaseUrl
const anonKey = runtimeConfiguration.supabaseAnonKey
export const openPlayConfigured = runtimeConfiguration.shared && !runtimeConfiguration.error
const client: SupabaseClient | null = url && anonKey ? createClient(url, anonKey, { auth: { persistSession: false } }) : null

export type OpenPlayCredentials = { sessionToken: string; deviceToken: string }
const auth = (credentials: OpenPlayCredentials) => ({ p_session_token: credentials.sessionToken, p_device_token: credentials.deviceToken })

export type SharedOpenPlaySnapshot = Record<string, unknown>
export type VersionedSession = Session & { version?: number }
export const sessionData = (session: Session): Record<string, unknown> => {
  const data = { ...(session as VersionedSession) } as Record<string, unknown>
  for (const key of ['id', 'nightId', 'type', 'status', 'startedAt', 'endedAt', 'checkedOutAt', 'reopenedAt', 'createdAt', 'updatedAt', 'version', 'voidedAt', 'voidedBy', 'voidedByName', 'voidCategory', 'voidNote', 'preVoidStatus', 'reinstatedAt', 'reinstatedBy', 'reinstatedByName', 'reinstatementNote']) delete data[key]
  return data
}

const call = async <T>(name: string, args: Record<string, unknown>): Promise<T> => {
  if (!client) throw new Error('Shared Open Play is not configured on this terminal.')
  const { data, error } = await client.rpc(name, args)
  if (error) throw new Error(error.message)
  return data as T
}

export const openPlayApi = {
  getState: (c: OpenPlayCredentials) => call<SharedOpenPlaySnapshot>('bsb_get_open_play_state', auth(c)),
  openNight: (c: OpenPlayCredentials) => call('bsb_open_night', auth(c)),
  startSession: (c: OpenPlayCredentials, type: SessionType, data: Record<string, unknown>, lanes: number[], downOverrides: number[]) => call('bsb_start_session', { ...auth(c), p_type: type, p_data: data, p_lanes: lanes, p_down_overrides: downOverrides }),
  editSession: (c: OpenPlayCredentials, session: VersionedSession, data: Record<string, unknown>, startedAt?: string) => call('bsb_edit_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_data: data, p_started_at: startedAt ?? null }),
  addLane: (c: OpenPlayCredentials, sessionId: string, lane: number, downOverride: boolean) => call('bsb_add_lane', { ...auth(c), p_session_id: sessionId, p_lane: lane, p_down_override: downOverride }),
  moveLane: (c: OpenPlayCredentials, sessionId: string, fromLane: number, toLane: number, downOverride: boolean) => call('bsb_move_lane', { ...auth(c), p_session_id: sessionId, p_from_lane: fromLane, p_to_lane: toLane, p_down_override: downOverride }),
  releaseLane: (c: OpenPlayCredentials, sessionId: string, lane: number) => call('bsb_release_lane', { ...auth(c), p_session_id: sessionId, p_lane: lane }),
  startBillingNow: (c: OpenPlayCredentials, sessionId: string, lane?: number) => call('bsb_start_billing_now', { ...auth(c), p_session_id: sessionId, p_lane: lane ?? null }),
  endSession: (c: OpenPlayCredentials, session: VersionedSession, data: Record<string, unknown>) => call('bsb_end_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_data: data }),
  checkoutSession: (c: OpenPlayCredentials, session: VersionedSession, data: Record<string, unknown>) => call('bsb_checkout_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_data: data }),
  reopenSession: (c: OpenPlayCredentials, session: VersionedSession, data: Record<string, unknown>) => call('bsb_reopen_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_data: data }),
  voidSession: (c: OpenPlayCredentials, session: VersionedSession, category: string, note: string) => call('bsb_void_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_category: category, p_note: note }),
  reinstateSession: (c: OpenPlayCredentials, session: VersionedSession, note: string) => call('bsb_reinstate_session', { ...auth(c), p_session_id: session.id, p_expected_version: session.version ?? 1, p_note: note }),
  setLaneCondition: (c: OpenPlayCredentials, lane: number, condition: LaneConditionKind, note: string) => call('bsb_set_lane_condition', { ...auth(c), p_lane: lane, p_condition: condition, p_note: note }),
  closeNight: (c: OpenPlayCredentials) => call('bsb_close_night', auth(c)),
  saveSettings: (c: OpenPlayCredentials, settings: Settings) => call('bsb_save_open_play_settings', { ...auth(c), p_settings: settings }),
  saveLeague: (c: OpenPlayCredentials, league: { id?: string; name: string; active: boolean; sortOrder: number }) => call('bsb_save_open_play_league', { ...auth(c), p_league_id: league.id ?? null, p_name: league.name, p_active: league.active, p_sort_order: league.sortOrder }),
}
