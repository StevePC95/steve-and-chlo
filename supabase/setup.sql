-- Steve & Chlo: database setup. Run once in Supabase: SQL Editor > New query > paste all > Run.
-- One table of household items. The app never touches tables directly: every read and write
-- goes through the functions below, and each one checks the shared code first.
-- The code itself is chosen in the app the first time it is opened, and stored here hashed.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.sc_secret (
  id int primary key check (id = 1),
  code_hash text not null,
  set_at timestamptz not null default now()
);
alter table public.sc_secret enable row level security;

create table if not exists public.sc_items (
  kind text not null check (kind in ('meals','plan','ticks','extras','todos','chores','ideas','notes','counts')),
  id text not null check (length(id) between 1 and 100),
  data jsonb not null default '{}'::jsonb check (pg_column_size(data) < 20000),
  updated_at timestamptz not null default now(),
  primary key (kind, id)
);
alter table public.sc_items enable row level security;
-- No policies on purpose: nobody reads or writes these tables except through the functions.

create or replace function public.sc_ok(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select code_hash into h from sc_secret where id = 1;
  if h is null or p_code is null then return false; end if;
  if crypt(p_code, h) = h then return true; end if;
  perform pg_sleep(1.5);  -- slow down guessing
  return false;
end $$;

create or replace function public.sc_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('setup', exists (select 1 from sc_secret where id = 1));
$$;

-- Works once only: the first person to open the app chooses the code.
create or replace function public.sc_setup(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from sc_secret where id = 1) then raise exception 'already_set'; end if;
  if p_code is null or length(p_code) < 6 or length(p_code) > 72 then raise exception 'code_too_short'; end if;
  insert into sc_secret (id, code_hash) values (1, crypt(p_code, gen_salt('bf', 6)));
  return true;
end $$;

create or replace function public.sc_check(p_code text) returns boolean
language sql security definer set search_path = public as $$ select sc_ok(p_code); $$;

create or replace function public.sc_all(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('k', kind, 'id', id, 'd', data)) from sc_items), '[]'::jsonb);
end $$;

create or replace function public.sc_put(p_code text, p_kind text, p_id text, p_data jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  if (select count(*) from sc_items) > 5000 then raise exception 'full'; end if;
  insert into sc_items (kind, id, data) values (p_kind, p_id, coalesce(p_data, '{}'::jsonb))
  on conflict (kind, id) do update set data = excluded.data, updated_at = now();
  return true;
end $$;

create or replace function public.sc_patch(p_code text, p_kind text, p_id text, p_data jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  update sc_items set data = data || coalesce(p_data, '{}'::jsonb), updated_at = now() where kind = p_kind and id = p_id;
  return found;
end $$;

create or replace function public.sc_del(p_code text, p_kind text, p_id text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not sc_ok(p_code) then raise exception 'bad_code' using errcode = '28P01'; end if;
  delete from sc_items where kind = p_kind and id = p_id;
  return true;
end $$;

-- Only the app-facing functions are callable from the website; sc_ok stays internal.
revoke all on function public.sc_ok(text) from public, anon, authenticated;
grant execute on function public.sc_status(), public.sc_setup(text), public.sc_check(text), public.sc_all(text),
  public.sc_put(text,text,text,jsonb), public.sc_patch(text,text,text,jsonb), public.sc_del(text,text,text) to anon, authenticated;

-- To change the shared code later (both phones then ask for the new one):
--   update public.sc_secret set code_hash = extensions.crypt('new-code-here', extensions.gen_salt('bf', 6)) where id = 1;
