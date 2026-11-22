-- Steve & Chlo: push reminders (added 22 Nov 2026). Runs after setup.sql.
-- How it works: reminders live in sc_items (kind 'reminders'). Every minute pg_cron runs sc_push_tick(),
-- which works out which reminders are due (Johannesburg time), queues one message per phone in
-- sc_push_out, and pings the Edge Function `sc-push`, which encrypts and sends them (Web Push).
-- Phones register in sc_push_subs when someone taps "Turn on reminders on this phone".
-- Secrets live in Supabase Vault, never in this repo: 'sc_cron_key' (guards the Edge Function) and
-- 'sc_vapid' ({"jwk":{...},"pub":"..."}, the push signing key; its public half is in config.js).

create extension if not exists pg_cron;
create extension if not exists pg_net;

alter table public.sc_items drop constraint if exists sc_items_kind_check;
alter table public.sc_items add constraint sc_items_kind_check check (kind in
  ('meals','plan','ticks','extras','todos','chores','ideas','notes','counts','events','reminders'));

create table if not exists public.sc_push_subs (
  endpoint text primary key check (endpoint like 'https://%' and length(endpoint) < 1000),
  who text not null check (who in ('steve','chlo')),
  keys jsonb not null,
  created_at timestamptz not null default now(),
  last_ok timestamptz,
  last_err text
);
alter table public.sc_push_subs enable row level security;

create table if not exists public.sc_push_out (
  id bigserial primary key,
  endpoint text not null,
  keys jsonb not null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.sc_push_out enable row level security;
-- No policies on either table: only the functions below touch them.

-- Ping the sender. Internal only.
create or replace function public.sc_push_kick() returns void
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'sc_cron_key';
  if k is null then return; end if;
  perform net.http_post(
    url := 'https://hlmxrxqddorntteyqowu.supabase.co/functions/v1/sc-push',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sc-key', k),
    timeout_milliseconds := 30000);
end $$;

-- The day `dm` in the month containing `x` (31 becomes the month's last day).
create or replace function public.sc_month_day(x date, dm int) returns date
language sql immutable as $$
  select (date_trunc('month', x)::date + least(dm, extract(day from (date_trunc('month', x) + interval '1 month - 1 day'))::int) - 1);
$$;

-- Queue every reminder that is due now. Called by pg_cron every minute.
create or replace function public.sc_push_tick() returns int
language plpgsql security definer set search_path = public as $$
declare
  loc timestamp := now() at time zone 'Africa/Johannesburg';
  d date := (now() at time zone 'Africa/Johannesburg')::date;
  r record; st date; t time; occ timestamp; k text; n int := 0; c int;
begin
  for r in select id, data from sc_items where kind = 'reminders' for update loop
    continue when coalesce(r.data->>'off', '') in ('true', '1');
    begin
      st := (r.data->>'date')::date; t := (r.data->>'time')::time;
    exception when others then continue;
    end;
    continue when st is null or t is null;
    case coalesce(r.data->>'rep', '')
      when '' then occ := st + t;
      when 'day' then occ := d + t;
        if occ > loc then occ := occ - interval '1 day'; end if;
      when 'week' then occ := (d - ((extract(dow from d)::int - extract(dow from st)::int + 7) % 7)) + t;
        if occ > loc then occ := occ - interval '7 days'; end if;
      when 'month' then occ := sc_month_day(d, extract(day from st)::int) + t;
        if occ > loc then occ := sc_month_day((date_trunc('month', d) - interval '1 day')::date, extract(day from st)::int) + t; end if;
      else continue;
    end case;
    -- Due = in the last 2 hours, not before the start date, not already sent.
    continue when occ > loc or occ <= loc - interval '2 hours' or occ::date < st;
    k := to_char(occ, 'YYYY-MM-DD"T"HH24:MI');
    continue when coalesce(r.data->>'last', '') >= k;
    update sc_items set data = data || jsonb_build_object('last', k), updated_at = now()
      where kind = 'reminders' and id = r.id;
    insert into sc_push_out (endpoint, keys, payload)
      select s.endpoint, s.keys, jsonb_build_object(
        'title', coalesce(nullif(r.data->>'t', ''), 'Reminder'),
        'body', coalesce(r.data->>'note', ''),
        'url', coalesce(nullif(r.data->>'go', ''), '#today'),
        'tag', 'sc-' || r.id)
      from sc_push_subs s
      where coalesce(r.data->>'who', 'both') not in ('steve', 'chlo') or s.who = r.data->>'who';
    get diagnostics c = row_count; n := n + c;
  end loop;
  if exists (select 1 from sc_push_out) then perform sc_push_kick(); end if;
  return n;
end $$;

-- Used by the Edge Function (service role): check the ping's key, then hand over the queue and the push key.
create or replace function public.sc_push_take(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare out jsonb; k text; v text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'sc_cron_key';
  if k is null or p_key is distinct from k then raise exception 'bad_key'; end if;
  select decrypted_secret into v from vault.decrypted_secrets where name = 'sc_vapid';
  delete from sc_push_out where created_at < now() - interval '2 hours';
  with t as (delete from sc_push_out where id > 0 returning endpoint, keys, payload)  -- PostgREST needs a WHERE
  select coalesce(jsonb_agg(jsonb_build_object('endpoint', endpoint, 'keys', keys, 'payload', payload)), '[]'::jsonb) into out from t;
  return jsonb_build_object('jobs', out, 'vapid', v::jsonb);
end $$;

create or replace function public.sc_push_result(p_results jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare x jsonb;
begin
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if (x->>'status')::int in (404, 410) then
      delete from sc_push_subs where endpoint = x->>'endpoint';       -- phone unsubscribed or app removed
    elsif (x->>'status')::int between 200 and 299 then
      update sc_push_subs set last_ok = now(), last_err = null where endpoint = x->>'endpoint';
    else
      update sc_push_subs set last_err = left((x->>'status') || ' ' || coalesce(x->>'text', ''), 200) where endpoint = x->>'endpoint';
    end if;
  end loop;
end $$;

-- App-facing (each checks the shared code).
create or replace function public.sc_push_save(p_code text, p_who text, p_endpoint text, p_keys jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  if p_who not in ('steve', 'chlo') or p_keys->>'p256dh' is null or p_keys->>'auth' is null then raise exception 'bad_sub'; end if;
  if (select count(*) from sc_push_subs) >= 20 and not exists (select 1 from sc_push_subs where endpoint = p_endpoint) then raise exception 'full'; end if;
  insert into sc_push_subs (endpoint, who, keys) values (p_endpoint, p_who, jsonb_build_object('p256dh', p_keys->>'p256dh', 'auth', p_keys->>'auth'))
  on conflict (endpoint) do update set who = excluded.who, keys = excluded.keys, last_err = null;
  return true;
end $$;

create or replace function public.sc_push_drop(p_code text, p_endpoint text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  delete from sc_push_subs where endpoint = p_endpoint;
  return true;
end $$;

-- Sends a test push to one phone straight away.
create or replace function public.sc_push_test(p_code text, p_endpoint text) returns boolean
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  select * into s from sc_push_subs where endpoint = p_endpoint;
  if not found then return false; end if;
  insert into sc_push_out (endpoint, keys, payload) values (s.endpoint, s.keys, jsonb_build_object(
    'title', 'Reminders are on', 'body', 'This phone will get ' || initcap(s.who) || '''s reminders.', 'url', '#todo', 'tag', 'sc-test'));
  perform sc_push_kick();
  return true;
end $$;

-- How many phones each of you has turned on, and this phone's last problem if any.
create or replace function public.sc_push_phones(p_code text, p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  return jsonb_build_object(
    'steve', (select count(*) from sc_push_subs where who = 'steve'),
    'chlo', (select count(*) from sc_push_subs where who = 'chlo'),
    'mine', (select jsonb_build_object('who', who, 'ok', last_ok, 'err', last_err, 'seen', last_seen) from sc_push_subs where endpoint = p_endpoint));
end $$;

revoke all on function public.sc_push_kick(), public.sc_push_tick(), public.sc_push_take(text), public.sc_push_result(jsonb)
  from public, anon, authenticated;
grant execute on function public.sc_push_take(text), public.sc_push_result(jsonb) to service_role;
revoke all on function public.sc_month_day(date,int) from public, anon, authenticated;
revoke all on function public.sc_push_save(text,text,text,jsonb), public.sc_push_drop(text,text),
  public.sc_push_test(text,text), public.sc_push_phones(text,text) from public;
grant execute on function public.sc_push_save(text,text,text,jsonb), public.sc_push_drop(text,text),
  public.sc_push_test(text,text), public.sc_push_phones(text,text) to anon, authenticated;

-- Every minute. To pause all reminders: select cron.unschedule('sc-push');
select cron.schedule('sc-push', '* * * * *', 'select public.sc_push_tick()');

-- Phones report back when a push arrives (sw.js calls this), so "not delivered" and "hidden" can be told apart.
alter table public.sc_push_subs add column if not exists last_seen timestamptz;
alter table public.sc_push_subs add column if not exists seen_err text;
create or replace function public.sc_push_seen(p_endpoint text, p_err text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  -- The endpoint is a long unguessable URL only that phone knows, so it acts as its own key.
  update sc_push_subs set last_seen = now(), seen_err = left(p_err, 200) where endpoint = p_endpoint;
end $$;
revoke all on function public.sc_push_seen(text, text) from public;
grant execute on function public.sc_push_seen(text, text) to anon, authenticated;
-- sc_push_phones also returns 'seen' (last_seen) for this phone since 22 Nov.
