import { describe, expect, it } from 'vitest'
import migration from '../supabase/migrations/202609210002_open_play_shared_foundation.sql?raw'
import nightFix from '../supabase/migrations/202609210004_open_play_business_night_same_day_fix.sql?raw'
import auditMigration from '../supabase/migrations/202609210006_open_play_authoritative_audit.sql?raw'
import voidMigration from '../supabase/migrations/202609210007_open_play_payment_and_void.sql?raw'
import milestoneSnapshotMigration from '../supabase/migrations/202609210008_open_play_session_milestone_snapshot.sql?raw'

describe('shared Open Play migration foundation', () => {
  it('creates the reduced operational tables with direct browser access restricted', () => {
    for (const table of ['business_nights', 'open_play_sessions', 'open_play_lane_assignments', 'open_play_lane_conditions', 'open_play_settings', 'open_play_leagues', 'open_play_activity']) {
      expect(migration).toContain(`public.${table}`)
    }
    expect(migration).toContain('revoke all on public.business_nights')
    expect(migration).toContain('alter table public.open_play_sessions enable row level security;')
  })

  it('database-enforces one active assignment per organization lane', () => {
    expect(migration).toContain('open_play_one_active_assignment_per_lane')
    expect(migration).toContain('on public.open_play_lane_assignments(organization_id, lane_number) where ended_at is null')
  })

  it('allows a new night after a same-date night has closed while retaining one OPEN night', () => {
    expect(migration).toContain('business_nights_one_open_per_organization')
    expect(migration).toContain('create index if not exists business_nights_by_organization_date')
    expect(migration).not.toContain('create unique index if not exists business_nights_one_date_per_organization')
    expect(nightFix).toContain('drop index if exists public.business_nights_one_date_per_organization;')
  })

  it('uses a device-bound active terminal identity for every operational RPC', () => {
    expect(migration).toContain('create or replace function public.bsb_open_play_actor')
    expect(migration).toContain('s.revoked_at is null and s.expires_at > now() and e.active and d.active')
    expect(migration).toContain('and e.organization_id=d.organization_id')
    expect(migration).toContain('public.bsb_open_play_require_actor(p_session_token,p_device_token)')
  })

  it('includes state reads, lifecycle commands, transaction locks, and version checks', () => {
    for (const rpc of ['bsb_get_open_play_state', 'bsb_open_night', 'bsb_start_session', 'bsb_edit_session', 'bsb_add_lane', 'bsb_move_lane', 'bsb_release_lane', 'bsb_start_billing_now', 'bsb_end_session', 'bsb_checkout_session', 'bsb_reopen_session', 'bsb_set_lane_condition', 'bsb_close_night', 'bsb_save_open_play_settings']) {
      expect(migration).toContain(`public.${rpc}`)
    }
    expect(migration).toContain('for update')
    expect(migration).toContain("if s.version<>p_expected_version then raise exception 'Stale session'; end if;")
    expect(migration).toContain("s.status<>'AWAITING_CLOSE'")
  })

  it('seeds only the known BSB defaults and never reads the legacy local store', () => {
    expect(migration).toContain("where slug='blue-springs-bowl'")
    expect(migration).toContain('generate_series(1,12)')
    expect(migration).toContain("'openBowlingLaneRateCents',2500")
    expect(migration).toContain("'Friday Late',5")
    expect(migration).not.toContain('localStorage.getItem')
  })

  it('keeps security-definer paths narrowly scoped and pgcrypto qualified', () => {
    expect(migration).toContain('set search_path = public, pg_temp')
    expect(migration).not.toContain('set search_path = public, extensions')
    expect(migration).toContain('extensions.digest(p_session_token')
    expect(migration).toContain('extensions.digest(p_device_token')
  })
})

describe('payment and authoritative void migration', () => {
  it('adds reversible void metadata without deleting session history', () => {
    for (const field of ['voided_at','voided_by','voided_by_name','void_category','void_note','pre_void_status','reinstated_at','reinstated_by','reinstated_by_name','reinstatement_note']) expect(voidMigration).toContain(field)
    expect(voidMigration).not.toMatch(/delete\s+from\s+public\.open_play_(sessions|activity|lane_assignments)/i)
  })

  it('allows owners and managers but rejects employees server-side', () => {
    for (const rpc of ['bsb_void_session','bsb_reinstate_session']) expect(voidMigration).toContain(`function public.${rpc}`)
    expect(voidMigration.match(/if v\.employee_role='EMPLOYEE' then raise exception 'Manager access required'/g)).toHaveLength(2)
  })

  it('derives the actor and rejects invalid reasons before mutating', () => {
    expect(voidMigration).not.toMatch(/p_(employee_id|employee_name|organization_id|device_id|role)/)
    expect(voidMigration.match(/bsb_open_play_require_actor\(p_session_token,p_device_token\)/g)?.length).toBeGreaterThanOrEqual(5)
    expect(voidMigration).toContain("p_category not in ('ENTERED_BY_MISTAKE','TRAINING_TEST','DUPLICATE','OTHER')")
    expect(voidMigration).toContain("char_length(btrim(coalesce(p_note,''))) not between 3 and 500")
  })

  it('enforces ended-session safety and writes one immutable event per transition', () => {
    const voidRpc=voidMigration.slice(voidMigration.indexOf('function public.bsb_void_session'),voidMigration.indexOf('function public.bsb_reinstate_session'))
    const reinstateRpc=voidMigration.slice(voidMigration.indexOf('function public.bsb_reinstate_session'),voidMigration.indexOf('grant execute'))
    expect(voidRpc).toContain("s.status not in ('AWAITING_CLOSE','COMPLETED')")
    expect(voidRpc).toContain('ended_at is null')
    expect(voidRpc.match(/'SESSION_VOIDED'/g)).toHaveLength(1)
    expect(reinstateRpc.match(/'SESSION_REINSTATED'/g)).toHaveLength(1)
    expect(reinstateRpc).toContain('status=s.pre_void_status')
  })

  it('stores self-contained payment and Pre/Post completion context', () => {
    for(const value of ["'PAYMENT_COMPLETED'","'amountPaidCents'","'sessionTypeLabel'","'laneHistory'","'SESSION_COMPLETED'","'Ended Post-Bowl'","'Ended Pre-Bowl'"]) expect(voidMigration).toContain(value)
    expect(voidMigration).toContain("if s.type='PRE_POST'")
  })
})

describe('session milestone snapshot migration', () => {
  it('exposes persisted payment and correction milestones through the existing shared-state RPC', () => {
    expect(milestoneSnapshotMigration).toContain('create or replace function public.bsb_get_open_play_state')
    expect(milestoneSnapshotMigration).toContain("'checkedOutAt',checked_out_at")
    expect(milestoneSnapshotMigration).toContain("'reopenedAt',reopened_at")
    expect(milestoneSnapshotMigration).toContain('bsb_open_play_require_actor(p_session_token,p_device_token)')
  })
})

describe('authoritative Open Play audit migration', () => {
  it('derives audit identity from the validated actor context', () => {
    expect(auditMigration).toContain('v:=public.bsb_open_play_require_actor(p_session_token,p_device_token)')
    expect(auditMigration).toContain('p_actor.employee_id,v_name,p_actor.device_id')
    expect(auditMigration).not.toMatch(/performed_by_employee/i)
  })

  it('stores immutable attribution and exposes it in the shared snapshot', () => {
    for (const field of ['performed_by_name', 'device_id', 'details']) expect(auditMigration).toContain(field)
    for (const key of ["'employeeId',performed_by", "'employeeName',performed_by_name", "'deviceId',device_id", "'details',details"]) expect(auditMigration).toContain(key)
  })

  it('logs each successful meaningful RPC through the single activity helper', () => {
    const calls = auditMigration.match(/perform public\.bsb_open_play_log_actor/g) ?? []
    expect(calls.length).toBe(14)
    for (const action of ['NIGHT_OPENED','SESSION_STARTED','SESSION_EDITED','LANE_ADDED','LANE_MOVED','LANE_RELEASED','BILLING_STARTED','SESSION_ENDED','CHECKOUT_COMPLETED','SESSION_REOPENED','LANE_CONDITION_CHANGED','NIGHT_CLOSED','SETTINGS_CHANGED','LEAGUE_SETTINGS_CHANGED']) expect(auditMigration).toContain(`'${action}'`)
  })

  it('writes activity after validation so rejected mutations cannot create success records', () => {
    const checkout = auditMigration.slice(auditMigration.indexOf('function public.bsb_checkout_session'), auditMigration.indexOf('function public.bsb_reopen_session'))
    expect(checkout.indexOf("raise exception 'Charged total is required at checkout'")).toBeLessThan(checkout.indexOf('bsb_open_play_log_actor'))
    expect(checkout.indexOf("set status='COMPLETED'")).toBeLessThan(checkout.indexOf('bsb_open_play_log_actor'))
  })
})
