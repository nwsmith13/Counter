-- Corrects the regular expression deployed in 202609210002.  PostgreSQL
-- regular expressions use a single backslash for the digit class.
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
