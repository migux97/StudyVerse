-- Subidas reservadas.
--
-- begin_upload reserva la ruta de Storage para quien sube, y solo con esa
-- reserva se puede subir el objeto y registrarlo. Así:
--   * nadie ocupa de antemano la ruta de la próxima versión de otro;
--   * finish_upload usa la carpeta y el nombre que validó begin_upload, no los
--     que manda el cliente;
--   * el espacio del plan se controla con el tamaño real, al terminar.
--
-- El número de la ruta (v{n}) es la clave de la reserva. El número de versión
-- se asigna al terminar (última + 1), así una subida abandonada no deja huecos.
-- Casi siempre coinciden; difieren solo si dos personas suben a la vez.

create table public.pending_uploads (
  storage_path   text primary key,
  group_id       uuid not null references public.groups (id) on delete cascade,
  file_id        uuid not null,
  version_number integer not null,               -- el de la ruta
  base_version   integer,                        -- última versión al reservar
  folder_id      uuid references public.folders (id) on delete cascade,
  nombre         text not null,
  user_id        uuid not null references auth.users (id) on delete cascade,
  expires_at     timestamptz not null default now() + interval '2 hours'
);

create index pending_uploads_file_idx on public.pending_uploads (file_id);
create index pending_uploads_group_idx on public.pending_uploads (group_id, expires_at);

-- Sin políticas: solo la usan las funciones de abajo.
alter table public.pending_uploads enable row level security;
revoke all on public.pending_uploads from anon, authenticated;

-- ¿Tengo reservada esta ruta? (política de subida de Storage)
create or replace function public.upload_reserved(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.pending_uploads
    where storage_path = p_path and user_id = auth.uid() and expires_at > now()
  )
$$;

revoke execute on function public.upload_reserved(text) from public, anon;
grant execute on function public.upload_reserved(text) to authenticated;

drop policy "archivos: subir a mis grupos" on storage.objects;

create policy "archivos: subir lo reservado"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'archivos' and public.upload_reserved(name));

-- Prepara una subida y la reserva. version_number es el número de la ruta:
-- salta los reservados por otros y los que ya tienen objeto en Storage, así
-- dos personas que suben a la vez no se pisan.
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
  base integer;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;

  if p_folder_id is not null and not exists (
    select 1 from public.folders where id = p_folder_id and group_id = p_group_id
  ) then
    raise exception 'La carpeta no existe' using errcode = 'P0002';
  end if;

  if nullif(trim(p_nombre), '') is null then
    raise exception 'Falta el nombre del archivo' using errcode = 'P0001';
  end if;

  -- Aviso temprano; el control que vale es el de finish_upload.
  select g.storage_used, l.storage_bytes into usado, limite
  from public.groups g join public.plan_limits l on l.plan = g.plan
  where g.id = p_group_id;

  if usado + greatest(coalesce(p_size_bytes, 0), 0) > limite then
    raise exception 'El grupo no tiene más espacio (límite: % MB)', limite / 1024 / 1024
      using errcode = 'P0001';
  end if;

  delete from public.pending_uploads pu where pu.group_id = p_group_id and pu.expires_at <= now();

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
    file_id := f.id;
    es_nuevo := false;
    select max(fv.version_number) into base from public.file_versions fv where fv.file_id = f.id;
    select 1 + greatest(
      base,
      (select max(pu.version_number) from public.pending_uploads pu where pu.file_id = f.id),
      (select max(substring(o.name from '/v([0-9]+)$')::int) from storage.objects o
       where o.bucket_id = 'archivos'
         and o.name like format('groups/%s/files/%s/v%%', p_group_id, f.id)
         and o.name ~ '/v[0-9]+$'),
      0)
    into version_number;
  end if;

  storage_path := public.storage_path_for(p_group_id, file_id, version_number);

  insert into public.pending_uploads
    (storage_path, group_id, file_id, version_number, base_version, folder_id, nombre, user_id)
  values
    (storage_path, p_group_id, file_id, version_number, base,
     coalesce(f.folder_id, p_folder_id), coalesce(f.nombre, trim(p_nombre)), auth.uid());

  return next;
end;
$$;

-- Registra la versión subida. p_version_number es el que devolvió
-- begin_upload (el de la ruta). Solo vale la reserva de quien llama; la
-- carpeta y el nombre salen de la reserva (p_folder_id y p_nombre se ignoran,
-- quedan por compatibilidad con la app).
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
  ruta text := public.storage_path_for(p_group_id, p_file_id, p_version_number);
  r public.pending_uploads;
  f public.files;
  tamano bigint;
  mime text;
  usado bigint;
  limite bigint;
  ultima integer;
  fv public.file_versions;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;

  select * into r from public.pending_uploads
  where storage_path = ruta and user_id = auth.uid();

  if r.storage_path is null then
    raise exception 'Esta subida no está preparada. Probá de nuevo' using errcode = 'P0001';
  end if;

  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype'
  into tamano, mime
  from storage.objects o
  where o.bucket_id = 'archivos' and o.name = ruta;

  if tamano is null then
    raise exception 'No se encontró el archivo subido' using errcode = 'P0002';
  end if;

  -- Cuota con el tamaño real. El lock serializa las subidas del grupo.
  select g.storage_used, l.storage_bytes into usado, limite
  from public.groups g join public.plan_limits l on l.plan = g.plan
  where g.id = p_group_id
  for update of g;

  if usado + tamano > limite then
    raise exception 'El grupo no tiene más espacio (límite: % MB)', limite / 1024 / 1024
      using errcode = 'P0001';
  end if;

  select * into f from public.files where id = p_file_id;

  if f.id is null then
    if r.base_version is not null then
      raise exception 'El archivo ya no existe' using errcode = 'P0002';
    end if;
    if r.folder_id is not null and not exists (
      select 1 from public.folders where id = r.folder_id and group_id = p_group_id
    ) then
      raise exception 'La carpeta no existe' using errcode = 'P0002';
    end if;
    insert into public.files (id, group_id, folder_id, nombre, created_by)
    values (p_file_id, p_group_id, r.folder_id, r.nombre, auth.uid())
    returning * into f;
  elsif f.group_id <> p_group_id then
    raise exception 'El archivo no es de este grupo' using errcode = '42501';
  elsif public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;

  select max(v.version_number) into ultima from public.file_versions v where v.file_id = f.id;
  -- Otra persona terminó una versión mientras esta subía: no se pisa.
  if ultima is distinct from r.base_version then
    raise exception 'Alguien subió otra versión al mismo tiempo. Probá de nuevo' using errcode = 'P0001';
  end if;

  begin
    insert into public.file_versions
      (file_id, group_id, version_number, storage_path, size_bytes, mime_type, nota, uploaded_by)
    values
      (f.id, p_group_id, coalesce(ultima, 0) + 1, ruta, tamano, mime, nullif(trim(p_nota), ''), auth.uid())
    returning * into fv;
  exception when unique_violation then
    raise exception 'Alguien subió otra versión al mismo tiempo. Probá de nuevo' using errcode = 'P0001';
  end;

  delete from public.pending_uploads where storage_path = ruta;

  -- Subir una versión nueva libera el bloqueo de quien lo tenía.
  update public.files
  set current_version_id = fv.id, locked_by = null, locked_at = null
  where id = f.id;

  return fv;
end;
$$;
