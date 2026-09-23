import { describe,expect,it } from 'vitest'
import migration from '../supabase/migrations/202609220005_scheduled_bowling.sql?raw'
import verifier from '../supabase/verify-production-readiness.sql?raw'
import main from './main.tsx?raw'
import { bookingDraft,scheduledBookings,todayBookings } from './bookings'
import type { Booking } from './domain'

const booking=(id:string,scheduledAt:string,status:Booking['status']='SCHEDULED'):Booking=>({id,type:'PRE_POST',status,scheduledAt,leagueId:'league',leagueNameSnapshot:'Thursday Match Point',designation:'PRE',teamDescription:'Smith Team',lanesNeeded:2,notes:null,createdAt:scheduledAt,createdBy:'employee',createdByName:'Employee',updatedAt:scheduledAt,updatedBy:'employee',updatedByName:'Employee',version:1,startedAt:null,startedBy:null,startedByName:null,cancelledAt:null,cancelledBy:null,cancelledByName:null,cancellationNote:null,resultingSessionId:null})

describe('scheduled bowling domain',()=>{
  it('orders upcoming chronologically and excludes cancelled/started bookings',()=>{const rows=scheduledBookings({b:booking('b','2026-09-24T16:00:00Z'),a:booking('a','2026-09-23T16:00:00Z'),c:booking('c','2026-09-22T16:00:00Z','CANCELLED')});expect(rows.map(row=>row.id)).toEqual(['a','b'])})
  it('identifies today using the counter device local date',()=>{const now=new Date(2026,8,23,9);const same=new Date(2026,8,23,18).toISOString();const next=new Date(2026,8,24,9).toISOString();expect(todayBookings({same:booking('same',same),next:booking('next',next)},now).map(row=>row.id)).toEqual(['same'])})
  it('normalizes editor input without physical lanes',()=>{const draft=bookingDraft('2026-09-26T11:00','league','POST','  Jones  ',2,'  call desk  ');expect(draft).toMatchObject({leagueId:'league',designation:'POST',teamDescription:'Jones',lanesNeeded:2,notes:'call desk'});expect(draft).not.toHaveProperty('lanes')})
})

describe('scheduled bowling migration',()=>{
  it('adds future booking and immutable audit models without a business-night foreign key',()=>{expect(migration).toContain('create table public.open_play_bookings');expect(migration).toContain('create table public.open_play_booking_activity');const table=migration.slice(migration.indexOf('create table public.open_play_bookings'),migration.indexOf('create index open_play_bookings_upcoming'));expect(table).not.toContain('night_id');expect(table).toContain("status public.bsb_booking_status");expect(table).toContain('lanes_needed integer');expect(table).not.toContain('lane_number')})
  it('supports only PRE_POST and the small three-state lifecycle',()=>{expect(migration).toContain("bsb_booking_type as enum ('PRE_POST')");expect(migration).toContain("bsb_booking_status as enum ('SCHEDULED','CANCELLED','STARTED')")})
  it('uses validated actor attribution and never accepts browser employee identity',()=>{expect(migration.match(/bsb_open_play_require_actor\(p_session_token,p_device_token\)/g)?.length).toBeGreaterThanOrEqual(5);expect(migration).not.toMatch(/p_(employee_id|employee_name|organization_id|device_id)/);expect(migration).toContain('performed_by_name');expect(migration).toContain('device_id')})
  it('uses optimistic versions and row locks for edit, cancel, and start',()=>{expect(migration.match(/for update;/g)?.length).toBeGreaterThanOrEqual(4);expect(migration.match(/b\.version<>p_expected_version/g)).toHaveLength(3);expect(migration).toContain("raise exception 'Stale booking'")})
  it('rejects lifecycle-invalid mutations',()=>{expect(migration).toContain("Only scheduled bookings can be edited");expect(migration).toContain("Only scheduled bookings can be cancelled");expect(migration).toContain("This booking has already been started");expect(migration).toContain("A cancelled booking cannot be started")})
  it('atomically starts exactly one existing Pre/Post session on the current open night',()=>{const start=migration.slice(migration.indexOf('function public.bsb_start_booking'),migration.indexOf('function public.bsb_get_open_play_state'));expect(start).toContain("status='OPEN' for update");expect(start).toContain("raise exception 'There is no open night'");expect(start.match(/insert into public\.open_play_sessions/g)).toHaveLength(1);expect(start).toContain("values(v.organization_id,n.id,'PRE_POST'");expect(start).toContain('resulting_session_id=s.id');expect(start).toContain("status='STARTED'")})
  it('assigns physical lanes only inside Start and requires the requested count',()=>{const beforeStart=migration.slice(0,migration.indexOf('function public.bsb_start_booking'));expect(beforeStart).not.toContain('open_play_lane_assignments');const start=migration.slice(migration.indexOf('function public.bsb_start_booking'));expect(start).toContain('array_length(p_lanes,1),0)<>b.lanes_needed');expect(start).toContain('insert into public.open_play_lane_assignments')})
  it('audits all four booking events and retains cancelled history outside normal upcoming',()=>{for(const event of ['BOOKING_CREATED','BOOKING_UPDATED','BOOKING_CANCELLED','BOOKING_STARTED'])expect(migration).toContain(`'${event}'`);expect(migration).toContain("status='SCHEDULED' or scheduled_at>=now()-interval '90 days'");expect(migration).toContain("where status='SCHEDULED'")})
  it('does not alter the closed-night barrier or attach future bookings to archived nights',()=>{expect(migration).not.toContain('drop trigger bsb_open_play_sessions_open_night_barrier');expect(migration).not.toContain('update public.business_nights');expect(migration).not.toContain('delete from')})
})

describe('scheduled bowling UI wiring',()=>{
  it('reuses StartSheet for booked arrivals and sends the booking RPC',()=>{expect(main).toContain('<StartSheet state={state} booking={state.bookings[sheet.startBooking]}');expect(main).toContain('openPlayApi.startBooking');expect(main).toContain('Choose exactly {booking.lanesNeeded}')})
  it('exposes compact Schedule and Upcoming actions with edit/cancel',()=>{for(const text of ['Schedule','Upcoming (','ADD BOOKING','SAVE BOOKING','CANCEL BOOKING'])expect(main).toContain(text)})
})

describe('scheduled bowling production verifier',()=>{
  it('checks schema, grants, enums, indexes, constraints, and cross-table integrity read-only',()=>{for(const value of ['open_play_bookings','open_play_booking_activity','bsb_create_booking','bsb_update_booking','bsb_cancel_booking','bsb_start_booking','bsb_booking_log','bsb_booking_type','bsb_booking_status','open_play_bookings_upcoming','started bookings have a resulting session','unstarted bookings have no resulting session','booking/session organization matches'])expect(verifier).toContain(value);expect(verifier).not.toMatch(/(?:^|\n)\s*(insert|update|delete|alter|create|drop|truncate)\b/im)})
})
