-- Bloqueos flexibles: menos espera para el resto del grupo.
--
--   * Quien bloquea elige la duración (por defecto 2 h, máximo 24 h) y puede renovarla.
--   * Los demás pueden pedirle que lo libere (lock_requests): le llega en vivo.
--   * Mientras tanto pueden subir sus cambios como copia ("Informe (copia de Ana).docx");
--     eso es una subida normal con otro nombre, no necesita nada en la base.

alter table public.files add column lock_until timestamptz;

-- Vencimiento efectivo: lock_until, o locked_at + 24 h para bloqueos viejos.
create or replace function public.lock_expires_at(f public.files)
returns timestamptz language sql stable as $$
  select coalesce(f.lock_until, f.locked_at + public.lock_ttl())
$$;

create or replace function public.locked_by_other(f public.files)
returns boolean language sql stable as $$
  select f.locked_by is not null
     and f.locked_by <> auth.uid()
     and public.lock_expires_at(f) > now()
$$;

-- Reemplaza la versión de la fase 4: ahora recibe la duración en minutos.
drop function public.lock_file(uuid);

create or replace function public.lock_file(p_file_id uuid, p_minutos integer default 120)
returns public.files
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  quien text;
  minutos integer := least(greatest(coalesce(p_minutos, 120), 15), 24 * 60);
begin
  select * into f from public.files where id = p_file_id for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;

  if public.locked_by_other(f) then
    select nombre into quien from public.profiles where id = f.locked_by;
    raise exception '% ya está editando este archivo', coalesce(quien, 'Otra persona')
      using errcode = 'P0001';
  end if;

  -- Si ya era mío, es una renovación: arranca de nuevo con la duración elegida.
  update public.files
  set locked_by = auth.uid(),
      locked_at = case when f.locked_by = auth.uid() then f.locked_at else now() end,
      lock_until = now() + make_interval(mins => minutos)
  where id = p_file_id
  returning * into f;
  return f;
end;
$$;

revoke execute on function public.lock_file(uuid, integer) from public, anon;
grant execute on function public.lock_file(uuid, integer) to authenticated;

-- Desbloquear y subir versión también limpian lock_until.
create or replace function public.clear_lock_until()
returns trigger language plpgsql as $$
begin
  if new.locked_by is null then
    new.lock_until := null;
  end if;
  return new;
end;
$$;

create trigger files_clear_lock_until
  before update of locked_by on public.files
  for each row execute function public.clear_lock_until();

create or replace function public.release_expired_locks()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  update public.files f set locked_by = null, locked_at = null
  where f.locked_by is not null and public.lock_expires_at(f) <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Pedidos de liberación ---------------------------------------------------------

create table public.lock_requests (
  id            uuid primary key default gen_random_uuid(),
  file_id       uuid not null references public.files (id) on delete cascade,
  group_id      uuid not null references public.groups (id) on delete cascade,
  owner_id      uuid not null references public.profiles (id) on delete cascade, -- quien lo tiene bloqueado
  requested_by  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  unique (file_id, requested_by)
);

create index lock_requests_owner_idx on public.lock_requests (owner_id);

alter table public.lock_requests enable row level security;

create policy "lock_requests: ver los de mis grupos"
  on public.lock_requests for select to authenticated
  using (public.is_group_member(group_id));

revoke insert, update, delete on public.lock_requests from authenticated;

-- Le pide a quien lo está editando que lo libere. Repetirlo dentro de los
-- 10 minutos no vuelve a avisar.
create or replace function public.request_unlock(p_file_id uuid)
returns public.lock_requests
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  r public.lock_requests;
begin
  select * into f from public.files where id = p_file_id;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;
  if not public.locked_by_other(f) then
    raise exception 'El archivo ya está libre' using errcode = 'P0001';
  end if;

  select * into r from public.lock_requests
  where file_id = p_file_id and requested_by = auth.uid();

  if r.id is not null and r.created_at > now() - interval '10 minutes' then
    raise exception 'Ya se lo pediste hace un rato' using errcode = 'P0001';
  end if;

  insert into public.lock_requests (file_id, group_id, owner_id, requested_by)
  values (p_file_id, f.group_id, f.locked_by, auth.uid())
  on conflict (file_id, requested_by)
  do update set created_at = now(), owner_id = excluded.owner_id
  returning * into r;
  return r;
end;
$$;

revoke execute on function public.request_unlock(uuid) from public, anon;
grant execute on function public.request_unlock(uuid) to authenticated;

-- Cuando el archivo se libera (o cambia de dueño) los pedidos ya no aplican.
create or replace function public.clear_lock_requests()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.lock_requests where file_id = new.id;
  return new;
end;
$$;

create trigger files_clear_lock_requests
  after update of locked_by on public.files
  for each row
  when (old.locked_by is distinct from new.locked_by)
  execute function public.clear_lock_requests();

alter table public.lock_requests replica identity full;
alter publication supabase_realtime add table public.lock_requests;
