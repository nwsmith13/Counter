-- Shared Open Play foundation.  This migration deliberately does not read or
-- alter bsb-counter:v1; that remains the legacy local-only store.

do $$ begin
  create type public.bsb_open_play_night_status as enum ('OPEN', 'CLOSED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bsb_open_play_session_type as enum ('OPEN_BOWLING', 'PRE_POST', 'PARTY');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bsb_open_play_session_status as enum ('ACTIVE', 'AWAITING_CLOSE', 'COMPLETED', 'VOIDED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bsb_open_play_lane_condition as enum ('AVAILABLE', 'DOWN', 'WATCH');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bsb_open_play_lane_end_reason as enum ('RELEASED', 'MOVED', 'SESSION_ENDED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bsb_open_play_actor_context as (
    organization_id uuid, employee_id uuid, employee_role public.bsb_employee_role, device_id uuid
  );
exception when duplicate_object then null; end $$;

create table if not exists public.business_nights (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  business_date date not null,
  status public.bsb_open_play_night_status not null default 'OPEN',
  opened_at timestamptz not null default now(),
  opened_by uuid not null references public.employees(id) on delete restrict,
  closed_at timestamptz,
  closed_by uuid references public.employees(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'OPEN' and closed_at is null and closed_by is null) or
         (status = 'CLOSED' and closed_at is not null and closed_by is not null)),
  check (closed_at is null or closed_at >= opened_at)
);
create unique index if not exists business_nights_one_open_per_organization
  on public.business_nights(organization_id) where status = 'OPEN';
create index if not exists business_nights_by_organization_date
  on public.business_nights(organization_id, business_date);

create table if not exists public.open_play_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  settings jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.employees(id) on delete restrict,
  check (jsonb_typeof(settings) = 'object')
);

create table if not exists public.open_play_leagues (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  active boolean not null default true,
  sort_order integer not null check (sort_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.employees(id) on delete restrict,
  unique (organization_id, name)
);
create index if not exists open_play_leagues_current_order
  on public.open_play_leagues(organization_id, active, sort_order);

create table if not exists public.open_play_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  night_id uuid not null references public.business_nights(id) on delete restrict,
  type public.bsb_open_play_session_type not null,
  status public.bsb_open_play_session_status not null default 'ACTIVE',
  started_at timestamptz not null default now(),
  started_by uuid not null references public.employees(id) on delete restrict,
  ended_at timestamptz,
  ended_by uuid references public.employees(id) on delete restrict,
  checked_out_at timestamptz,
  checked_out_by uuid references public.employees(id) on delete restrict,
  reopened_at timestamptz,
  reopened_by uuid references public.employees(id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid not null references public.employees(id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references public.employees(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  data jsonb not null default '{}'::jsonb,
  check (jsonb_typeof(data) = 'object'),
  check (ended_at is null or ended_at >= started_at)
);
create index if not exists open_play_sessions_night_status
  on public.open_play_sessions(organization_id, night_id, status);

create table if not exists public.open_play_lane_assignments (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  night_id uuid not null references public.business_nights(id) on delete restrict,
  session_id uuid not null references public.open_play_sessions(id) on delete cascade,
  lane_number integer not null check (lane_number between 1 and 12),
  started_at timestamptz not null default now(),
  started_by uuid not null references public.employees(id) on delete restrict,
  billing_started_at timestamptz not null,
  billable_started_at timestamptz,
  billing_group_id uuid not null,
  ended_at timestamptz,
  ended_by uuid references public.employees(id) on delete restrict,
  end_reason public.bsb_open_play_lane_end_reason,
  down_override_confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at),
  check ((ended_at is null and end_reason is null and ended_by is null) or
         (ended_at is not null and end_reason is not null and ended_by is not null))
);
-- The final guard against two tablets owning the same physical lane.
create unique index if not exists open_play_one_active_assignment_per_lane
  on public.open_play_lane_assignments(organization_id, lane_number) where ended_at is null;
create index if not exists open_play_lane_assignments_session
  on public.open_play_lane_assignments(session_id, started_at);

create table if not exists public.open_play_lane_conditions (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lane_number integer not null check (lane_number between 1 and 12),
  condition public.bsb_open_play_lane_condition not null default 'AVAILABLE',
  note text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.employees(id) on delete restrict,
  primary key (organization_id, lane_number)
);

create table if not exists public.open_play_activity (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  night_id uuid not null references public.business_nights(id) on delete restrict,
  session_id uuid references public.open_play_sessions(id) on delete set null,
  occurred_at timestamptz not null default now(),
  type text not null check (char_length(type) between 1 and 80),
  lane_numbers integer[] not null default '{}',
  summary text not null check (char_length(summary) between 1 and 240),
  performed_by uuid not null references public.employees(id) on delete restrict
);
create index if not exists open_play_activity_night_recent
  on public.open_play_activity(organization_id, night_id, occurred_at desc);

alter table public.business_nights enable row level security;
alter table public.open_play_settings enable row level security;
alter table public.open_play_leagues enable row level security;
alter table public.open_play_sessions enable row level security;
alter table public.open_play_lane_assignments enable row level security;
alter table public.open_play_lane_conditions enable row level security;
alter table public.open_play_activity enable row level security;
revoke all on public.business_nights, public.open_play_settings, public.open_play_leagues,
  public.open_play_sessions, public.open_play_lane_assignments, public.open_play_lane_conditions,
  public.open_play_activity from anon, authenticated;

-- Validates an employee terminal session and its specific authorized device.
create or replace function public.bsb_open_play_actor(p_session_token text, p_device_token text)
returns public.bsb_open_play_actor_context
language sql security definer stable set search_path = public, pg_temp
as $$
  select row(e.organization_id, e.id, e.role, d.id)::public.bsb_open_play_actor_context
  from public.employee_terminal_sessions s
  join public.employees e on e.id=s.employee_id
  join public.authorized_devices d on d.id=s.device_id
  where s.token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex')
    and d.token_hash=encode(extensions.digest(p_device_token,'sha256'),'hex')
    and s.revoked_at is null and s.expires_at > now() and e.active and d.active
    and e.organization_id=d.organization_id
  limit 1
$$;
revoke all on function public.bsb_open_play_actor(text,text) from public, anon, authenticated;

create or replace function public.bsb_open_play_require_actor(p_session_token text, p_device_token text)
returns public.bsb_open_play_actor_context
language plpgsql security definer stable set search_path = public, pg_temp
as $$
declare v_actor public.bsb_open_play_actor_context;
begin
  select * into v_actor from public.bsb_open_play_actor(p_session_token,p_device_token);
  if v_actor.employee_id is null then raise exception 'Unauthorized terminal session'; end if;
  return v_actor;
end $$;
revoke all on function public.bsb_open_play_require_actor(text,text) from public, anon, authenticated;

create or replace function public.bsb_open_play_log(p_org uuid, p_night uuid, p_session uuid,
  p_type text, p_lanes integer[], p_summary text, p_employee uuid)
returns void language sql security definer set search_path = public, pg_temp
as $$ insert into public.open_play_activity(organization_id,night_id,session_id,type,lane_numbers,summary,performed_by)
  values(p_org,p_night,p_session,p_type,coalesce(p_lanes,'{}'),p_summary,p_employee) $$;
revoke all on function public.bsb_open_play_log(uuid,uuid,uuid,text,integer[],text,uuid) from public, anon, authenticated;

create or replace function public.bsb_open_play_assert_money(p_value jsonb, p_key text, p_nullable boolean default true)
returns void language plpgsql security definer immutable set search_path = public, pg_temp
as $$
begin
  if not (p_value ? p_key) or p_value->p_key is null or p_value->p_key='null'::jsonb then
    if p_nullable then return; else raise exception 'Missing %',p_key; end if;
  end if;
  if jsonb_typeof(p_value->p_key)<>'number' or (p_value->>p_key) !~ '^\d+$' then
    raise exception '% must be nonnegative integer cents',p_key;
  end if;
end $$;
revoke all on function public.bsb_open_play_assert_money(jsonb,text,boolean) from public, anon, authenticated;

create or replace function public.bsb_open_play_validate_data(p_type public.bsb_open_play_session_type, p_data jsonb)
returns void language plpgsql security definer immutable set search_path = public, pg_temp
as $$
begin
  if jsonb_typeof(p_data)<>'object' then raise exception 'Session data is required'; end if;
  if p_type='OPEN_BOWLING' then
    if jsonb_typeof(p_data->'pricing')<>'object' then raise exception 'Open bowling pricing snapshot is required'; end if;
    perform public.bsb_open_play_assert_money(p_data->'pricing','laneRateCentsPerHour',false);
    perform public.bsb_open_play_assert_money(p_data->'pricing','shoeRateCents',false);
    perform public.bsb_open_play_assert_money(p_data->'pricing','minimumChargeCents',false);
    perform public.bsb_open_play_assert_money(p_data->'pricing','bowlingSubtotalCents',true);
    perform public.bsb_open_play_assert_money(p_data->'pricing','shoeSubtotalCents',true);
    perform public.bsb_open_play_assert_money(p_data->'pricing','taxableSubtotalCents',true);
    perform public.bsb_open_play_assert_money(p_data->'pricing','taxCents',true);
    perform public.bsb_open_play_assert_money(p_data->'pricing','calculatedTotalCents',true);
    perform public.bsb_open_play_assert_money(p_data->'pricing','chargedTotalCents',true);
  elsif p_type='PARTY' then
    perform public.bsb_open_play_assert_money(p_data,'partyAmountCents',false);
  elsif p_type='PRE_POST' then
    if p_data ? 'partyAmountCents' or p_data ? 'pricing' then raise exception 'Pre/Post cannot contain revenue'; end if;
  end if;
end $$;
revoke all on function public.bsb_open_play_validate_data(public.bsb_open_play_session_type,jsonb) from public, anon, authenticated;

-- Seed only the known BSB organization; no browser local storage is read.
insert into public.open_play_settings(organization_id,settings)
select id, jsonb_build_object('timezone','America/Chicago','laneCount',12,
  'openBowlingLaneRateCents',2500,'shoeRentalRateCents',300,'openBowlingGracePeriodMinutes',5,
  'openBowlingMinimumChargeCents',500,'openBowlingTaxRate',0.08725,
  'showFactsAndJokes',true,'soundEffectsEnabled',false)
from public.organizations where slug='blue-springs-bowl'
on conflict (organization_id) do nothing;
insert into public.open_play_lane_conditions(organization_id,lane_number)
select o.id, n from public.organizations o cross join generate_series(1,12) n where o.slug='blue-springs-bowl'
on conflict (organization_id,lane_number) do nothing;
insert into public.open_play_leagues(organization_id,name,sort_order)
select o.id, x.name, x.sort_order from public.organizations o cross join (values
  ('Tuesday',0),('Wednesday Early',1),('Wednesday Late',2),('Thursday Match Point',3),('Friday Early',4),('Friday Late',5)
) as x(name,sort_order) where o.slug='blue-springs-bowl'
on conflict (organization_id,name) do nothing;

create or replace function public.bsb_get_open_play_state(p_session_token text, p_device_token text)
returns jsonb language plpgsql security definer stable set search_path = public, pg_temp
as $$
declare v public.bsb_open_play_actor_context; v_open uuid; v_previous uuid;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select id into v_open from public.business_nights where organization_id=v.organization_id and status='OPEN';
  select id into v_previous from public.business_nights where organization_id=v.organization_id and status='CLOSED' order by closed_at desc limit 1;
  return jsonb_build_object(
    'settings',(select settings from public.open_play_settings where organization_id=v.organization_id),
    'leagues',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'sortOrder',sort_order) order by sort_order) from public.open_play_leagues where organization_id=v.organization_id),'[]'::jsonb),
    'laneConditions',coalesce((select jsonb_agg(jsonb_build_object('laneNumber',lane_number,'condition',condition,'note',note,'updatedAt',updated_at) order by lane_number) from public.open_play_lane_conditions where organization_id=v.organization_id),'[]'::jsonb),
    'currentNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status',case when status='CLOSED' then 'ARCHIVED' else 'OPEN' end) from public.business_nights where id=v_open),
    'previousNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status','ARCHIVED') from public.business_nights where id=v_previous),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'type',type,'status',status,'startedAt',started_at,'endedAt',ended_at,'createdAt',created_at,'updatedAt',updated_at,'data',data,'version',version)) from public.open_play_sessions where night_id=v_open),'[]'::jsonb),
    'laneAssignments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'sessionId',session_id,'laneNumber',lane_number,'startedAt',started_at,'billingStartedAt',billing_started_at,'billingGroupId',billing_group_id,'billableStartedAt',billable_started_at,'endedAt',ended_at,'endReason',end_reason,'downOverrideConfirmed',down_override_confirmed)) from public.open_play_lane_assignments where night_id=v_open),'[]'::jsonb),
    'activity',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'occurredAt',occurred_at,'type',type,'sessionId',session_id,'laneNumbers',lane_numbers,'summary',summary) order by occurred_at desc) from (select * from public.open_play_activity where night_id=v_open order by occurred_at desc limit 200) a),'[]'::jsonb)
  );
end $$;

create or replace function public.bsb_open_night(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v public.bsb_open_play_actor_context; n public.business_nights; tz text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select settings->>'timezone' into tz from public.open_play_settings where organization_id=v.organization_id;
  insert into public.business_nights(organization_id,business_date,opened_by) values(v.organization_id,(now() at time zone coalesce(tz,'America/Chicago'))::date,v.employee_id) returning * into n;
  perform public.bsb_open_play_log(v.organization_id,n.id,null,'NIGHT_OPENED','{}','Opened night',v.employee_id);
  return jsonb_build_object('id',n.id,'version',1);
exception when unique_violation then raise exception 'A business night is already open'; end $$;

create or replace function public.bsb_start_session(p_session_token text,p_device_token text,p_type public.bsb_open_play_session_type,p_data jsonb,p_lanes integer[],p_down_overrides integer[] default '{}')
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v public.bsb_open_play_actor_context; n public.business_nights; s public.open_play_sessions; lane integer; a uuid;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); perform public.bsb_open_play_validate_data(p_type,p_data);
  if coalesce(array_length(p_lanes,1),0)=0 or exists(select 1 from unnest(p_lanes) x where x not between 1 and 12) or (select count(*) from unnest(p_lanes))<>(select count(distinct x) from unnest(p_lanes) x) then raise exception 'Select one or more distinct lanes'; end if;
  select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update;
  if n.id is null then raise exception 'There is no open night'; end if;
  insert into public.open_play_sessions(organization_id,night_id,type,started_by,created_by,updated_by,data) values(v.organization_id,n.id,p_type,v.employee_id,v.employee_id,v.employee_id,p_data) returning * into s;
  foreach lane in array p_lanes loop
    a:=pg_catalog.gen_random_uuid();
    insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed)
      values(a,v.organization_id,n.id,s.id,lane,v.employee_id,now(),a,lane=any(coalesce(p_down_overrides,'{}')));
  end loop;
  perform public.bsb_open_play_log(v.organization_id,n.id,s.id,'SESSION_STARTED',p_lanes,'Started '||lower(replace(p_type::text,'_',' ')),v.employee_id);
  return jsonb_build_object('id',s.id,'version',s.version);
exception when unique_violation then raise exception 'One or more selected lanes are already in use'; end $$;

create or replace function public.bsb_edit_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb,p_started_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; old_started_at timestamptz;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update;
 if s.id is null or s.status<>'ACTIVE' then raise exception 'Only active sessions can be edited'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; old_started_at:=s.started_at;
 if p_started_at is not null and p_started_at>now() then raise exception 'Start time cannot be in the future'; end if; perform public.bsb_open_play_validate_data(s.type,p_data);
 update public.open_play_sessions set data=p_data,started_at=coalesce(p_started_at,started_at),updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s;
 if p_started_at is not null then update public.open_play_lane_assignments set started_at=p_started_at,billing_started_at=case when billing_started_at=old_started_at then p_started_at else billing_started_at end,updated_at=now() where session_id=s.id and started_at=old_started_at; end if;
 perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'SESSION_EDITED','{}','Edited session',v.employee_id); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_add_lane(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer,p_down_override boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; a uuid;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if p_lane not between 1 and 12 then raise exception 'Invalid lane'; end if; select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'This session is not active'; end if; a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,s.night_id,s.id,p_lane,v.employee_id,now(),a,p_down_override); update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'LANE_ADDED',array[p_lane],'Added lane '||p_lane,v.employee_id); return jsonb_build_object('id',s.id); exception when unique_violation then raise exception 'Lane % is already in use',p_lane; end $$;

create or replace function public.bsb_move_lane(p_session_token text,p_device_token text,p_session_id uuid,p_from_lane integer,p_to_lane integer,p_down_override boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; old public.open_play_lane_assignments; a uuid;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if p_from_lane=p_to_lane or p_to_lane not between 1 and 12 then raise exception 'Choose a different valid lane'; end if; select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'Choose an active session lane to move'; end if; select * into old from public.open_play_lane_assignments where session_id=s.id and lane_number=p_from_lane and ended_at is null for update; if old.id is null then raise exception 'Lane is not assigned to this session'; end if; update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='MOVED',updated_at=now() where id=old.id; a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billable_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,s.night_id,s.id,p_to_lane,v.employee_id,old.billing_started_at,old.billable_started_at,old.billing_group_id,p_down_override); update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'LANE_MOVED',array[p_from_lane,p_to_lane],'Moved lane '||p_from_lane||' to lane '||p_to_lane,v.employee_id); return jsonb_build_object('id',s.id); exception when unique_violation then raise exception 'Lane % is already in use',p_to_lane; end $$;

create or replace function public.bsb_release_lane(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; a public.open_play_lane_assignments;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; select * into a from public.open_play_lane_assignments where session_id=p_session_id and lane_number=p_lane and ended_at is null for update; if s.id is null or s.status<>'ACTIVE' or a.id is null then raise exception 'Lane is not assigned to this active session'; end if; update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='RELEASED',updated_at=now() where id=a.id; update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'LANE_RELEASED',array[p_lane],'Released lane '||p_lane,v.employee_id); return jsonb_build_object('id',s.id); end $$;

create or replace function public.bsb_start_billing_now(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.type<>'OPEN_BOWLING' or s.status<>'ACTIVE' then raise exception 'This open-bowling session is not active'; end if; with changed as (update public.open_play_lane_assignments set billable_started_at=now(),updated_at=now() where session_id=s.id and ended_at is null and billable_started_at is null and (p_lane is null or lane_number=p_lane) returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; if cardinality(lanes)>0 then perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'BILLING_STARTED',lanes,'Started billing now',v.employee_id); end if; return jsonb_build_object('id',s.id); end $$;

-- p_data is the client-calculated session data/snapshot from the established TypeScript engine.
create or replace function public.bsb_end_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'This session is not active'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); with changed as (update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='SESSION_ENDED',updated_at=now() where session_id=s.id and ended_at is null returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; update public.open_play_sessions set status='AWAITING_CLOSE',data=p_data,ended_at=now(),ended_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'SESSION_ENDED',lanes,'Ended session',v.employee_id); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_checkout_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'AWAITING_CLOSE' then raise exception 'End the session before closing it'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); if s.type='OPEN_BOWLING' and (not (p_data->'pricing' ? 'chargedTotalCents') or p_data->'pricing'->'chargedTotalCents'='null'::jsonb) then raise exception 'Charged total is required at checkout'; end if; update public.open_play_sessions set status='COMPLETED',data=p_data,checked_out_at=now(),checked_out_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'SESSION_CLOSED','{}','Closed session',v.employee_id); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_reopen_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status='ACTIVE' then raise exception 'This session cannot be reopened'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); with changed as (update public.open_play_lane_assignments set ended_at=null,ended_by=null,end_reason=null,updated_at=now() where session_id=s.id and end_reason='SESSION_ENDED' returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; update public.open_play_sessions set status='ACTIVE',data=p_data,ended_at=null,ended_by=null,reopened_at=now(),reopened_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log(v.organization_id,s.night_id,s.id,'SESSION_REOPENED',lanes,'Reopened session',v.employee_id); return jsonb_build_object('id',s.id,'version',s.version); exception when unique_violation then raise exception 'Cannot reopen because a lane is now in use'; end $$;

create or replace function public.bsb_set_lane_condition(p_session_token text,p_device_token text,p_lane integer,p_condition public.bsb_open_play_lane_condition,p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); update public.open_play_lane_conditions set condition=p_condition,note=nullif(btrim(p_note),''),updated_at=now(),updated_by=v.employee_id where organization_id=v.organization_id and lane_number=p_lane; if not found then raise exception 'Invalid lane'; end if; select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN'; if n.id is not null then perform public.bsb_open_play_log(v.organization_id,n.id,null,'LANE_CONDITION_CHANGED',array[p_lane],'Updated lane '||p_lane||' condition',v.employee_id); end if; end $$;

create or replace function public.bsb_close_night(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update; if n.id is null then raise exception 'There is no open night'; end if; if exists(select 1 from public.open_play_sessions s where s.night_id=n.id and (s.status not in ('COMPLETED','VOIDED') or (s.type='OPEN_BOWLING' and (not (s.data->'pricing' ? 'chargedTotalCents') or s.data->'pricing'->'chargedTotalCents'='null'::jsonb)))) then raise exception 'Sessions still need resolution'; end if; update public.business_nights set status='CLOSED',closed_at=now(),closed_by=v.employee_id,updated_at=now() where id=n.id returning * into n; perform public.bsb_open_play_log(v.organization_id,n.id,null,'NIGHT_CLOSED','{}','Closed night',v.employee_id); return jsonb_build_object('id',n.id); end $$;

create or replace function public.bsb_save_open_play_settings(p_session_token text,p_device_token text,p_settings jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if; if jsonb_typeof(p_settings)<>'object' then raise exception 'Settings are required'; end if; update public.open_play_settings set settings=p_settings,updated_at=now(),updated_by=v.employee_id where organization_id=v.organization_id; end $$;

create or replace function public.bsb_save_open_play_league(p_session_token text,p_device_token text,p_league_id uuid,p_name text,p_active boolean,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; l public.open_play_leagues;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if; if btrim(p_name)='' or p_sort_order<0 then raise exception 'Valid league name and order are required'; end if;
  if p_league_id is null then insert into public.open_play_leagues(organization_id,name,active,sort_order,updated_by) values(v.organization_id,btrim(p_name),p_active,p_sort_order,v.employee_id) returning * into l;
  else update public.open_play_leagues set name=btrim(p_name),active=p_active,sort_order=p_sort_order,updated_at=now(),updated_by=v.employee_id where id=p_league_id and organization_id=v.organization_id returning * into l; if l.id is null then raise exception 'League option not found'; end if; end if;
  return jsonb_build_object('id',l.id,'name',l.name,'active',l.active,'sortOrder',l.sort_order);
end $$;

grant execute on function public.bsb_get_open_play_state(text,text) to anon;
grant execute on function public.bsb_open_night(text,text) to anon;
grant execute on function public.bsb_start_session(text,text,public.bsb_open_play_session_type,jsonb,integer[],integer[]) to anon;
grant execute on function public.bsb_edit_session(text,text,uuid,integer,jsonb,timestamptz) to anon;
grant execute on function public.bsb_add_lane(text,text,uuid,integer,boolean) to anon;
grant execute on function public.bsb_move_lane(text,text,uuid,integer,integer,boolean) to anon;
grant execute on function public.bsb_release_lane(text,text,uuid,integer) to anon;
grant execute on function public.bsb_start_billing_now(text,text,uuid,integer) to anon;
grant execute on function public.bsb_end_session(text,text,uuid,integer,jsonb) to anon;
grant execute on function public.bsb_checkout_session(text,text,uuid,integer,jsonb) to anon;
grant execute on function public.bsb_reopen_session(text,text,uuid,integer,jsonb) to anon;
grant execute on function public.bsb_set_lane_condition(text,text,integer,public.bsb_open_play_lane_condition,text) to anon;
grant execute on function public.bsb_close_night(text,text) to anon;
grant execute on function public.bsb_save_open_play_settings(text,text,jsonb) to anon;
grant execute on function public.bsb_save_open_play_league(text,text,uuid,text,boolean,integer) to anon;
