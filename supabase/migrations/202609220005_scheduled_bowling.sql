-- Scheduled Bowling V1: future Pre/Post intent, deliberately independent of business nights.

do $$ begin create type public.bsb_booking_type as enum ('PRE_POST'); exception when duplicate_object then null; end $$;
do $$ begin create type public.bsb_booking_status as enum ('SCHEDULED','CANCELLED','STARTED'); exception when duplicate_object then null; end $$;

create table public.open_play_bookings (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  type public.bsb_booking_type not null default 'PRE_POST',
  status public.bsb_booking_status not null default 'SCHEDULED',
  scheduled_at timestamptz not null,
  league_id uuid not null references public.open_play_leagues(id) on delete restrict,
  league_name_snapshot text not null check (char_length(btrim(league_name_snapshot)) between 1 and 120),
  designation text not null check (designation in ('PRE','POST')),
  team_description text not null check (char_length(btrim(team_description)) between 1 and 240),
  lanes_needed integer not null default 2 check (lanes_needed between 1 and 12),
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.employees(id) on delete restrict,
  created_by_name text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.employees(id) on delete restrict,
  updated_by_name text not null,
  version integer not null default 1 check (version > 0),
  started_at timestamptz,
  started_by uuid references public.employees(id) on delete restrict,
  started_by_name text,
  cancelled_at timestamptz,
  cancelled_by uuid references public.employees(id) on delete restrict,
  cancelled_by_name text,
  cancellation_note text,
  resulting_session_id uuid unique references public.open_play_sessions(id) on delete restrict,
  check ((status='SCHEDULED' and started_at is null and resulting_session_id is null and cancelled_at is null) or
         (status='STARTED' and started_at is not null and started_by is not null and resulting_session_id is not null and cancelled_at is null) or
         (status='CANCELLED' and cancelled_at is not null and cancelled_by is not null and cancellation_note is not null and started_at is null and resulting_session_id is null))
);
create index open_play_bookings_upcoming on public.open_play_bookings(organization_id,scheduled_at,id) where status='SCHEDULED';

create table public.open_play_booking_activity (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  booking_id uuid not null references public.open_play_bookings(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  type text not null check (type in ('BOOKING_CREATED','BOOKING_UPDATED','BOOKING_CANCELLED','BOOKING_STARTED')),
  performed_by uuid not null references public.employees(id) on delete restrict,
  performed_by_name text not null,
  device_id uuid not null references public.authorized_devices(id) on delete restrict,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details)='object')
);
create index open_play_booking_activity_recent on public.open_play_booking_activity(organization_id,booking_id,occurred_at desc);

alter table public.open_play_bookings enable row level security;
alter table public.open_play_booking_activity enable row level security;
revoke all on public.open_play_bookings,public.open_play_booking_activity from anon,authenticated;

create or replace function public.bsb_booking_log(p_actor public.bsb_open_play_actor_context,p_booking uuid,p_type text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_name text;
begin
  select display_name into v_name from public.employees where id=p_actor.employee_id and organization_id=p_actor.organization_id;
  insert into public.open_play_booking_activity(organization_id,booking_id,type,performed_by,performed_by_name,device_id,details)
  values(p_actor.organization_id,p_booking,p_type,p_actor.employee_id,v_name,p_actor.device_id,coalesce(p_details,'{}'::jsonb));
end $$;
revoke all on function public.bsb_booking_log(public.bsb_open_play_actor_context,uuid,text,jsonb) from public,anon,authenticated;

create or replace function public.bsb_create_booking(p_session_token text,p_device_token text,p_scheduled_at timestamptz,p_league_id uuid,p_designation text,p_team_description text,p_lanes_needed integer,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; l public.open_play_leagues; b public.open_play_bookings; v_name text;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  if p_scheduled_at is null then raise exception 'Date and time are required'; end if;
  if p_designation not in ('PRE','POST') then raise exception 'Choose Pre-Bowl or Post-Bowl'; end if;
  if char_length(btrim(coalesce(p_team_description,''))) not between 1 and 240 then raise exception 'Team / Bowler is required'; end if;
  if p_lanes_needed not between 1 and 12 then raise exception 'Lanes needed must be between 1 and 12'; end if;
  select * into l from public.open_play_leagues where id=p_league_id and organization_id=v.organization_id and active;
  if l.id is null then raise exception 'Select an active league/night'; end if;
  select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  insert into public.open_play_bookings(organization_id,scheduled_at,league_id,league_name_snapshot,designation,team_description,lanes_needed,notes,created_by,created_by_name,updated_by,updated_by_name)
  values(v.organization_id,p_scheduled_at,l.id,l.name,p_designation,btrim(p_team_description),p_lanes_needed,nullif(btrim(coalesce(p_notes,'')),''),v.employee_id,v_name,v.employee_id,v_name) returning * into b;
  perform public.bsb_booking_log(v,b.id,'BOOKING_CREATED',jsonb_build_object('scheduledAt',b.scheduled_at,'lanesNeeded',b.lanes_needed));
  return jsonb_build_object('id',b.id,'version',b.version);
end $$;

create or replace function public.bsb_update_booking(p_session_token text,p_device_token text,p_booking_id uuid,p_expected_version integer,p_scheduled_at timestamptz,p_league_id uuid,p_designation text,p_team_description text,p_lanes_needed integer,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; b public.open_play_bookings; l public.open_play_leagues; v_name text;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select * into b from public.open_play_bookings where id=p_booking_id and organization_id=v.organization_id for update;
  if b.id is null then raise exception 'Booking not found'; end if;
  if b.status<>'SCHEDULED' then raise exception 'Only scheduled bookings can be edited'; end if;
  if b.version<>p_expected_version then raise exception 'Stale booking'; end if;
  if p_scheduled_at is null or p_designation not in ('PRE','POST') or char_length(btrim(coalesce(p_team_description,''))) not between 1 and 240 or p_lanes_needed not between 1 and 12 then raise exception 'Enter valid booking details'; end if;
  select * into l from public.open_play_leagues where id=p_league_id and organization_id=v.organization_id and active;
  if l.id is null then raise exception 'Select an active league/night'; end if;
  select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  update public.open_play_bookings set scheduled_at=p_scheduled_at,league_id=l.id,league_name_snapshot=l.name,designation=p_designation,team_description=btrim(p_team_description),lanes_needed=p_lanes_needed,notes=nullif(btrim(coalesce(p_notes,'')),''),updated_at=now(),updated_by=v.employee_id,updated_by_name=v_name,version=version+1 where id=b.id returning * into b;
  perform public.bsb_booking_log(v,b.id,'BOOKING_UPDATED',jsonb_build_object('version',b.version));
  return jsonb_build_object('id',b.id,'version',b.version);
end $$;

create or replace function public.bsb_cancel_booking(p_session_token text,p_device_token text,p_booking_id uuid,p_expected_version integer,p_note text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; b public.open_play_bookings; v_name text;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select * into b from public.open_play_bookings where id=p_booking_id and organization_id=v.organization_id for update;
  if b.id is null then raise exception 'Booking not found'; end if;
  if b.status<>'SCHEDULED' then raise exception 'Only scheduled bookings can be cancelled'; end if;
  if b.version<>p_expected_version then raise exception 'Stale booking'; end if;
  if char_length(btrim(coalesce(p_note,''))) not between 3 and 500 then raise exception 'Enter a short cancellation reason'; end if;
  select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  update public.open_play_bookings set status='CANCELLED',cancelled_at=now(),cancelled_by=v.employee_id,cancelled_by_name=v_name,cancellation_note=btrim(p_note),updated_at=now(),updated_by=v.employee_id,updated_by_name=v_name,version=version+1 where id=b.id returning * into b;
  perform public.bsb_booking_log(v,b.id,'BOOKING_CANCELLED',jsonb_build_object('reason',b.cancellation_note));
  return jsonb_build_object('id',b.id,'version',b.version);
end $$;

create or replace function public.bsb_start_booking(p_session_token text,p_device_token text,p_booking_id uuid,p_expected_version integer,p_lanes integer[],p_down_overrides integer[] default '{}')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; b public.open_play_bookings; n public.business_nights; s public.open_play_sessions; a uuid; lane integer; v_name text; v_data jsonb;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select * into b from public.open_play_bookings where id=p_booking_id and organization_id=v.organization_id for update;
  if b.id is null then raise exception 'Booking not found'; end if;
  if b.status='STARTED' then raise exception 'This booking has already been started'; end if;
  if b.status='CANCELLED' then raise exception 'A cancelled booking cannot be started'; end if;
  if b.version<>p_expected_version then raise exception 'Stale booking'; end if;
  if coalesce(array_length(p_lanes,1),0)<>b.lanes_needed or exists(select 1 from unnest(p_lanes) x where x not between 1 and 12) or (select count(*) from unnest(p_lanes))<>(select count(distinct x) from unnest(p_lanes) x) then raise exception 'Select exactly % distinct lane(s)',b.lanes_needed; end if;
  select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update;
  if n.id is null then raise exception 'There is no open night'; end if;
  v_data:=jsonb_build_object('leagueId',b.league_id,'leagueNameSnapshot',b.league_name_snapshot,'designation',b.designation,'teamDescription',b.team_description,'bowlerCount',0,'notes',b.notes);
  perform public.bsb_open_play_validate_data('PRE_POST',v_data);
  insert into public.open_play_sessions(organization_id,night_id,type,started_by,created_by,updated_by,data) values(v.organization_id,n.id,'PRE_POST',v.employee_id,v.employee_id,v.employee_id,v_data) returning * into s;
  foreach lane in array p_lanes loop a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,n.id,s.id,lane,v.employee_id,now(),a,lane=any(coalesce(p_down_overrides,'{}'))); end loop;
  select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  update public.open_play_bookings set status='STARTED',started_at=now(),started_by=v.employee_id,started_by_name=v_name,resulting_session_id=s.id,updated_at=now(),updated_by=v.employee_id,updated_by_name=v_name,version=version+1 where id=b.id returning * into b;
  perform public.bsb_open_play_log_actor(v,n.id,s.id,'SESSION_STARTED',p_lanes,'Started Pre/Post Bowl',jsonb_build_object('sessionType','PRE_POST','label',b.team_description,'bookingId',b.id));
  perform public.bsb_booking_log(v,b.id,'BOOKING_STARTED',jsonb_build_object('sessionId',s.id,'nightId',n.id,'lanes',to_jsonb(p_lanes)));
  return jsonb_build_object('id',b.id,'version',b.version,'sessionId',s.id);
exception when unique_violation then raise exception 'One or more selected lanes are already in use';
end $$;

create or replace function public.bsb_get_open_play_state(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer stable set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; v_open uuid; v_previous uuid; v_activity_night uuid;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select id into v_open from public.business_nights where organization_id=v.organization_id and status='OPEN';
  select id into v_previous from public.business_nights where organization_id=v.organization_id and status='CLOSED' order by closed_at desc limit 1;
  v_activity_night:=coalesce(v_open,v_previous);
  return jsonb_build_object(
    'settings',(select settings from public.open_play_settings where organization_id=v.organization_id),
    'leagues',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'sortOrder',sort_order) order by sort_order) from public.open_play_leagues where organization_id=v.organization_id),'[]'::jsonb),
    'laneConditions',coalesce((select jsonb_agg(jsonb_build_object('laneNumber',lane_number,'condition',condition,'note',note,'updatedAt',updated_at) order by lane_number) from public.open_play_lane_conditions where organization_id=v.organization_id),'[]'::jsonb),
    'currentNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status',case when status='CLOSED' then 'ARCHIVED' else 'OPEN' end) from public.business_nights where id=v_open),
    'previousNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status','ARCHIVED') from public.business_nights where id=v_previous),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'type',type,'status',status,'startedAt',started_at,'endedAt',ended_at,'checkedOutAt',checked_out_at,'reopenedAt',reopened_at,'createdAt',created_at,'updatedAt',updated_at,'data',data,'version',version,'voidedAt',voided_at,'voidedBy',voided_by,'voidedByName',voided_by_name,'voidCategory',void_category,'voidNote',void_note,'preVoidStatus',pre_void_status,'reinstatedAt',reinstated_at,'reinstatedBy',reinstated_by,'reinstatedByName',reinstated_by_name,'reinstatementNote',reinstatement_note)) from public.open_play_sessions where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'laneAssignments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'sessionId',session_id,'laneNumber',lane_number,'startedAt',started_at,'billingStartedAt',billing_started_at,'billingGroupId',billing_group_id,'billableStartedAt',billable_started_at,'endedAt',ended_at,'endReason',end_reason,'downOverrideConfirmed',down_override_confirmed)) from public.open_play_lane_assignments where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'activity',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'occurredAt',occurred_at,'type',type,'sessionId',session_id,'laneNumbers',lane_numbers,'summary',summary,'employeeId',performed_by,'employeeName',performed_by_name,'deviceId',device_id,'details',details) order by occurred_at desc) from (select * from public.open_play_activity where night_id=v_activity_night order by occurred_at desc limit 200) a),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object('id',id,'type',type,'status',status,'scheduledAt',scheduled_at,'leagueId',league_id,'leagueNameSnapshot',league_name_snapshot,'designation',designation,'teamDescription',team_description,'lanesNeeded',lanes_needed,'notes',notes,'createdAt',created_at,'createdBy',created_by,'createdByName',created_by_name,'updatedAt',updated_at,'updatedBy',updated_by,'updatedByName',updated_by_name,'version',version,'startedAt',started_at,'startedBy',started_by,'startedByName',started_by_name,'cancelledAt',cancelled_at,'cancelledBy',cancelled_by,'cancelledByName',cancelled_by_name,'cancellationNote',cancellation_note,'resultingSessionId',resulting_session_id) order by scheduled_at,id) from public.open_play_bookings where organization_id=v.organization_id and (status='SCHEDULED' or scheduled_at>=now()-interval '90 days')),'[]'::jsonb)
  );
end $$;

grant execute on function public.bsb_create_booking(text,text,timestamptz,uuid,text,text,integer,text) to anon;
grant execute on function public.bsb_update_booking(text,text,uuid,integer,timestamptz,uuid,text,text,integer,text) to anon;
grant execute on function public.bsb_cancel_booking(text,text,uuid,integer,text) to anon;
grant execute on function public.bsb_start_booking(text,text,uuid,integer,integer[],integer[]) to anon;
grant execute on function public.bsb_get_open_play_state(text,text) to anon;
