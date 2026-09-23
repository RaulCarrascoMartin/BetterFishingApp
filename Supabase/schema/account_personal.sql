-- account_personal.sql
-- Provisioning del dominio de cuenta personal (spec account-personal, tarea 1.1).
-- Idempotente y re-ejecutable: create extension if not exists / create table
-- if not exists / create policy ... (se asume ejecución única en instancia
-- nueva; la política, a diferencia de spot-discovery, no se re-ejecuta con
-- drop policy forzado para conservar el DDL del design.md).
-- Depende del esquema `auth` de Supabase (auth.users/auth.uid) y de pgcrypto.

create extension if not exists pgcrypto;

-- NOTA (provisioning fuera del SQL, tarea 1.1): los buckets `avatars` y
-- `catches` se provisionan desde el dashboard/CLI de Supabase con políticas
-- de acceso a nivel de objeto por `user_id` (RLS de objeto: solo el dueño
-- lee/escribe sus objetos bajo `{user_id}/...`). No se crean aquí.

-- ===========================================================================
-- Tabla public.profiles
-- ===========================================================================
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  updated_at timestamptz not null default now()
);

-- ===========================================================================
-- Favoritos: NO se definen aquí.
-- La tabla `spot_favorites`, sus índices, RLS y RPC
-- (my_favorite_* / add_spot_favorite / remove_spot_favorite) son propiedad de
-- spot-discovery; account-personal solo los consume vía `SpotRepository`.
-- ===========================================================================

-- ===========================================================================
-- Tabla public.catches (id = Catch.id)
-- ===========================================================================
create table if not exists public.catches (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  species jsonb not null,
  date timestamptz not null,
  location jsonb,
  notes text not null default '',
  created_at timestamptz not null,
  updated_at timestamptz not null default now(),
  photo_path text,
  unique (id, user_id)
);
create index if not exists catches_user_id_idx on public.catches (user_id);

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table public.profiles enable row level security;
alter table public.catches enable row level security;

create policy profiles_own on public.profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy catches_own on public.catches
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ===========================================================================
-- RPCs
-- ===========================================================================
create or replace function public.upsert_profile(
  p_user_id uuid, p_display_name text, p_avatar_path text, p_updated_at timestamptz default now()
) returns void
language sql security invoker set search_path = public
as $$
  insert into public.profiles (user_id, display_name, avatar_path, updated_at)
  values (p_user_id, p_display_name, p_avatar_path, p_updated_at)
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    avatar_path = excluded.avatar_path,
    updated_at = excluded.updated_at
  where public.profiles.user_id = auth.uid()
$$;

create or replace function public.upsert_catch(p_user_id uuid, p_catch text)
returns void
language plpgsql security invoker set search_path = public
as $$
declare c jsonb := p_catch::jsonb;
begin
  insert into public.catches (id, user_id, species, date, location, notes, created_at, photo_path)
  values (
    (c ->> 'id')::uuid,
    p_user_id,
    c -> 'species',
    (c ->> 'date')::timestamptz,
    c -> 'location',
    coalesce(c ->> 'notes', ''),
    (c ->> 'createdAt')::timestamptz,
    c ->> 'photoPath'
  )
  on conflict (id) do update set
    species = excluded.species,
    date = excluded.date,
    location = excluded.location,
    notes = excluded.notes,
    photo_path = excluded.photo_path,
    updated_at = now()
  where public.catches.user_id = auth.uid();
end $$;