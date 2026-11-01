-- Fase 1: perfiles de usuario y límites de planes.

create extension if not exists pgcrypto;

-- Planes ---------------------------------------------------------------------

create type public.plan_tipo as enum ('free', 'premium');

-- Límites configurables por plan. Se leen desde la app y desde funciones SQL;
-- cambiar un límite es un UPDATE, no un deploy.
create table public.plan_limits (
  plan                 public.plan_tipo primary key,
  storage_bytes        bigint not null,
  versiones_visibles   integer,          -- null = historial completo
  reporte_pdf          boolean not null default false
);

insert into public.plan_limits (plan, storage_bytes, versiones_visibles, reporte_pdf) values
  ('free',    500::bigint * 1024 * 1024, 3,    false),
  ('premium', 10::bigint * 1024 * 1024 * 1024, null, true);

alter table public.plan_limits enable row level security;

create policy "plan_limits: lectura para usuarios autenticados"
  on public.plan_limits for select
  to authenticated
  using (true);

-- Perfiles -------------------------------------------------------------------

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nombre      text not null check (char_length(trim(nombre)) between 1 and 80),
  avatar_url  text,
  plan        public.plan_tipo not null default 'free',
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- La visibilidad entre integrantes del mismo grupo se agrega en la fase 2.
create policy "profiles: ver el propio"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()));

create policy "profiles: editar el propio"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- El plan lo cambia solo el backend (pagos), nunca el cliente.
revoke update on public.profiles from authenticated;
grant update (nombre, avatar_url) on public.profiles to authenticated;

-- Crea el perfil al registrarse. Toma el nombre de los metadatos del registro
-- (email/contraseña) o del proveedor (Google); si no hay, usa el email.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nombre, avatar_url)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(new.email, '@', 1)
    ), 80),
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
