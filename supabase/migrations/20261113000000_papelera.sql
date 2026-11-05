-- Papelera: eliminar un archivo lo manda a la papelera por 30 días, como en
-- Drive. De ahí se restaura o se elimina para siempre (quien lo subió, quien
-- lo mandó a la papelera o un admin). Ocupa espacio hasta que se vacía.

alter table public.files
  add column deleted_at timestamptz,
  add column deleted_by uuid references public.profiles (id) on delete set null;

create index files_papelera_idx on public.files (group_id, deleted_at) where deleted_at is not null;

-- El nombre es único entre los archivos que no están en la papelera.
drop index public.files_nombre_unico;
create unique index files_nombre_unico
  on public.files (group_id, folder_id, lower(nombre)) nulls not distinct
  where deleted_at is null;

-- Lo que está en la papelera no se edita, ni se bloquea, ni se renombra.
create or replace function public.files_papelera_inmutable()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.deleted_at is not null and new.deleted_at is not null
     and (new.nombre <> old.nombre
          or new.locked_by is distinct from old.locked_by
          or new.current_version_id is distinct from old.current_version_id) then
    raise exception 'Está en la papelera: restauralo para usarlo' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger files_papelera_inmutable
  before update on public.files
  for each row execute function public.files_papelera_inmutable();

-- Subir por nombre no encuentra lo que está en la papelera (sube uno nuevo).
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
    select * into f from public.files where id = p_file_id and group_id = p_group_id and deleted_at is null;
    if f.id is null then
      raise exception 'El archivo no existe' using errcode = 'P0002';
    end if;
  else
    select * into f from public.files
    where group_id = p_group_id
      and folder_id is not distinct from p_folder_id
      and lower(nombre) = lower(trim(p_nombre))
      and deleted_at is null;
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

-- Eliminar = mandar a la papelera. Devuelve una lista vacía (antes devolvía las
-- rutas a borrar de Storage; ahora eso pasa al vaciar la papelera).
create or replace function public.delete_file(p_file_id uuid)
returns setof text
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
begin
  select * into f from public.files where id = p_file_id and deleted_at is null for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;
  if not (f.created_by = auth.uid() or public.is_group_admin(f.group_id)) then
    raise exception 'Solo quien lo subió o un admin pueden eliminarlo' using errcode = '42501';
  end if;
  if public.locked_by_other(f) then
    raise exception 'Otra persona está editando este archivo' using errcode = 'P0001';
  end if;
  update public.files
  set deleted_at = clock_timestamp(), deleted_by = auth.uid(), locked_by = null, locked_at = null
  where id = p_file_id;
  return;
end;
$$;

-- Restaurar: vuelve a su carpeta (o a la raíz si la carpeta ya no está). Si ya
-- hay otro con el mismo nombre, queda como "Nombre (2).ext".
create or replace function public.restaurar_archivo(p_file_id uuid)
returns public.files
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  carpeta uuid;
  nuevo text;
  base text;
  ext text;
  n integer := 2;
begin
  select * into f from public.files where id = p_file_id and deleted_at is not null for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'No está en la papelera' using errcode = 'P0002';
  end if;
  carpeta := (select id from public.folders where id = f.folder_id);
  nuevo := f.nombre;
  base := regexp_replace(f.nombre, '(\.[^.]+)$', '');
  ext := coalesce(substring(f.nombre from '(\.[^.]+)$'), '');
  while exists (select 1 from public.files o
                where o.group_id = f.group_id and o.folder_id is not distinct from carpeta
                  and lower(o.nombre) = lower(nuevo) and o.deleted_at is null) loop
    nuevo := base || ' (' || n || ')' || ext;
    n := n + 1;
  end loop;
  update public.files
  set deleted_at = null, deleted_by = null, folder_id = carpeta, nombre = nuevo
  where id = p_file_id
  returning * into f;
  return f;
end;
$$;

-- Eliminar para siempre: quien lo subió, quien lo mandó a la papelera o un
-- admin. Los objetos de Storage los borra la limpieza diaria.
create or replace function public.eliminar_definitivo(p_file_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
begin
  -- for update: si alguien lo está restaurando justo ahora, espera y ve el cambio.
  select * into f from public.files where id = p_file_id and deleted_at is not null for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'No está en la papelera' using errcode = 'P0002';
  end if;
  if not (f.created_by = auth.uid() or f.deleted_by = auth.uid() or public.is_group_admin(f.group_id)) then
    raise exception 'Solo quien lo subió, quien lo eliminó o un admin pueden borrarlo para siempre' using errcode = '42501';
  end if;
  delete from public.files where id = p_file_id and deleted_at is not null;
end;
$$;

-- Una carpeta con cosas en la papelera se puede borrar: lo de la papelera pasa
-- a la raíz (así se puede restaurar igual).
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
     or exists (select 1 from public.files where folder_id = p_folder_id and deleted_at is null) then
    raise exception 'La carpeta no está vacía' using errcode = 'P0001';
  end if;
  update public.files set folder_id = null where folder_id = p_folder_id and deleted_at is not null;
  delete from public.folders where id = p_folder_id;
end;
$$;

revoke execute on function public.restaurar_archivo(uuid) from public, anon;
revoke execute on function public.eliminar_definitivo(uuid) from public, anon;
grant execute on function public.restaurar_archivo(uuid) to authenticated;
grant execute on function public.eliminar_definitivo(uuid) to authenticated;
revoke execute on function public.files_papelera_inmutable() from public, anon, authenticated;

-- Actividad: a la papelera y restaurado.
create or replace function public.activity_papelera()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  base jsonb := jsonb_build_object('file_id', new.id, 'folder_id', new.folder_id, 'nombre', new.nombre);
begin
  if old.deleted_at is null and new.deleted_at is not null then
    perform public.log_activity(new.group_id, auth.uid(), 'archivo_a_papelera', base);
  elsif old.deleted_at is not null and new.deleted_at is null then
    perform public.log_activity(new.group_id, auth.uid(), 'archivo_restaurado', base);
  end if;
  return null;
end;
$$;

revoke execute on function public.activity_papelera() from public, anon, authenticated;

create trigger files_activity_papelera
  after update of deleted_at on public.files
  for each row execute function public.activity_papelera();

-- Storage: un objeto que ya no usa ninguna versión NO se puede leer. Antes
-- hacía falta para que la app lo borrara después de eliminar; ahora los borra
-- la limpieza diaria (con la clave del servidor), y dejarlos legibles exponía
-- las versiones que el plan oculta durante esa ventana.
create or replace function public.storage_object_readable(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
           select 1 from public.file_versions v
           where v.storage_path = p_path and public.version_visible(v.file_id, v.version_number))
      or public.upload_reserved(p_path)
$$;

-- La papelera se vacía sola a los 30 días.
select cron.schedule(
  'vaciar-papelera',
  '0 5 * * *',
  $$delete from public.files where deleted_at < now() - interval '30 days'$$
);
