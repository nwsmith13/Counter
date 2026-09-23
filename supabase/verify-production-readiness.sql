-- Open Play Book production readiness verification (READ ONLY).
-- Run manually in the BSB Operations Supabase SQL Editor after taking a backup.
-- This script performs catalog/data reads only and returns PASS/FAIL rows.

with
required_tables(name) as (values
  ('organizations'),('employees'),('authorized_devices'),('employee_terminal_sessions'),
  ('device_enrollment_codes'),('business_nights'),('open_play_settings'),
  ('open_play_leagues'),('open_play_sessions'),('open_play_lane_assignments'),
  ('open_play_lane_conditions'),('open_play_activity'),
  ('open_play_bookings'),('open_play_booking_activity')
),
required_columns(table_name,column_name) as (values
  ('organizations','slug'),('employees','role'),('employees','active'),
  ('authorized_devices','token_hash'),('authorized_devices','active'),
  ('authorized_devices','updated_at'),
  ('employee_terminal_sessions','expires_at'),('employee_terminal_sessions','revoked_at'),
  ('device_enrollment_codes','code_hash'),('device_enrollment_codes','expires_at'),('device_enrollment_codes','used_at'),
  ('business_nights','status'),('open_play_settings','settings'),('open_play_leagues','sort_order'),
  ('open_play_sessions','status'),('open_play_sessions','version'),('open_play_sessions','checked_out_at'),
  ('open_play_sessions','voided_at'),('open_play_sessions','void_category'),('open_play_sessions','pre_void_status'),
  ('open_play_sessions','voided_by'),('open_play_sessions','voided_by_name'),('open_play_sessions','void_note'),
  ('open_play_sessions','reinstated_at'),('open_play_sessions','reinstated_by'),
  ('open_play_sessions','reinstated_by_name'),('open_play_sessions','reinstatement_note'),
  ('open_play_lane_assignments','billable_started_at'),
  ('open_play_lane_assignments','billing_group_id'),('open_play_activity','performed_by_name'),
  ('open_play_activity','device_id'),('open_play_activity','details'),
  ('open_play_bookings','status'),('open_play_bookings','scheduled_at'),
  ('open_play_bookings','lanes_needed'),('open_play_bookings','version'),
  ('open_play_bookings','resulting_session_id'),
  ('open_play_booking_activity','booking_id'),('open_play_booking_activity','type'),
  ('open_play_booking_activity','performed_by_name'),('open_play_booking_activity','device_id')
),
browser_rpcs(signature) as (values
  ('bsb_list_active_employees(text)'),('bsb_verify_employee_pin(text,uuid,text)'),
  ('bsb_owner_list_employees(text)'),('bsb_owner_save_employee(text,uuid,text,bsb_employee_role,boolean,text)'),
  ('bsb_owner_list_devices(text)'),('bsb_owner_create_device_enrollment(text,text)'),
  ('bsb_owner_list_devices_with_current(text)'),('bsb_owner_rename_device(text,uuid,text)'),
  ('bsb_redeem_device_enrollment(text)'),('bsb_owner_set_device_active(text,uuid,boolean)'),
  ('bsb_get_open_play_state(text,text)'),('bsb_open_night(text,text)'),
  ('bsb_start_session(text,text,bsb_open_play_session_type,jsonb,integer[],integer[])'),
  ('bsb_edit_session(text,text,uuid,integer,jsonb,timestamp with time zone)'),
  ('bsb_add_lane(text,text,uuid,integer,boolean)'),('bsb_move_lane(text,text,uuid,integer,integer,boolean)'),
  ('bsb_release_lane(text,text,uuid,integer)'),('bsb_start_billing_now(text,text,uuid,integer)'),
  ('bsb_end_session(text,text,uuid,integer,jsonb)'),('bsb_checkout_session(text,text,uuid,integer,jsonb)'),
  ('bsb_reopen_session(text,text,uuid,integer,jsonb)'),('bsb_void_session(text,text,uuid,integer,text,text)'),
  ('bsb_reinstate_session(text,text,uuid,integer,text)'),
  ('bsb_set_lane_condition(text,text,integer,bsb_open_play_lane_condition,text)'),
  ('bsb_close_night(text,text)'),('bsb_save_open_play_settings(text,text,jsonb)'),
  ('bsb_save_open_play_league(text,text,uuid,text,boolean,integer)'),
  ('bsb_create_booking(text,text,timestamp with time zone,uuid,text,text,integer,text)'),
  ('bsb_update_booking(text,text,uuid,integer,timestamp with time zone,uuid,text,text,integer,text)'),
  ('bsb_cancel_booking(text,text,uuid,integer,text)'),
  ('bsb_start_booking(text,text,uuid,integer,integer[],integer[])')
),
internal_helpers(signature) as (values
  ('bsb_device(text)'),('bsb_session_employee(text)'),('bsb_open_play_actor(text,text)'),
  ('bsb_open_play_require_actor(text,text)'),('bsb_open_play_assert_money(jsonb,text,boolean)'),
  ('bsb_open_play_validate_data(bsb_open_play_session_type,jsonb)'),
  ('bsb_open_play_log(uuid,uuid,uuid,text,integer[],text,uuid)'),
  ('bsb_open_play_log_actor(bsb_open_play_actor_context,uuid,uuid,text,integer[],text,jsonb)'),
  ('bsb_open_play_require_open_night_for_row()'),
  ('bsb_booking_log(bsb_open_play_actor_context,uuid,text,jsonb)')
),
required_indexes(name) as (values
  ('business_nights_one_open_per_organization'),
  ('open_play_one_active_assignment_per_lane'),
  ('device_enrollment_codes_code_hash_key'),
  ('authorized_devices_token_hash_key'),
  ('employee_terminal_sessions_token_hash_key'),
  ('open_play_bookings_upcoming'),
  ('open_play_bookings_resulting_session_id_key')
),
required_constraints(table_name,name) as (values
  ('open_play_sessions','open_play_sessions_void_context'),
  ('open_play_sessions','open_play_sessions_reinstatement_context')
),
required_triggers(table_name,name) as (values
  ('open_play_sessions','bsb_open_play_sessions_open_night_barrier'),
  ('open_play_lane_assignments','bsb_open_play_lane_assignments_open_night_barrier')
),
enum_expectations(type_name, expected) as (values
  ('bsb_employee_role','EMPLOYEE,MANAGER,OWNER'),
  ('bsb_open_play_night_status','CLOSED,OPEN'),
  ('bsb_open_play_session_type','OPEN_BOWLING,PARTY,PRE_POST'),
  ('bsb_open_play_session_status','ACTIVE,AWAITING_CLOSE,COMPLETED,VOIDED'),
  ('bsb_open_play_lane_condition','AVAILABLE,DOWN,WATCH'),
  ('bsb_open_play_lane_end_reason','MOVED,RELEASED,SESSION_ENDED'),
  ('bsb_booking_type','PRE_POST'),
  ('bsb_booking_status','CANCELLED,SCHEDULED,STARTED')
),
checks as (
  select '01 required tables' check_name,
    not exists(select 1 from required_tables r where to_regclass('public.'||r.name) is null) ok,
    coalesce((select string_agg(name,', ') from required_tables r where to_regclass('public.'||r.name) is null),'all present') detail
  union all
  select '02 required columns',
    not exists(select 1 from required_columns r left join information_schema.columns c on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name where c.column_name is null),
    coalesce((select string_agg(r.table_name||'.'||r.column_name,', ') from required_columns r left join information_schema.columns c on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name where c.column_name is null),'all present')
  union all
  select '03 enum values',
    not exists(select 1 from enum_expectations x left join (select t.typname, string_agg(e.enumlabel,',' order by e.enumlabel) actual from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' group by t.typname) a on a.typname=x.type_name where a.actual is distinct from x.expected),
    coalesce((select string_agg(x.type_name||' expected ['||x.expected||'] got ['||coalesce(a.actual,'missing')||']','; ') from enum_expectations x left join (select t.typname, string_agg(e.enumlabel,',' order by e.enumlabel) actual from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' group by t.typname) a on a.typname=x.type_name where a.actual is distinct from x.expected),'all match')
  union all
  select '04 RLS enabled',
    not exists(select 1 from required_tables r left join pg_class c on c.oid=to_regclass('public.'||r.name) where not coalesce(c.relrowsecurity,false)),
    coalesce((select string_agg(r.name,', ') from required_tables r left join pg_class c on c.oid=to_regclass('public.'||r.name) where not coalesce(c.relrowsecurity,false)),'enabled on all required tables')
  union all
  select '05 direct browser table writes/reads restricted',
    not exists(select 1 from required_tables r where coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'DELETE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'DELETE'),false)),
    coalesce((select string_agg(r.name,', ') from required_tables r where coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'DELETE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'DELETE'),false)),'no direct browser table privileges')
  union all
  select '06 browser RPCs exist and anon can execute',
    not exists(select 1 from browser_rpcs r where to_regprocedure('public.'||r.signature) is null or not coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),
    coalesce((select string_agg(signature,', ') from browser_rpcs r where to_regprocedure('public.'||r.signature) is null or not coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),'all callable')
  union all
  select '07 internal helpers not browser callable',
    not exists(select 1 from internal_helpers r where to_regprocedure('public.'||r.signature) is null or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false) or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),
    coalesce((select string_agg(signature,', ') from internal_helpers r where to_regprocedure('public.'||r.signature) is null or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false) or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),'all present and restricted')
  union all
  select '08 Blue Springs Bowl organization', count(*)=1, count(*)||' matching organization row(s)' from public.organizations where slug='blue-springs-bowl'
  union all
  select '09 active OWNER', count(*)>=1, count(*)||' active owner(s)' from public.employees e join public.organizations o on o.id=e.organization_id where o.slug='blue-springs-bowl' and e.active and e.role='OWNER'
  union all
  select '10 active authorized device', count(*)>=1, count(*)||' active authorized device(s)' from public.authorized_devices d join public.organizations o on o.id=d.organization_id where o.slug='blue-springs-bowl' and d.active
  union all
  select '11 required operational indexes',
    not exists(select 1 from required_indexes r left join pg_class c on c.relname=r.name and c.relkind='i' left join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where c.oid is null or n.oid is null),
    coalesce((select string_agg(r.name,', ') from required_indexes r left join pg_class c on c.relname=r.name and c.relkind='i' left join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where c.oid is null or n.oid is null),'all present')
  union all
  select '12 required lifecycle constraints',
    not exists(select 1 from required_constraints r left join pg_constraint c on c.conrelid=to_regclass('public.'||r.table_name) and c.conname=r.name where c.oid is null),
    coalesce((select string_agg(r.table_name||'.'||r.name,', ') from required_constraints r left join pg_constraint c on c.conrelid=to_regclass('public.'||r.table_name) and c.conname=r.name where c.oid is null),'all present')
  union all
  select '13 closed-night barrier triggers',
    not exists(select 1 from required_triggers r left join pg_trigger t on t.tgrelid=to_regclass('public.'||r.table_name) and t.tgname=r.name and not t.tgisinternal where t.oid is null or not t.tgenabled in ('O','A')),
    coalesce((select string_agg(r.table_name||'.'||r.name,', ') from required_triggers r left join pg_trigger t on t.tgrelid=to_regclass('public.'||r.table_name) and t.tgname=r.name and not t.tgisinternal where t.oid is null or not t.tgenabled in ('O','A')),'both enabled')
  union all
  select '14 no unresolved sessions in closed nights', count(*)=0, count(*)||' violating session(s)'
    from public.open_play_sessions s join public.business_nights n on n.id=s.night_id
    where n.status='CLOSED' and s.status in ('ACTIVE','AWAITING_CLOSE')
  union all
  select '15 no active assignments in closed nights', count(*)=0, count(*)||' violating assignment(s)'
    from public.open_play_lane_assignments a join public.business_nights n on n.id=a.night_id
    where n.status='CLOSED' and a.ended_at is null
  union all
  select '16 active assignments belong to active sessions', count(*)=0, count(*)||' violating assignment(s)'
    from public.open_play_lane_assignments a join public.open_play_sessions s on s.id=a.session_id
    where a.ended_at is null and s.status<>'ACTIVE'
  union all
  select '17 organization/night/session ownership matches', count(*)=0, count(*)||' mismatched row(s)'
    from (
      select s.id from public.open_play_sessions s join public.business_nights n on n.id=s.night_id
        where s.organization_id<>n.organization_id
      union all
      select a.id from public.open_play_lane_assignments a
        join public.open_play_sessions s on s.id=a.session_id
        join public.business_nights n on n.id=a.night_id
        where a.organization_id<>s.organization_id or a.night_id<>s.night_id
          or a.organization_id<>n.organization_id or s.organization_id<>n.organization_id
    ) mismatches
  union all
  select '18 completed Open Bowling has payment', count(*)=0, count(*)||' completed session(s) missing payment'
    from public.open_play_sessions s where s.status='COMPLETED' and s.type='OPEN_BOWLING'
      and (not (s.data->'pricing' ? 'chargedTotalCents') or s.data->'pricing'->'chargedTotalCents'='null'::jsonb)
  union all
  select '19 every organization has an active OWNER', count(*)=0, count(*)||' organization(s) without an active owner'
    from public.organizations o where not exists(select 1 from public.employees e where e.organization_id=o.id and e.active and e.role='OWNER')
  union all
  select '20 internal helpers denied to PUBLIC and browser roles',
    not exists(select 1 from internal_helpers r where to_regprocedure('public.'||r.signature) is null
      or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)
      or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)
      or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.'||r.signature) and a.grantee=0 and a.privilege_type='EXECUTE')),
    coalesce((select string_agg(signature,', ') from internal_helpers r where to_regprocedure('public.'||r.signature) is null
      or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)
      or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)
      or exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.'||r.signature) and a.grantee=0 and a.privilege_type='EXECUTE')),'all present and restricted')
  union all
  select '21 SECURITY DEFINER search paths fixed', count(*)=0, count(*)||' function(s) missing public, pg_temp search_path'
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and not coalesce(p.proconfig,'{}'::text[]) @> array['search_path=public, pg_temp']
  union all
  select '22 booking structural constraints',
    (select count(*) from pg_constraint c where c.conrelid=to_regclass('public.open_play_bookings') and c.contype='c'
      and (pg_get_constraintdef(c.oid) ilike '%lanes_needed >= 1%' or pg_get_constraintdef(c.oid) ilike '%lanes_needed%between 1 and 12%'))>=1
    and (select count(*) from pg_constraint c where c.conrelid=to_regclass('public.open_play_bookings') and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%status%SCHEDULED%' and pg_get_constraintdef(c.oid) ilike '%resulting_session_id%')>=1,
    'requires 1-12 lanes and status/resulting-session lifecycle consistency'
  union all
  select '23 started bookings have a resulting session', count(*)=0, count(*)||' violating booking(s)'
    from public.open_play_bookings b where b.status='STARTED' and b.resulting_session_id is null
  union all
  select '24 unstarted bookings have no resulting session', count(*)=0, count(*)||' violating booking(s)'
    from public.open_play_bookings b where b.status in ('SCHEDULED','CANCELLED') and b.resulting_session_id is not null
  union all
  select '25 booking/session organization matches', count(*)=0, count(*)||' mismatched booking/session row(s)'
    from public.open_play_bookings b join public.open_play_sessions s on s.id=b.resulting_session_id
    where b.organization_id<>s.organization_id or b.status<>'STARTED' or s.type<>'PRE_POST'
  union all
  select '26 booking activity ownership matches', count(*)=0, count(*)||' mismatched booking activity row(s)'
    from public.open_play_booking_activity a join public.open_play_bookings b on b.id=a.booking_id
    where a.organization_id<>b.organization_id
)
select check_name, case when ok then 'PASS' else 'FAIL' end status, detail
from checks order by check_name;
