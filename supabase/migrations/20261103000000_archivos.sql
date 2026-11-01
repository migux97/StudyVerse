-- Fase 3: carpetas, archivos con versiones y Storage.
--
-- Flujo de subida (los bytes nunca pasan por la base):
--   1. begin_upload  → valida permisos, bloqueo y cuota; devuelve file_id,
--                      número de versión y ruta en Storage.
--   2. El cliente sube el archivo a Storage en esa ruta.
--   3. finish_upload → verifica que el objeto exista, toma el tamaño real de
--                      Storage y registra la versión.
-- Ruta en Storage: groups/{group_id}/files/{file_id}/v{n}

-- Tablas -------------------------------------------------------------------

create table public.folders (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups (id) on delete cascade,
  parent_id   uuid references public.folders (id) on delete cascade,
  nombre      text not null check (char_length(trim(nombre)) between 1 and 120),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);

create unique index folders_nombre_unico
  on public.folders (group_id, parent_id, lower(nombre)) nulls not distinct;
create index folders_group_idx on public.folders (group_id);

create table public.files (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null references public.groups (id) on delete cascade,
  folder_id           uuid references public.folders (id) on delete cascade, -- null = raíz del grupo
  nombre              text not null check (char_length(trim(nombre)) between 1 and 255),
  current_version_id  uuid,
  locked_by           uuid references public.profiles (id) on delete set null,
  locked_at           timestamptz,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now()
);

create unique index files_nombre_unico
  on public.files (group_id, folder_id, lower(nombre)) nulls not distinct;
create index files_group_idx on public.files (group_id);

create table public.file_versions (
  id              uuid primary key default gen_random_uuid(),
  file_id         uuid not null references public.files (id) on delete cascade,
  group_id        uuid not null references public.groups (id) on delete cascade,
  version_number  integer not null check (version_number > 0),
  storage_path    text not null,
  size_bytes      bigint not null check (size_bytes >= 0),
  mime_type       text,
  nota            text check (nota is null or char_length(nota) <= 500),
  uploaded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (file_id, version_number)
);

create index file_versions_path_idx on public.file_versions (storage_path);

alter table public.files
  add constraint files_current_version_id_fkey
  foreign key (current_version_id) references public.file_versions (id) on delete set null;

-- Helpers ------------------------------------------------------------------

-- Duración de un bloqueo antes de vencer (se usa también en la fase 4).
create or replace function public.lock_ttl()
returns interval language sql immutable as $$ select interval '24 hours' $$;

create or replace function public.storage_path_for(p_group_id uuid, p_file_id uuid, p_version integer)
returns text language sql immutable as $$
  select format('groups/%s/files/%s/v%s', p_group_id, p_file_id, p_version)
$$;

-- ¿El archivo está bloqueado por otra persona (y el bloqueo sigue vigente)?
create or replace function public.locked_by_other(f public.files)
returns boolean language sql stable as $$
  select f.locked_by is not null
     and f.locked_by <> auth.uid()
     and f.locked_at > now() - public.lock_ttl()
$$;

-- Plan free: solo las últimas N versiones son visibles (plan_limits).
create or replace function public.version_visible(p_file_id uuid, p_version integer)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    p_version > (select max(v.version_number) from public.file_versions v where v.file_id = p_file_id)
                - (select l.versiones_visibles
                   from public.files f
                   join public.groups g on g.id = f.group_id
                   join public.plan_limits l on l.plan = g.plan
                   where f.id = p_file_id),
    true)  -- versiones_visibles null (premium) = historial completo
$$;

-- ¿Alguna versión (visible o no) usa todavía este objeto de Storage?
create or replace function public.storage_path_in_use(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.file_versions where storage_path = p_path)
$$;

-- RLS ----------------------------------------------------------------------

alter table public.folders enable row level security;
alter table public.files enable row level security;
alter table public.file_versions enable row level security;

create policy "folders: ver las de mis grupos"
  on public.folders for select to authenticated
  using (public.is_group_member(group_id));

create policy "folders: crear en mis grupos"
  on public.folders for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and created_by = (select auth.uid())
    and (parent_id is null
         or exists (select 1 from public.folders p where p.id = parent_id and p.group_id = folders.group_id))
  );

create policy "folders: renombrar en mis grupos"
  on public.folders for update to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));

revoke update on public.folders from authenticated;
grant update (nombre) on public.folders to authenticated;
revoke delete on public.folders from authenticated; -- con delete_folder()

create policy "files: ver los de mis grupos"
  on public.files for select to authenticated
  using (public.is_group_member(group_id));

-- Altas, cambios y bajas de archivos: solo con las funciones de abajo.
revoke insert, update, delete on public.files from authenticated;

create policy "file_versions: ver las visibles de mis grupos"
  on public.file_versions for select to authenticated
  using (public.is_group_member(group_id) and public.version_visible(file_id, version_number));

revoke insert, update, delete on public.file_versions from authenticated;

-- Storage --------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('archivos', 'archivos', false, 50 * 1024 * 1024)
on conflict (id) do nothing;

-- (storage.foldername('groups/G/files/F/v1'))[2] = G
create policy "archivos: leer los de mis grupos"
  on storage.objects for select to authenticated
  using (bucket_id = 'archivos' and public.is_group_member(((storage.foldername(name))[2])::uuid));

create policy "archivos: subir a mis grupos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'archivos'
    and name ~ '^groups/[0-9a-f-]{36}/files/[0-9a-f-]{36}/v[0-9]+$'
    and public.is_group_member(((storage.foldername(name))[2])::uuid)
  );

-- Solo se borran objetos que ya no usa ninguna versión (después de delete_file).
create policy "archivos: borrar huérfanos de mis grupos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'archivos'
    and public.is_group_member(((storage.foldername(name))[2])::uuid)
    and not public.storage_path_in_use(name)
  );

-- Espacio usado por grupo ------------------------------------------------------
-- Cuenta cada objeto de Storage una vez: restaurar una versión reutiliza el
-- objeto viejo y no suma espacio.

create or replace function public.track_storage_added()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.file_versions
                 where storage_path = new.storage_path and id <> new.id) then
    update public.groups set storage_used = storage_used + new.size_bytes where id = new.group_id;
  end if;
  return new;
end;
$$;

create trigger file_versions_storage_added
  after insert on public.file_versions
  for each row execute function public.track_storage_added();

-- Por sentencia: al borrar un archivo se van todas sus versiones juntas, y
-- varias pueden compartir objeto (restauradas); cada objeto se descuenta una vez.
create or replace function public.track_storage_freed()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.groups g
  set storage_used = greatest(g.storage_used - x.total, 0)
  from (
    select d.group_id, sum(d.size_bytes) as total
    from (select distinct on (storage_path) storage_path, group_id, size_bytes from borradas) d
    where not exists (select 1 from public.file_versions v where v.storage_path = d.storage_path)
    group by d.group_id
  ) x
  where g.id = x.group_id;
  return null;
end;
$$;

create trigger file_versions_storage_freed
  after delete on public.file_versions
  referencing old table as borradas
  for each statement execute function public.track_storage_freed();

-- Operaciones ------------------------------------------------------------------

-- Prepara una subida. Con p_file_id sube una versión nueva de ese archivo; si
-- no, busca por nombre en la carpeta: si existe es versión nueva, si no, archivo nuevo.
create or replace function public.begin_upload(
  p_group_id uuid,
  p_folder_id uuid,
  p_nombre text,
  p_size_bytes bigint,
  p_file_id uuid default null
)
returns table (file_id uuid, version_number integer, storage_path text, es_nuevo boolean)
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  usado bigint;
  limite bigint;
  v integer;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;

  if p_folder_id is not null and not exists (
    select 1 from public.folders where id = p_folder_id and group_id = p_group_id
  ) then
    raise exception 'La carpeta no existe' using errcode = 'P0002';
  end if;

  select g.storage_used, l.storage_bytes into usado, limite
  from public.groups g join public.plan_limits l on l.plan = g.plan
  where g.id = p_group_id;

  if usado + coalesce(p_size_bytes, 0) > limite then
    raise exception 'El grupo no tiene más espacio (límite: % MB)', limite / 1024 / 1024
      using errcode = 'P0001';
  end if;

  if p_file_id is not null then
    select * into f from public.files where id = p_file_id and group_id = p_group_id;
    if f.id is null then
      raise exception 'El archivo no existe' using errcode = 'P0002';
    end if;
  else
    select * into f from public.files
    where group_id = p_group_id
      and folder_id is not distinct from p_folder_id
      and lower(nombre) = lower(trim(p_nombre));
  end if;

  if f.id is null then
    file_id := gen_random_uuid();
    version_number := 1;
    es_nuevo := true;
  else
    if public.locked_by_other(f) then
      raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
    end if;
    select coalesce(max(fv.version_number), 0) + 1 into v
    from public.file_versions fv where fv.file_id = f.id;
    file_id := f.id;
    version_number := v;
    es_nuevo := false;
  end if;

  storage_path := public.storage_path_for(p_group_id, file_id, version_number);
  return next;
end;
$$;

-- Registra la versión una vez que el objeto está en Storage.
create or replace function public.finish_upload(
  p_group_id uuid,
  p_folder_id uuid,
  p_nombre text,
  p_file_id uuid,
  p_version_number integer,
  p_nota text default null
)
returns public.file_versions
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  ruta text := public.storage_path_for(p_group_id, p_file_id, p_version_number);
  tamano bigint;
  mime text;
  fv public.file_versions;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;

  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype'
  into tamano, mime
  from storage.objects o
  where o.bucket_id = 'archivos' and o.name = ruta;

  if tamano is null then
    raise exception 'No se encontró el archivo subido' using errcode = 'P0002';
  end if;

  select * into f from public.files where id = p_file_id;

  if f.id is null then
    if p_version_number <> 1 then
      raise exception 'Versión inválida' using errcode = 'P0001';
    end if;
    insert into public.files (id, group_id, folder_id, nombre, created_by)
    values (p_file_id, p_group_id, p_folder_id, trim(p_nombre), auth.uid())
    returning * into f;
  elsif f.group_id <> p_group_id then
    raise exception 'El archivo no es de este grupo' using errcode = '42501';
  elsif public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;

  begin
    insert into public.file_versions
      (file_id, group_id, version_number, storage_path, size_bytes, mime_type, nota, uploaded_by)
    values
      (f.id, p_group_id, p_version_number, ruta, tamano, mime, nullif(trim(p_nota), ''), auth.uid())
    returning * into fv;
  exception when unique_violation then
    raise exception 'Alguien subió otra versión al mismo tiempo. Probá de nuevo' using errcode = 'P0001';
  end;

  -- Subir una versión nueva libera el bloqueo de quien lo tenía.
  update public.files
  set current_version_id = fv.id, locked_by = null, locked_at = null
  where id = f.id;

  return fv;
end;
$$;

-- Restaurar = nueva versión que apunta al mismo objeto de Storage.
create or replace function public.restore_version(p_version_id uuid, p_nota text default null)
returns public.file_versions
language plpgsql security definer set search_path = ''
as $$
declare
  vieja public.file_versions;
  f public.files;
  fv public.file_versions;
begin
  select * into vieja from public.file_versions where id = p_version_id;
  if vieja.id is null or not public.is_group_member(vieja.group_id)
     or not public.version_visible(vieja.file_id, vieja.version_number) then
    raise exception 'La versión no existe' using errcode = 'P0002';
  end if;

  select * into f from public.files where id = vieja.file_id;
  if public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;

  insert into public.file_versions
    (file_id, group_id, version_number, storage_path, size_bytes, mime_type, nota, uploaded_by)
  select vieja.file_id, vieja.group_id, max(version_number) + 1, vieja.storage_path,
         vieja.size_bytes, vieja.mime_type,
         coalesce(nullif(trim(p_nota), ''), format('Restaurada desde la v%s', vieja.version_number)),
         auth.uid()
  from public.file_versions where file_id = vieja.file_id
  returning * into fv;

  update public.files set current_version_id = fv.id, locked_by = null, locked_at = null
  where id = f.id;

  return fv;
end;
$$;

create or replace function public.rename_file(p_file_id uuid, p_nombre text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
begin
  select * into f from public.files where id = p_file_id;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;
  if public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;

  begin
    update public.files set nombre = trim(p_nombre) where id = p_file_id;
  exception when unique_violation then
    raise exception 'Ya hay un archivo con ese nombre en esta carpeta' using errcode = 'P0001';
  end;
end;
$$;

-- Elimina el archivo con todas sus versiones. Devuelve las rutas de Storage
-- para que el cliente borre los objetos (la base no puede borrarlos).
create or replace function public.delete_file(p_file_id uuid)
returns setof text
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  rutas text[];
begin
  select * into f from public.files where id = p_file_id;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;
  if not (f.created_by = auth.uid() or public.is_group_admin(f.group_id)) then
    raise exception 'Solo quien lo subió o un admin pueden eliminarlo' using errcode = '42501';
  end if;
  if public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;

  select array_agg(distinct storage_path) into rutas from public.file_versions where file_id = p_file_id;
  delete from public.files where id = p_file_id;
  return query select unnest(coalesce(rutas, '{}'));
end;
$$;

create or replace function public.delete_folder(p_folder_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  c public.folders;
begin
  select * into c from public.folders where id = p_folder_id;
  if c.id is null or not public.is_group_member(c.group_id) then
    raise exception 'La carpeta no existe' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.folders where parent_id = p_folder_id)
     or exists (select 1 from public.files where folder_id = p_folder_id) then
    raise exception 'La carpeta no está vacía' using errcode = 'P0001';
  end if;
  delete from public.folders where id = p_folder_id;
end;
$$;

revoke execute on function public.begin_upload(uuid, uuid, text, bigint, uuid) from public, anon;
revoke execute on function public.finish_upload(uuid, uuid, text, uuid, integer, text) from public, anon;
revoke execute on function public.restore_version(uuid, text) from public, anon;
revoke execute on function public.rename_file(uuid, text) from public, anon;
revoke execute on function public.delete_file(uuid) from public, anon;
revoke execute on function public.delete_folder(uuid) from public, anon;
grant execute on function public.begin_upload(uuid, uuid, text, bigint, uuid) to authenticated;
grant execute on function public.finish_upload(uuid, uuid, text, uuid, integer, text) to authenticated;
grant execute on function public.restore_version(uuid, text) to authenticated;
grant execute on function public.rename_file(uuid, text) to authenticated;
grant execute on function public.delete_file(uuid) to authenticated;
grant execute on function public.delete_folder(uuid) to authenticated;

-- Realtime ----------------------------------------------------------------------

alter table public.folders replica identity full;
alter table public.files replica identity full;
alter table public.file_versions replica identity full;
alter publication supabase_realtime add table public.folders, public.files, public.file_versions;
