-- 001_spot_discovery_init.sql
-- Provisioning del dominio de spots (spec spot-discovery, tarea 1.1).
-- Idempotente y re-ejecutable: create if not exists / create or replace /
-- drop policy if exists + revoke/grant explícitos.
-- Depende de la extensión PostGIS y del esquema `auth` de Supabase (auth.users/auth.uid).

create extension if not exists postgis;

-- ===========================================================================
-- Tabla public.spots
-- ===========================================================================
create table if not exists public.spots (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  summary text not null default '',
  geom geometry(Point,4326) not null,
  longitude double precision not null,
  latitude double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.spots is
  'Spots de pesca curados. Geografía en WGS84 (SRID 4326).';
comment on column public.spots.geom is
  'Geometría de punto WGS84 (SRID 4326); unidades en grados decimales.';
comment on column public.spots.longitude is
  'Longitud en grados decimales (WGS84); coherente con geom.';
comment on column public.spots.latitude is
  'Latitud en grados decimales (WGS84); coherente con geom.';

create index if not exists spots_geom_gix on public.spots using gist (geom);

-- ===========================================================================
-- Tabla public.spot_favorites
-- ===========================================================================
create table if not exists public.spot_favorites (
  spot_id uuid not null references public.spots(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (spot_id, user_id)
);

comment on table public.spot_favorites is
  'Favoritos de spots asociados a cuentas (auth.users). Acceso restringido por RLS a auth.uid() = user_id.';

create index if not exists spot_favorites_user_idx on public.spot_favorites (user_id);

-- ===========================================================================
-- Row Level Security
-- ===========================================================================
alter table public.spots enable row level security;
alter table public.spot_favorites enable row level security;

drop policy if exists spots_select on public.spots;
create policy spots_select on public.spots
  for select using (true);

drop policy if exists spot_favorites_select on public.spot_favorites;
create policy spot_favorites_select on public.spot_favorites
  for select using (auth.uid() = user_id);

drop policy if exists spot_favorites_insert on public.spot_favorites;
create policy spot_favorites_insert on public.spot_favorites
  for insert with check (auth.uid() = user_id);

drop policy if exists spot_favorites_delete on public.spot_favorites;
create policy spot_favorites_delete on public.spot_favorites
  for delete using (auth.uid() = user_id);

-- ===========================================================================
-- Funciones RPC
-- ===========================================================================
-- nearby_spots: devuelve spots dentro de `radius_km` ordenados por distancia
-- ascendente. La distancia se calcula sobre geography; `distance_m` está en
-- metros. Parámetros de ubicación en grados decimales (WGS84).
create or replace function public.nearby_spots(lat double precision, lng double precision, radius_km double precision)
returns table (id uuid, name text, category text, summary text, longitude double precision, latitude double precision, distance_m double precision)
language sql stable security definer
set search_path = public
as $fn$
  select s.id, s.name, s.category, s.summary, s.longitude, s.latitude,
         st_distance(s.geom::geography,
                     st_setsrid(st_makepoint(lng, lat), 4326)::geography) as distance_m
  from public.spots s
  where st_dwithin(s.geom::geography,
                   st_setsrid(st_makepoint(lng, lat), 4326)::geography,
                   radius_km * 1000)
  order by distance_m asc;
$fn$;

comment on function public.nearby_spots(double precision, double precision, double precision) is
  'Spots dentro del radio (búfer sobre geography, radius_km * 1000 metros) ordenados por distancia creciente; distance_m en metros, ubicación en grados decimales (WGS84).';

create or replace function public.my_favorite_spot_ids()
returns table (spot_id uuid)
language sql stable security definer
set search_path = public
as $fn$
  select f.spot_id
  from public.spot_favorites f
  where f.user_id = auth.uid();
$fn$;

comment on function public.my_favorite_spot_ids() is
  'Ids de los favoritos del usuario autenticado (auth.uid()). Sin sesión devuelve conjunto vacío.';

create or replace function public.my_favorite_spots()
returns table (id uuid, name text, category text, summary text, longitude double precision, latitude double precision)
language sql stable security definer
set search_path = public
as $fn$
  select s.id, s.name, s.category, s.summary, s.longitude, s.latitude
  from public.spot_favorites f
  join public.spots s on s.id = f.spot_id
  where f.user_id = auth.uid()
  order by f.created_at desc;
$fn$;

comment on function public.my_favorite_spots() is
  'Spots favoritos del usuario autenticado (auth.uid()), misma forma de fila que spots.';

create or replace function public.add_spot_favorite(spot_id uuid)
returns void
language sql volatile security definer
set search_path = public
as $fn$
  insert into public.spot_favorites (spot_id, user_id)
  values (spot_id, auth.uid())
  on conflict do nothing;
$fn$;

comment on function public.add_spot_favorite(uuid) is
  'Marca el spot como favorito del usuario autenticado (auth.uid()); idempotente (ON CONFLICT DO NOTHING).';

create or replace function public.remove_spot_favorite(spot_id uuid)
returns void
language sql volatile security definer
set search_path = public
as $fn$
  delete from public.spot_favorites
  where public.spot_favorites.spot_id = $1 and user_id = auth.uid();
$fn$;

comment on function public.remove_spot_favorite(uuid) is
  'Quita el spot de los favoritos del usuario autenticado (auth.uid()).';

-- ===========================================================================
-- Permisos
-- ===========================================================================
grant usage on schema public to anon, authenticated;

revoke all on table public.spots from anon, authenticated;
revoke all on table public.spot_favorites from anon, authenticated;
revoke all on function public.nearby_spots(double precision, double precision, double precision) from public;
revoke all on function public.my_favorite_spot_ids() from public;
revoke all on function public.my_favorite_spots() from public;
revoke all on function public.add_spot_favorite(uuid) from public;
revoke all on function public.remove_spot_favorite(uuid) from public;

grant select on table public.spots to anon, authenticated;
grant execute on function public.nearby_spots(double precision, double precision, double precision) to anon, authenticated;
grant execute on function public.my_favorite_spot_ids() to authenticated;
grant execute on function public.my_favorite_spots() to authenticated;
grant execute on function public.add_spot_favorite(uuid) to authenticated;
grant execute on function public.remove_spot_favorite(uuid) to authenticated;

-- ===========================================================================
-- Semilla curada de spots (tarea 1.2)
-- ===========================================================================
-- 18 spots de pesca realistas alrededor de Cataluña y el litoral peninsular.
-- Categorías del dominio (design.md, SpotCategory): river, lake, sea, shore.
-- Idempotente: on conflict (name) do nothing; se exige unicidad de `name`
-- (create unique index if not exists) para que el conflicto sea efectivo al
-- re-ejecutar todo el fichero.
create unique index if not exists spots_name_uidx on public.spots (name);

insert into public.spots (name, category, summary, longitude, latitude, geom) values
  ('Embalse de Sau', 'lake',
   'Río Ter embalsado en Osona; aguas abiertas y profundas.',
   2.2486, 42.0037, st_setsrid(st_makepoint(2.2486, 42.0037), 4326)),
  ('Pantano de la Tierra Alta', 'lake',
   'Recorrido amplio de la Tierra Alta, tranquilo y alejado.',
   0.4210, 41.1060, st_setsrid(st_makepoint(0.4210, 41.1060), 4326)),
  ('Platja de la Barceloneta', 'shore',
   'Orilla urbana de Barcelona con fácil acceso desde la ciudad.',
   2.1905, 41.3783, st_setsrid(st_makepoint(2.1905, 41.3783), 4326)),
  ('Desembocadura del Besòs', 'river',
   'Curso bajo del Besòs donde se junta con el mar.',
   2.2316, 41.4118, st_setsrid(st_makepoint(2.2316, 41.4118), 4326)),
  ('Port de Barcelona (Moll de Pescadors)', 'sea',
   'Zona portuaria de pesca con corriente y mar abierto.',
   2.1815, 41.3690, st_setsrid(st_makepoint(2.1815, 41.3690), 4326)),
  ('Platja de Badalona', 'shore',
   'Largo paseo marítimo al norte de Barcelona.',
   2.2470, 41.4496, st_setsrid(st_makepoint(2.2470, 41.4496), 4326)),
  ('Delta del Llobregat', 'shore',
   'Desembocadura protegida junto al Prat, muy cambiante.',
   2.1266, 41.2832, st_setsrid(st_makepoint(2.1266, 41.2832), 4326)),
  ('Riu Llobregat a Sant Boi', 'river',
   'Tramo tranquilo del Llobregat antes de la llanura deltaica.',
   2.0343, 41.3441, st_setsrid(st_makepoint(2.0343, 41.3441), 4326)),
  ('Platja de Castelldefels', 'shore',
   'Orilla amplia al sur de Barcelona, ideal desde la arena.',
   1.9797, 41.2480, st_setsrid(st_makepoint(1.9797, 41.2480), 4326)),
  ('Riu Anoia a Martorell', 'river',
   'Tramo fluvial del Anoia antes de verter al Llobregat.',
   1.8480, 41.4950, st_setsrid(st_makepoint(1.8480, 41.4950), 4326)),
  ('Riu Tordera a Sant Celoni', 'river',
   'Río de montaña de la falda del Montseny, de poca profundidad.',
   2.5490, 41.6960, st_setsrid(st_makepoint(2.5490, 41.6960), 4326)),
  ('Pantà de Vallforners', 'lake',
   'Embalse pequeño entre el Montseny y el Corredor.',
   2.5480, 41.7260, st_setsrid(st_makepoint(2.5480, 41.7260), 4326)),
  ('Pantà de Boadella', 'lake',
   'Embalse del río Muga en la Alta Empordà.',
   2.8167, 42.3333, st_setsrid(st_makepoint(2.8167, 42.3333), 4326)),
  ('Estany de Banyoles', 'lake',
   'Lago natural más grande de Cataluña, con aguas claras.',
   2.7556, 42.1188, st_setsrid(st_makepoint(2.7556, 42.1188), 4326)),
  ('Delta de l''Ebre (Port del Fangar)', 'sea',
   'Bahía del delta del Ebro abierta al Mediterráneo.',
   0.8333, 40.7333, st_setsrid(st_makepoint(0.8333, 40.7333), 4326)),
  ('Cap de Creus', 'sea',
   'Fondos rocosos y corrientes de la punta nordeste.',
   3.2250, 42.3180, st_setsrid(st_makepoint(3.2250, 42.3180), 4326)),
  ('Platja de Cambrils', 'shore',
   'Orilla de la Costa Daurada con zona de pesca deportiva.',
   1.0895, 41.0700, st_setsrid(st_makepoint(1.0895, 41.0700), 4326)),
  ('Riu Segre a Lleida', 'river',
   'Tramo urbano del Segre, estable y céntrico.',
   0.6250, 41.6167, st_setsrid(st_makepoint(0.6250, 41.6167), 4326))
on conflict (name) do nothing;