-- Minimal stand-ins for the parts of a Supabase database the migrations touch.
--
-- Exists so the schema and the RLS suite can be run against a throwaway local
-- Postgres, with no project and no Docker. It is NEVER applied to a real
-- project — Supabase provides all of this itself.
--
-- Only what the migrations actually reference is modelled: the auth.users
-- columns the signup trigger reads, auth.uid(), the storage tables, and
-- storage.foldername().

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end;
$$;

create schema if not exists auth;
create schema if not exists storage;

grant usage on schema public, auth, storage to anon, authenticated, service_role;

create table if not exists auth.users (
  instance_id uuid,
  id uuid primary key default gen_random_uuid(),
  aud text,
  role text,
  email text unique,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb default '{}'::jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- The identity PostgREST injects per request, read the same way Supabase does.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    current_setting('request.jwt.claims', true)::jsonb ->> 'sub',
    ''
  )::uuid;
$$;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz default now()
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets,
  name text,
  owner uuid,
  metadata jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table storage.objects enable row level security;

-- Supabase's version returns the path segments with the filename dropped, so
-- 'group/bill/receipt.jpg' becomes {group,bill} and [1] is the scoping id.
create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  select (string_to_array(name, '/'))[1:greatest(
    array_length(string_to_array(name, '/'), 1) - 1, 0
  )];
$$;

grant select, insert, update, delete on storage.objects to authenticated;
grant select on storage.buckets to authenticated;

-- Current Supabase projects do NOT auto-grant DML on `public` to the API
-- roles: the default privileges carry only TRUNCATE, REFERENCES, TRIGGER and
-- MAINTAIN (the `Dxtm` in pg_default_acl). SELECT/INSERT/UPDATE/DELETE must be
-- granted explicitly, which `20260925000007_grants.sql` does.
--
-- Reproduced exactly here. An earlier version of this shim granted ALL, which
-- masked the missing grants until the schema hit a real project — every query
-- would have failed with "permission denied". Mirror production, or the suite
-- lies.
alter default privileges in schema public
  grant truncate, references, trigger on tables to anon, authenticated, service_role;
