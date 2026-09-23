-- Center-wide Bowling Schedule contract. Run only after 202609230001 commits the enum labels.

alter table public.open_play_bookings alter column league_id drop not null;
alter table public.open_play_bookings alter column league_name_snapshot drop not null;
alter table public.open_play_bookings alter column designation drop not null;
alter table public.open_play_bookings alter column team_description drop not null;
alter table public.open_play_bookings add column party_name text;
alter table public.open_play_bookings add column party_amount_cents integer;
alter table public.open_play_bookings add column customer_name text;
alter table public.open_play_bookings add column expected_bowlers integer;
alter table public.open_play_bookings add constraint open_play_bookings_type_details check (
  (type='PRE_POST' and league_id is not null and league_name_snapshot is not null and designation in ('PRE','POST') and char_length(btrim(team_description)) between 1 and 240 and party_name is null and party_amount_cents is null and customer_name is null and expected_bowlers is null) or
  (type='PARTY' and league_id is null and league_name_snapshot is null and designation is null and team_description is null and char_length(btrim(party_name)) between 1 and 240 and party_amount_cents between 0 and 100000000 and customer_name is null and expected_bowlers is null) or
  (type='OPEN_PLAY' and league_id is null and league_name_snapshot is null and designation is null and team_description is null and party_name is null and party_amount_cents is null and char_length(btrim(customer_name)) between 1 and 240 and (expected_bowlers is null or expected_bowlers between 1 and 500))
);
create index open_play_bookings_calendar on public.open_play_bookings(organization_id,scheduled_at) where status='SCHEDULED';

create or replace function public.bsb_create_bowling_booking(p_session_token text,p_device_token text,p_type public.bsb_booking_type,p_scheduled_at timestamptz,p_league_id uuid,p_designation text,p_team_description text,p_party_name text,p_party_amount_cents integer,p_customer_name text,p_expected_bowlers integer,p_lanes_needed integer,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; l public.open_play_leagues; b public.open_play_bookings; v_name text;
begin
 v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
 if p_scheduled_at is null then raise exception 'Date and time are required'; end if;
 if p_lanes_needed not between 1 and 12 then raise exception 'Lanes needed must be between 1 and 12'; end if;
 if p_type='PRE_POST' then
  if p_designation not in ('PRE','POST') or char_length(btrim(coalesce(p_team_description,''))) not between 1 and 240 then raise exception 'Enter valid Pre/Post details'; end if;
  select * into l from public.open_play_leagues where id=p_league_id and organization_id=v.organization_id and active;
  if l.id is null then raise exception 'Select an active league/night'; end if;
 elsif p_type='PARTY' then
  if char_length(btrim(coalesce(p_party_name,''))) not between 1 and 240 or p_party_amount_cents not between 0 and 100000000 then raise exception 'Enter valid party details'; end if;
 elsif p_type='OPEN_PLAY' then
  if char_length(btrim(coalesce(p_customer_name,''))) not between 1 and 240 or (p_expected_bowlers is not null and p_expected_bowlers not between 1 and 500) then raise exception 'Enter valid Open Play details'; end if;
 end if;
 select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
 insert into public.open_play_bookings(organization_id,type,scheduled_at,league_id,league_name_snapshot,designation,team_description,party_name,party_amount_cents,customer_name,expected_bowlers,lanes_needed,notes,created_by,created_by_name,updated_by,updated_by_name)
 values(v.organization_id,p_type,p_scheduled_at,l.id,l.name,p_designation,nullif(btrim(coalesce(p_team_description,'')),''),nullif(btrim(coalesce(p_party_name,'')),''),p_party_amount_cents,nullif(btrim(coalesce(p_customer_name,'')),''),p_expected_bowlers,p_lanes_needed,nullif(btrim(coalesce(p_notes,'')),''),v.employee_id,v_name,v.employee_id,v_name) returning * into b;
 perform public.bsb_booking_log(v,b.id,'BOOKING_CREATED',jsonb_build_object('type',b.type,'scheduledAt',b.scheduled_at,'lanesNeeded',b.lanes_needed));
 return jsonb_build_object('id',b.id,'version',b.version);
end $$;

create or replace function public.bsb_update_bowling_booking(p_session_token text,p_device_token text,p_booking_id uuid,p_expected_version integer,p_type public.bsb_booking_type,p_scheduled_at timestamptz,p_league_id uuid,p_designation text,p_team_description text,p_party_name text,p_party_amount_cents integer,p_customer_name text,p_expected_bowlers integer,p_lanes_needed integer,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; b public.open_play_bookings; l public.open_play_leagues; v_name text;
begin
 v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
 select * into b from public.open_play_bookings where id=p_booking_id and organization_id=v.organization_id for update;
 if b.id is null then raise exception 'Booking not found'; end if;
 if b.status<>'SCHEDULED' then raise exception 'Only scheduled bookings can be edited'; end if;
 if b.version<>p_expected_version then raise exception 'Stale booking'; end if;
 if p_type<>b.type then raise exception 'Booking type cannot be changed'; end if;
 if p_scheduled_at is null or p_lanes_needed not between 1 and 12 then raise exception 'Enter valid booking details'; end if;
 if p_type='PRE_POST' then select * into l from public.open_play_leagues where id=p_league_id and organization_id=v.organization_id and active; if l.id is null or p_designation not in ('PRE','POST') or char_length(btrim(coalesce(p_team_description,''))) not between 1 and 240 then raise exception 'Enter valid Pre/Post details'; end if;
 elsif p_type='PARTY' and (char_length(btrim(coalesce(p_party_name,''))) not between 1 and 240 or p_party_amount_cents not between 0 and 100000000) then raise exception 'Enter valid party details';
 elsif p_type='OPEN_PLAY' and (char_length(btrim(coalesce(p_customer_name,''))) not between 1 and 240 or (p_expected_bowlers is not null and p_expected_bowlers not between 1 and 500)) then raise exception 'Enter valid Open Play details'; end if;
 select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
 update public.open_play_bookings set scheduled_at=p_scheduled_at,league_id=l.id,league_name_snapshot=l.name,designation=case when p_type='PRE_POST' then p_designation end,team_description=case when p_type='PRE_POST' then btrim(p_team_description) end,party_name=case when p_type='PARTY' then btrim(p_party_name) end,party_amount_cents=case when p_type='PARTY' then p_party_amount_cents end,customer_name=case when p_type='OPEN_PLAY' then btrim(p_customer_name) end,expected_bowlers=case when p_type='OPEN_PLAY' then p_expected_bowlers end,lanes_needed=p_lanes_needed,notes=nullif(btrim(coalesce(p_notes,'')),''),updated_at=now(),updated_by=v.employee_id,updated_by_name=v_name,version=version+1 where id=b.id returning * into b;
 perform public.bsb_booking_log(v,b.id,'BOOKING_UPDATED',jsonb_build_object('type',b.type,'version',b.version)); return jsonb_build_object('id',b.id,'version',b.version);
end $$;

create or replace function public.bsb_start_bowling_booking(p_session_token text,p_device_token text,p_booking_id uuid,p_expected_version integer,p_lanes integer[],p_down_overrides integer[] default '{}',p_actual_bowlers integer default null,p_actual_shoes integer default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.bsb_open_play_actor_context; b public.open_play_bookings; n public.business_nights; s public.open_play_sessions; cfg jsonb; v_data jsonb; a uuid; lane integer; v_name text; v_session_type public.bsb_open_play_session_type;
begin
 v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
 select * into b from public.open_play_bookings where id=p_booking_id and organization_id=v.organization_id for update;
 if b.id is null then raise exception 'Booking not found'; end if;
 if b.status='STARTED' then raise exception 'This booking has already been started'; end if;
 if b.status='CANCELLED' then raise exception 'A cancelled booking cannot be started'; end if;
 if b.version<>p_expected_version then raise exception 'Stale booking'; end if;
 if cardinality(p_lanes)<>b.lanes_needed or exists(select 1 from unnest(p_lanes) x where x not between 1 and 12) or (select count(*) from unnest(p_lanes))<>(select count(distinct x) from unnest(p_lanes) x) then raise exception 'Select exactly % distinct lane(s)',b.lanes_needed; end if;
 select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update;
 if n.id is null then raise exception 'There is no open night'; end if;
 if b.type='PRE_POST' then v_session_type:='PRE_POST';v_data:=jsonb_build_object('leagueId',b.league_id,'leagueNameSnapshot',b.league_name_snapshot,'designation',b.designation,'teamDescription',b.team_description,'bowlerCount',0,'notes',b.notes);
 elsif b.type='PARTY' then v_session_type:='PARTY';v_data:=jsonb_build_object('partyName',b.party_name,'bowlerCount',0,'partyAmountCents',b.party_amount_cents,'notes',b.notes);
 else
  if p_actual_bowlers is null or p_actual_bowlers<1 or p_actual_shoes is null or p_actual_shoes<0 then raise exception 'Confirm actual bowlers and shoe rentals'; end if;
  select settings into cfg from public.open_play_settings where organization_id=v.organization_id;
  v_session_type:='OPEN_BOWLING';v_data:=jsonb_build_object('partyName',b.customer_name,'bowlerCount',p_actual_bowlers,'shoeCount',p_actual_shoes,'notes',b.notes,'pricing',jsonb_build_object('laneRateCentsPerHour',(cfg->>'openBowlingLaneRateCents')::integer,'shoeRateCents',(cfg->>'shoeRentalRateCents')::integer,'gracePeriodMinutes',(cfg->>'openBowlingGracePeriodMinutes')::integer,'minimumChargeCents',(cfg->>'openBowlingMinimumChargeCents')::integer,'taxRate',(cfg->>'openBowlingTaxRate')::numeric,'bowlingSubtotalCents',null,'shoeSubtotalCents',null,'taxableSubtotalCents',null,'taxCents',null,'calculatedTotalCents',null,'roundedTotalCents',null,'chargedTotalCents',null,'adjustmentNote',null));
 end if;
 perform public.bsb_open_play_validate_data(v_session_type,v_data);
 insert into public.open_play_sessions(organization_id,night_id,type,started_by,created_by,updated_by,data) values(v.organization_id,n.id,v_session_type,v.employee_id,v.employee_id,v.employee_id,v_data) returning * into s;
 foreach lane in array p_lanes loop a:=pg_catalog.gen_random_uuid();insert into public.open_play_lane_assignments(id,organization_id,night_id,session_id,lane_number,started_by,billing_started_at,billing_group_id,down_override_confirmed) values(a,v.organization_id,n.id,s.id,lane,v.employee_id,now(),a,lane=any(coalesce(p_down_overrides,'{}')));end loop;
 select display_name into v_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
 update public.open_play_bookings set status='STARTED',started_at=now(),started_by=v.employee_id,started_by_name=v_name,resulting_session_id=s.id,updated_at=now(),updated_by=v.employee_id,updated_by_name=v_name,version=version+1 where id=b.id returning * into b;
 perform public.bsb_open_play_log_actor(v,n.id,s.id,'SESSION_STARTED',p_lanes,'Started scheduled '||replace(v_session_type::text,'_',' '),jsonb_build_object('sessionType',v_session_type,'label',coalesce(b.team_description,b.party_name,b.customer_name),'bookingId',b.id));
 perform public.bsb_booking_log(v,b.id,'BOOKING_STARTED',jsonb_build_object('type',b.type,'sessionId',s.id,'nightId',n.id,'lanes',to_jsonb(p_lanes)));
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
  'bookings',coalesce((select jsonb_agg(jsonb_build_object('id',id,'type',type,'status',status,'scheduledAt',scheduled_at,'leagueId',league_id,'leagueNameSnapshot',league_name_snapshot,'designation',designation,'teamDescription',team_description,'partyName',party_name,'partyAmountCents',party_amount_cents,'customerName',customer_name,'expectedBowlers',expected_bowlers,'lanesNeeded',lanes_needed,'notes',notes,'createdAt',created_at,'createdBy',created_by,'createdByName',created_by_name,'updatedAt',updated_at,'updatedBy',updated_by,'updatedByName',updated_by_name,'version',version,'startedAt',started_at,'startedBy',started_by,'startedByName',started_by_name,'cancelledAt',cancelled_at,'cancelledBy',cancelled_by,'cancelledByName',cancelled_by_name,'cancellationNote',cancellation_note,'resultingSessionId',resulting_session_id) order by scheduled_at,id) from public.open_play_bookings where organization_id=v.organization_id and (status='SCHEDULED' or scheduled_at>=now()-interval '90 days')),'[]'::jsonb)
 );
end $$;

revoke all on function public.bsb_create_bowling_booking(text,text,public.bsb_booking_type,timestamptz,uuid,text,text,text,integer,text,integer,integer,text) from public,anon,authenticated;
revoke all on function public.bsb_update_bowling_booking(text,text,uuid,integer,public.bsb_booking_type,timestamptz,uuid,text,text,text,integer,text,integer,integer,text) from public,anon,authenticated;
revoke all on function public.bsb_start_bowling_booking(text,text,uuid,integer,integer[],integer[],integer,integer) from public,anon,authenticated;
grant execute on function public.bsb_create_bowling_booking(text,text,public.bsb_booking_type,timestamptz,uuid,text,text,text,integer,text,integer,integer,text) to anon;
grant execute on function public.bsb_update_bowling_booking(text,text,uuid,integer,public.bsb_booking_type,timestamptz,uuid,text,text,text,integer,text,integer,integer,text) to anon;
grant execute on function public.bsb_start_bowling_booking(text,text,uuid,integer,integer[],integer[],integer,integer) to anon;
