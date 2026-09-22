-- Slice 4: authoritative employee attribution for the existing Open Play activity stream.
-- Existing rows remain valid and intentionally retain null snapshots/device/details.

alter table public.open_play_activity
  alter column night_id drop not null,
  alter column performed_by drop not null,
  add column if not exists performed_by_name text,
  add column if not exists device_id uuid references public.authorized_devices(id) on delete restrict,
  add column if not exists details jsonb not null default '{}'::jsonb;

alter table public.open_play_activity
  add constraint open_play_activity_details_object check (jsonb_typeof(details) = 'object');

-- The actor is always the context returned by bsb_open_play_require_actor. The
-- browser has no identity parameter to spoof. The name is copied at write time.
create or replace function public.bsb_open_play_log_actor(
  p_actor public.bsb_open_play_actor_context, p_night uuid, p_session uuid,
  p_type text, p_lanes integer[], p_summary text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_name text;
begin
  select display_name into v_name from public.employees
    where id=p_actor.employee_id and organization_id=p_actor.organization_id;
  if v_name is null then raise exception 'Authorized employee not found'; end if;
  insert into public.open_play_activity(
    organization_id,night_id,session_id,type,lane_numbers,summary,performed_by,
    performed_by_name,device_id,details)
  values(p_actor.organization_id,p_night,p_session,p_type,coalesce(p_lanes,'{}'),p_summary,
    p_actor.employee_id,v_name,p_actor.device_id,coalesce(p_details,'{}'::jsonb));
end $$;
revoke all on function public.bsb_open_play_log_actor(public.bsb_open_play_actor_context,uuid,uuid,text,integer[],text,jsonb) from public, anon, authenticated;

create or replace function public.bsb_get_open_play_state(p_session_token text, p_device_token text)
returns jsonb language plpgsql security definer stable set search_path = public, pg_temp
as $$
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
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'type',type,'status',status,'startedAt',started_at,'endedAt',ended_at,'createdAt',created_at,'updatedAt',updated_at,'data',data,'version',version)) from public.open_play_sessions where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'laneAssignments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'sessionId',session_id,'laneNumber',lane_number,'startedAt',started_at,'billingStartedAt',billing_started_at,'billingGroupId',billing_group_id,'billableStartedAt',billable_started_at,'endedAt',ended_at,'endReason',end_reason,'downOverrideConfirmed',down_override_confirmed)) from public.open_play_lane_assignments where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'activity',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'occurredAt',occurred_at,'type',type,'sessionId',session_id,'laneNumbers',lane_numbers,'summary',summary,'employeeId',performed_by,'employeeName',performed_by_name,'deviceId',device_id,'details',details) order by occurred_at desc) from (select * from public.open_play_activity where night_id=v_activity_night order by occurred_at desc limit 200) a),'[]'::jsonb)
  );
end $$;

create or replace function public.bsb_open_night(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights; tz text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select settings->>'timezone' into tz from public.open_play_settings where organization_id=v.organization_id; insert into public.business_nights(organization_id,business_date,opened_by) values(v.organization_id,(now() at time zone coalesce(tz,'America/Chicago'))::date,v.employee_id) returning * into n; perform public.bsb_open_play_log_actor(v,n.id,null,'NIGHT_OPENED','{}','Opened night',jsonb_build_object('businessDate',n.business_date)); return jsonb_build_object('id',n.id,'version',1); exception when unique_violation then raise exception 'A business night is already open'; end $$;

create or replace function public.bsb_start_session(p_session_token text,p_device_token text,p_type public.bsb_open_play_session_type,p_data jsonb,p_lanes integer[],p_down_overrides integer[] default '{}')
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights; s public.open_play_sessions; lane integer; a uuid; label text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); perform public.bsb_open_play_validate_data(p_type,p_data); if coalesce(array_length(p_lanes,1),0)=0 or exists(select 1 from unnest(p_lanes) x where x not between 1 and 12) or (select count(*) from unnest(p_lanes))<>(select count(distinct x) from unnest(p_lanes) x) then raise exception 'Select one or more distinct lanes'; end if; select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update; if n.id is null then raise exception 'There is no open night'; end if; insert into public.open_play_sessions(organization_id,night_id,type,started_by,created_by,updated_by,data) values(v.organization_id,n.id,p_type,v.employee_id,v.employee_id,v.employee_id,p_data) returning * into s; foreach lane in array p_lanes loop a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,n.id,s.id,lane,v.employee_id,now(),a,lane=any(coalesce(p_down_overrides,'{}'))); end loop; label:=case p_type when 'OPEN_BOWLING' then 'Started Open Bowling' when 'PRE_POST' then 'Started Pre/Post Bowl' else 'Started Party' end; perform public.bsb_open_play_log_actor(v,n.id,s.id,'SESSION_STARTED',p_lanes,label,jsonb_build_object('sessionType',p_type,'label',coalesce(p_data->>'partyName',p_data->>'teamDescription',p_data->>'leagueNameSnapshot'))); return jsonb_build_object('id',s.id,'version',s.version); exception when unique_violation then raise exception 'One or more selected lanes are already in use'; end $$;

create or replace function public.bsb_edit_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb,p_started_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; old_started_at timestamptz; old_data jsonb;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'Only active sessions can be edited'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; old_started_at:=s.started_at; old_data:=s.data; if p_started_at is not null and p_started_at>now() then raise exception 'Start time cannot be in the future'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); update public.open_play_sessions set data=p_data,started_at=coalesce(p_started_at,started_at),updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; if p_started_at is not null then update public.open_play_lane_assignments set started_at=p_started_at,billing_started_at=case when billing_started_at=old_started_at then p_started_at else billing_started_at end,updated_at=now() where session_id=s.id and started_at=old_started_at; end if; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_EDITED','{}','Edited session',jsonb_build_object('before',old_data,'after',p_data,'previousStartedAt',old_started_at,'startedAt',s.started_at)); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_add_lane(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer,p_down_override boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; a uuid;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if p_lane not between 1 and 12 then raise exception 'Invalid lane'; end if; select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'This session is not active'; end if; a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,s.night_id,s.id,p_lane,v.employee_id,now(),a,p_down_override); update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'LANE_ADDED',array[p_lane],'Added lane '||p_lane,jsonb_build_object('downOverride',p_down_override)); return jsonb_build_object('id',s.id); exception when unique_violation then raise exception 'Lane % is already in use',p_lane; end $$;

create or replace function public.bsb_move_lane(p_session_token text,p_device_token text,p_session_id uuid,p_from_lane integer,p_to_lane integer,p_down_override boolean default false)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; old public.open_play_lane_assignments; a uuid;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if p_from_lane=p_to_lane or p_to_lane not between 1 and 12 then raise exception 'Choose a different valid lane'; end if; select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'Choose an active session lane to move'; end if; select * into old from public.open_play_lane_assignments where session_id=s.id and lane_number=p_from_lane and ended_at is null for update; if old.id is null then raise exception 'Lane is not assigned to this session'; end if; update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='MOVED',updated_at=now() where id=old.id; a:=pg_catalog.gen_random_uuid(); insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billable_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,s.night_id,s.id,p_to_lane,v.employee_id,old.billing_started_at,old.billable_started_at,old.billing_group_id,p_down_override); update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'LANE_MOVED',array[p_from_lane,p_to_lane],'Moved lane '||p_from_lane||' → '||p_to_lane,jsonb_build_object('fromLane',p_from_lane,'toLane',p_to_lane,'downOverride',p_down_override)); return jsonb_build_object('id',s.id); exception when unique_violation then raise exception 'Lane % is already in use',p_to_lane; end $$;

create or replace function public.bsb_release_lane(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; a public.open_play_lane_assignments;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; select * into a from public.open_play_lane_assignments where session_id=p_session_id and lane_number=p_lane and ended_at is null for update; if s.id is null or s.status<>'ACTIVE' or a.id is null then raise exception 'Lane is not assigned to this active session'; end if; update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='RELEASED',updated_at=now() where id=a.id; update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'LANE_RELEASED',array[p_lane],'Released lane '||p_lane,'{}'); return jsonb_build_object('id',s.id); end $$;

create or replace function public.bsb_start_billing_now(p_session_token text,p_device_token text,p_session_id uuid,p_lane integer default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.type<>'OPEN_BOWLING' or s.status<>'ACTIVE' then raise exception 'This open-bowling session is not active'; end if; with changed as (update public.open_play_lane_assignments set billable_started_at=now(),updated_at=now() where session_id=s.id and ended_at is null and billable_started_at is null and (p_lane is null or lane_number=p_lane) returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; if cardinality(lanes)>0 then update public.open_play_sessions set updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'BILLING_STARTED',lanes,'Started billing',jsonb_build_object('forcedGraceCompletion',true)); end if; return jsonb_build_object('id',s.id); end $$;

create or replace function public.bsb_end_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'This session is not active'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); with changed as (update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='SESSION_ENDED',updated_at=now() where session_id=s.id and ended_at is null returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; update public.open_play_sessions set status='AWAITING_CLOSE',data=p_data,ended_at=now(),ended_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_ENDED',lanes,'Ended session','{}'); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_checkout_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[]; charged integer; calculated integer; note text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'AWAITING_CLOSE' then raise exception 'End the session before closing it'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); if s.type='OPEN_BOWLING' and (not (p_data->'pricing' ? 'chargedTotalCents') or p_data->'pricing'->'chargedTotalCents'='null'::jsonb) then raise exception 'Charged total is required at checkout'; end if; select coalesce(array_agg(lane_number order by lane_number),'{}') into lanes from public.open_play_lane_assignments where session_id=s.id; charged:=case when s.type='OPEN_BOWLING' then (p_data->'pricing'->>'chargedTotalCents')::integer else coalesce((p_data->>'partyAmountCents')::integer,0) end; calculated:=case when s.type='OPEN_BOWLING' then (p_data->'pricing'->>'calculatedTotalCents')::integer else charged end; note:=case when s.type='OPEN_BOWLING' then nullif(p_data->'pricing'->>'adjustmentNote','') end; update public.open_play_sessions set status='COMPLETED',data=p_data,checked_out_at=now(),checked_out_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'CHECKOUT_COMPLETED',lanes,'Checkout completed',jsonb_strip_nulls(jsonb_build_object('chargedTotalCents',charged,'calculatedTotalCents',calculated,'adjustmentCents',charged-calculated,'adjustmentNote',note))); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_reopen_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[];
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status='ACTIVE' then raise exception 'This session cannot be reopened'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); with changed as (update public.open_play_lane_assignments set ended_at=null,ended_by=null,end_reason=null,updated_at=now() where session_id=s.id and end_reason='SESSION_ENDED' returning lane_number) select coalesce(array_agg(lane_number),'{}') into lanes from changed; update public.open_play_sessions set status='ACTIVE',data=p_data,ended_at=null,ended_by=null,reopened_at=now(),reopened_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_REOPENED',lanes,'Reopened session',jsonb_build_object('correction',true)); return jsonb_build_object('id',s.id,'version',s.version); exception when unique_violation then raise exception 'Cannot reopen because a lane is now in use'; end $$;

create or replace function public.bsb_set_lane_condition(p_session_token text,p_device_token text,p_lane integer,p_condition public.bsb_open_play_lane_condition,p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights; old public.open_play_lane_conditions;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into old from public.open_play_lane_conditions where organization_id=v.organization_id and lane_number=p_lane for update; if old.lane_number is null then raise exception 'Invalid lane'; end if; update public.open_play_lane_conditions set condition=p_condition,note=nullif(btrim(p_note),''),updated_at=now(),updated_by=v.employee_id where organization_id=v.organization_id and lane_number=p_lane; select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN'; if n.id is not null and (old.condition<>p_condition or old.note is distinct from nullif(btrim(p_note),'')) then perform public.bsb_open_play_log_actor(v,n.id,null,'LANE_CONDITION_CHANGED',array[p_lane],'Changed lane '||p_lane||' condition',jsonb_build_object('previousCondition',old.condition,'condition',p_condition,'note',nullif(btrim(p_note),''))); end if; end $$;

create or replace function public.bsb_close_night(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n public.business_nights;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update; if n.id is null then raise exception 'There is no open night'; end if; if exists(select 1 from public.open_play_sessions s where s.night_id=n.id and (s.status not in ('COMPLETED','VOIDED') or (s.type='OPEN_BOWLING' and (not (s.data->'pricing' ? 'chargedTotalCents') or s.data->'pricing'->'chargedTotalCents'='null'::jsonb)))) then raise exception 'Sessions still need resolution'; end if; update public.business_nights set status='CLOSED',closed_at=now(),closed_by=v.employee_id,updated_at=now() where id=n.id returning * into n; perform public.bsb_open_play_log_actor(v,n.id,null,'NIGHT_CLOSED','{}','Closed night','{}'); return jsonb_build_object('id',n.id); end $$;

create or replace function public.bsb_save_open_play_settings(p_session_token text,p_device_token text,p_settings jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; n uuid; old_settings jsonb;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if; if jsonb_typeof(p_settings)<>'object' then raise exception 'Settings are required'; end if; select settings into old_settings from public.open_play_settings where organization_id=v.organization_id for update; if old_settings is distinct from p_settings then update public.open_play_settings set settings=p_settings,updated_at=now(),updated_by=v.employee_id where organization_id=v.organization_id; select id into n from public.business_nights where organization_id=v.organization_id and status='OPEN'; perform public.bsb_open_play_log_actor(v,n,null,'SETTINGS_CHANGED','{}','Changed Open Play settings',jsonb_build_object('before',old_settings,'after',p_settings)); end if; end $$;

create or replace function public.bsb_save_open_play_league(p_session_token text,p_device_token text,p_league_id uuid,p_name text,p_active boolean,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; l public.open_play_leagues; old public.open_play_leagues; n uuid; action text; changed boolean:=true;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if; if btrim(p_name)='' or p_sort_order<0 then raise exception 'Valid league name and order are required'; end if; if p_league_id is null then insert into public.open_play_leagues(organization_id,name,active,sort_order,updated_by) values(v.organization_id,btrim(p_name),p_active,p_sort_order,v.employee_id) returning * into l; action:='Added league option'; else select * into old from public.open_play_leagues where id=p_league_id and organization_id=v.organization_id for update; if old.id is null then raise exception 'League option not found'; end if; changed:=old.name is distinct from btrim(p_name) or old.active is distinct from p_active or old.sort_order is distinct from p_sort_order; if changed then update public.open_play_leagues set name=btrim(p_name),active=p_active,sort_order=p_sort_order,updated_at=now(),updated_by=v.employee_id where id=old.id returning * into l; else l:=old; end if; action:='Changed league option'; end if; if changed then select id into n from public.business_nights where organization_id=v.organization_id and status='OPEN'; perform public.bsb_open_play_log_actor(v,n,null,'LEAGUE_SETTINGS_CHANGED','{}',action,jsonb_build_object('leagueId',l.id,'name',l.name,'active',l.active,'sortOrder',l.sort_order)); end if; return jsonb_build_object('id',l.id,'name',l.name,'active',l.active,'sortOrder',l.sort_order); end $$;

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
