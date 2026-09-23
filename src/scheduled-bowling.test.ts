import { describe,expect,it } from 'vitest'
import migration from '../supabase/migrations/202609220005_scheduled_bowling.sql?raw'
import scheduleEnumMigration from '../supabase/migrations/202609230001_bowling_schedule.sql?raw'
import scheduleMigration from '../supabase/migrations/202609230002_bowling_schedule_contract.sql?raw'
import verifier from '../supabase/verify-production-readiness.sql?raw'
import main from './main.tsx?raw'
import { bookingDraft,bookingsForDate,monthGrid,scheduledBookings,scheduledDateKeys,todayBookings,todayReminder } from './bookings'
import type { Booking } from './domain'

const booking=(id:string,scheduledAt:string,status:Booking['status']='SCHEDULED',type:Booking['type']='PRE_POST'):Booking=>({id,type,status,scheduledAt,leagueId:type==='PRE_POST'?'league':null,leagueNameSnapshot:type==='PRE_POST'?'Thursday Match Point':null,designation:type==='PRE_POST'?'PRE':null,teamDescription:type==='PRE_POST'?'Smith Team':null,partyName:type==='PARTY'?'Smith Birthday':null,partyAmountCents:type==='PARTY'?12000:null,customerName:type==='OPEN_PLAY'?'Johnson':null,expectedBowlers:type==='OPEN_PLAY'?8:null,lanesNeeded:2,notes:null,createdAt:scheduledAt,createdBy:'employee',createdByName:'Employee',updatedAt:scheduledAt,updatedBy:'employee',updatedByName:'Employee',version:1,startedAt:null,startedBy:null,startedByName:null,cancelledAt:null,cancelledBy:null,cancelledByName:null,cancellationNote:null,resultingSessionId:null})

describe('scheduled bowling domain',()=>{
  it('orders upcoming chronologically and excludes cancelled/started bookings',()=>{const rows=scheduledBookings({b:booking('b','2026-09-24T16:00:00Z'),a:booking('a','2026-09-23T16:00:00Z'),c:booking('c','2026-09-22T16:00:00Z','CANCELLED')});expect(rows.map(row=>row.id)).toEqual(['a','b'])})
  it('identifies today using the counter device local date',()=>{const now=new Date(2026,8,23,9);const same=new Date(2026,8,23,18).toISOString();const next=new Date(2026,8,24,9).toISOString();expect(todayBookings({same:booking('same',same),next:booking('next',next)},now).map(row=>row.id)).toEqual(['same'])})
  it('normalizes editor input without physical lanes',()=>{const draft=bookingDraft('PRE_POST','2026-09-26T11:00',2,'  call desk  ',{leagueId:'league',designation:'POST',teamDescription:'Jones'});expect(draft).toMatchObject({leagueId:'league',designation:'POST',teamDescription:'Jones',lanesNeeded:2,notes:'call desk'});expect(draft).not.toHaveProperty('lanes')})
})

describe('bowling schedule calendar',()=>{
 it('renders a stable six-week month grid across month boundaries',()=>{const days=monthGrid(new Date(2026,8,1));expect(days).toHaveLength(42);expect(days[0].getDay()).toBe(0);expect(days[41].getDay()).toBe(6);expect(days.some(day=>day.getMonth()===7)).toBe(true);expect(days.some(day=>day.getMonth()===9)).toBe(true)})
 it('dots only dates with scheduled bookings',()=>{const date=new Date(2026,8,26,12);const rows={scheduled:booking('scheduled',new Date(2026,8,26,11).toISOString()),started:booking('started',new Date(2026,8,27,11).toISOString(),'STARTED'),cancelled:booking('cancelled',new Date(2026,8,28,11).toISOString(),'CANCELLED')};expect(scheduledDateKeys(rows)).toEqual(new Set(['2026-09-26']));expect(bookingsForDate(rows,date).map(x=>x.id)).toEqual(['scheduled']);expect(bookingsForDate(rows,new Date(2026,8,29))).toEqual([])})
 it('orders a selected date chronologically across all types',()=>{const day=(hour:number)=>new Date(2026,8,26,hour).toISOString();const rows={open:booking('open',day(18),'SCHEDULED','OPEN_PLAY'),pre:booking('pre',day(11)),party:booking('party',day(14),'SCHEDULED','PARTY')};expect(bookingsForDate(rows,new Date(2026,8,26)).map(x=>x.type)).toEqual(['PRE_POST','PARTY','OPEN_PLAY'])})
})

describe('expanded booking contract migration',()=>{
 it('commits enum labels in a dedicated migration before the contract references them',()=>{expect(scheduleEnumMigration).toContain("add value if not exists 'PARTY'");expect(scheduleEnumMigration).toContain("add value if not exists 'OPEN_PLAY'");expect(scheduleEnumMigration).not.toContain('open_play_bookings_type_details');expect(scheduleMigration).not.toContain('alter type public.bsb_booking_type add value')})
 it('extends one aggregate and keeps authoritative typed starts',()=>{expect(scheduleMigration).toContain('open_play_bookings_type_details');expect(scheduleMigration).toContain('for update');expect(scheduleMigration).toContain("if b.status='STARTED'");expect(scheduleMigration).toContain('cardinality(p_lanes)<>b.lanes_needed')})
 it('snapshots Party amount but reads current Open Play settings at start',()=>{expect(scheduleMigration).toContain("'partyAmountCents',b.party_amount_cents");expect(scheduleMigration).toContain('select settings into cfg');expect(scheduleMigration).toContain("cfg->>'openBowlingLaneRateCents'");expect(scheduleMigration).not.toContain('future_price')})
})

describe('Upcoming Today reminder',()=>{
  const at=(day:number,hour:number,minute=0)=>new Date(2026,8,day,hour,minute).toISOString()
  const now=new Date(2026,8,23,10,0)
  it('does not create a strip when no scheduled booking is today',()=>{expect(todayReminder({},now)).toBeNull();expect(todayReminder({tomorrow:booking('tomorrow',at(24,10))},now)).toBeNull();expect(todayReminder({yesterday:booking('yesterday',at(22,10))},now)).toBeNull()})
  it('selects today’s scheduled booking and omits cancelled and started records',()=>{const result=todayReminder({scheduled:booking('scheduled',at(23,13)),cancelled:booking('cancelled',at(23,11),'CANCELLED'),started:booking('started',at(23,9),'STARTED')},now);expect(result).toMatchObject({booking:{id:'scheduled'},additionalCount:0,urgency:'NORMAL'})})
  it('adds stronger emphasis within sixty minutes and waiting after its time',()=>{expect(todayReminder({soon:booking('soon',at(23,11))},now)?.urgency).toBe('SOON');expect(todayReminder({due:booking('due',at(23,10))},now)?.urgency).toBe('WAITING');expect(todayReminder({late:booking('late',at(23,9,59))},now)?.urgency).toBe('WAITING')})
  it('keeps multiple bookings compact by selecting the earliest and counting the rest',()=>{const result=todayReminder({later:booking('later',at(23,15)),first:booking('first',at(23,11)),middle:booking('middle',at(23,13))},now);expect(result).toMatchObject({booking:{id:'first'},additionalCount:2})})
  it('disappears after the authoritative state changes the final booking to STARTED',()=>{const rows={today:booking('today',at(23,11))};expect(todayReminder(rows,now)).not.toBeNull();expect(todayReminder({...rows,today:booking('today',at(23,11),'STARTED')},now)).toBeNull()})
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
  it('passes the selected calendar date into Add Booking and preserves it across type choices',()=>{expect(main).toContain("add={selectedDateKey=>setSheet({addBooking:selectedDateKey})}");expect(main).toContain('selectedDateKey={sheet.addBooking}');expect(main).toContain('bookingInitialDateTime(selectedDate)');expect(main).toContain("onClick={()=>setType(kind)}")})
  it('retains the non-calendar Add Booking fallback',()=>{expect(main).toContain("sheet==='ADD_BOOKING'&&<BookingEditor" )})
  it('reuses StartSheet for booked arrivals and sends the booking RPC',()=>{expect(main).toContain('<StartSheet state={state} booking={state.bookings[sheet.startBooking]}');expect(main).toContain('openPlayApi.startBooking');expect(main).toContain('Choose exactly {booking.lanesNeeded}')})
  it('exposes compact Schedule and Upcoming actions with edit/cancel',()=>{for(const text of ['Schedule','Upcoming (','ADD BOOKING','SAVE BOOKING','CANCEL BOOKING'])expect(main).toContain(text)})
  it('routes one reminder to booking detail and multiple reminders to the existing Upcoming sheet',()=>{expect(main).toContain("reminder.additionalCount?'UPCOMING':{booking:reminder.booking.id}");expect(main).toContain('function UpcomingTodayReminder');expect(main).toContain('UPCOMING TODAY')})
})

describe('scheduled bowling production verifier',()=>{
  it('checks schema, grants, enums, indexes, constraints, and cross-table integrity read-only',()=>{for(const value of ['open_play_bookings','open_play_booking_activity','bsb_create_booking','bsb_update_booking','bsb_cancel_booking','bsb_start_booking','bsb_booking_log','bsb_booking_type','bsb_booking_status','open_play_bookings_upcoming','started bookings have a resulting session','unstarted bookings have no resulting session','booking/session organization matches'])expect(verifier).toContain(value);expect(verifier).not.toMatch(/(?:^|\n)\s*(insert|update|delete|alter|create|drop|truncate)\b/im)})
})
