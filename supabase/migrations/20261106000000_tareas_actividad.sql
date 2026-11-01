-- Fase 5: tareas, feed de actividad y aportes.

-- Tareas ---------------------------------------------------------------------

create type public.estado_tarea as enum ('pendiente', 'en_progreso', 'hecha');

create table public.tasks (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references public.groups (id) on delete cascade,
  folder_id     uuid references public.folders (id) on delete set null, -- TP al que pertenece (opcional)
  titulo        text not null check (char_length(trim(titulo)) between 1 and 200),
  assigned_to   uuid references public.profiles (id) on delete set null,
  due_date      date,
  estado        public.estado_tarea not null default 'pendiente',
  completed_at  timestamptz,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index tasks_group_idx on public.tasks (group_id);
create index tasks_due_idx on public.tasks (due_date) where estado <> 'hecha';

create or replace function public.is_member_of(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.group_members where group_id = p_group_id and user_id = p_user_id)
$$;

-- Valida responsable y carpeta, y lleva completed_at.
create or replace function public.tasks_before_write()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.assigned_to is not null and not public.is_member_of(new.group_id, new.assigned_to) then
    raise exception 'El responsable tiene que ser del grupo' using errcode = 'P0001';
  end if;
  if new.folder_id is not null and not exists (
    select 1 from public.folders where id = new.folder_id and group_id = new.group_id
  ) then
    raise exception 'La carpeta no es de este grupo' using errcode = 'P0001';
  end if;

  if new.estado = 'hecha' and (tg_op = 'INSERT' or old.estado <> 'hecha') then
    new.completed_at := now();
  elsif new.estado <> 'hecha' then
    new.completed_at := null;
  end if;
  return new;
end;
$$;

create trigger tasks_before_write
  before insert or update on public.tasks
  for each row execute function public.tasks_before_write();

alter table public.tasks enable row level security;

create policy "tasks: ver las de mis grupos"
  on public.tasks for select to authenticated
  using (public.is_group_member(group_id));

create policy "tasks: crear en mis grupos"
  on public.tasks for insert to authenticated
  with check (public.is_group_member(group_id) and created_by = (select auth.uid()));

create policy "tasks: editar en mis grupos"
  on public.tasks for update to authenticated
  using (public.is_group_member(group_id))
  with check (public.is_group_member(group_id));

create policy "tasks: elimina quien la creó o un admin"
  on public.tasks for delete to authenticated
  using (created_by = (select auth.uid()) or public.is_group_admin(group_id));

revoke update on public.tasks from authenticated;
grant update (titulo, assigned_to, due_date, estado, folder_id) on public.tasks to authenticated;

-- Actividad ------------------------------------------------------------------
-- Solo la escriben los triggers. user_id = quién hizo la acción (null si fue
-- el sistema). El payload guarda los nombres para que el texto sobreviva a
-- renombres y borrados.

create table public.activity (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups (id) on delete cascade,
  user_id     uuid references public.profiles (id) on delete set null,
  tipo        text not null,
  payload     jsonb not null default '{}',
  -- clock_timestamp: varios eventos de una misma operación quedan en orden.
  created_at  timestamptz not null default clock_timestamp()
);

create index activity_group_idx on public.activity (group_id, created_at desc);

alter table public.activity enable row level security;

create policy "activity: ver la de mis grupos"
  on public.activity for select to authenticated
  using (public.is_group_member(group_id));

revoke insert, update, delete on public.activity from authenticated;

create or replace function public.log_activity(
  p_group_id uuid, p_user_id uuid, p_tipo text, p_payload jsonb default '{}'
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  -- Si el grupo se está borrando (cascada), no hay nada que registrar.
  if not exists (select 1 from public.groups where id = p_group_id) then
    return;
  end if;
  insert into public.activity (group_id, user_id, tipo, payload)
  values (p_group_id, p_user_id, p_tipo, coalesce(p_payload, '{}'));
end;
$$;

revoke execute on function public.log_activity(uuid, uuid, text, jsonb) from public, anon, authenticated;

create or replace function public.nombre_de(p_user_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select nombre from public.profiles where id = p_user_id
$$;

-- Versiones: "subió la v3" o "restauró la v1 (como v4)".
create or replace function public.activity_file_versions()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  desde integer;
begin
  select * into f from public.files where id = new.file_id;
  -- Restaurar reutiliza el objeto de una versión anterior.
  select min(version_number) into desde from public.file_versions
  where file_id = new.file_id and storage_path = new.storage_path and id <> new.id;

  perform public.log_activity(new.group_id, new.uploaded_by,
    case when desde is null then 'version_subida' else 'version_restaurada' end,
    jsonb_build_object(
      'file_id', new.file_id, 'folder_id', f.folder_id,
      'nombre', coalesce(f.nombre, 'un archivo'), 'version', new.version_number, 'desde', desde,
      'nota', new.nota));
  return new;
end;
$$;

create trigger file_versions_activity
  after insert on public.file_versions
  for each row execute function public.activity_file_versions();

-- Archivos: bloqueos, renombres y bajas.
create or replace function public.activity_files()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  base jsonb;
begin
  if tg_op = 'DELETE' then
    perform public.log_activity(old.group_id, auth.uid(), 'archivo_eliminado',
      jsonb_build_object('nombre', old.nombre, 'folder_id', old.folder_id));
    return old;
  end if;

  base := jsonb_build_object('file_id', new.id, 'folder_id', new.folder_id, 'nombre', new.nombre);

  if old.nombre <> new.nombre then
    perform public.log_activity(new.group_id, auth.uid(), 'archivo_renombrado',
      base || jsonb_build_object('antes', old.nombre));
  end if;

  if new.locked_by is not null and new.locked_by is distinct from old.locked_by then
    perform public.log_activity(new.group_id, new.locked_by, 'archivo_bloqueado',
      base || jsonb_build_object('hasta', new.lock_until));
  elsif old.locked_by is not null and new.locked_by is null
        and new.current_version_id is not distinct from old.current_version_id  -- subir ya avisa
        and auth.uid() is not null then                                         -- vencido (cron): no
    if auth.uid() = old.locked_by then
      perform public.log_activity(new.group_id, auth.uid(), 'archivo_desbloqueado', base);
    else
      perform public.log_activity(new.group_id, auth.uid(), 'desbloqueo_forzado',
        base || jsonb_build_object('de', public.nombre_de(old.locked_by)));
    end if;
  end if;
  return new;
end;
$$;

create trigger files_activity
  after update or delete on public.files
  for each row execute function public.activity_files();

create or replace function public.activity_folders()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.log_activity(new.group_id, new.created_by, 'carpeta_creada',
    jsonb_build_object('folder_id', new.id, 'nombre', new.nombre));
  return new;
end;
$$;

create trigger folders_activity
  after insert on public.folders
  for each row execute function public.activity_folders();

-- Integrantes: user_id es la persona que entra o sale.
create or replace function public.activity_group_members()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Quien crea el grupo no "se une".
    if new.rol <> 'admin' or exists (select 1 from public.group_members
                                     where group_id = new.group_id and user_id <> new.user_id) then
      perform public.log_activity(new.group_id, new.user_id, 'miembro_unido');
    end if;
    return new;
  end if;

  perform public.log_activity(old.group_id, old.user_id, 'miembro_salio',
    case when auth.uid() is distinct from old.user_id
         then jsonb_build_object('por', public.nombre_de(auth.uid()))
         else '{}' end);
  return old;
end;
$$;

create trigger group_members_activity
  after insert or delete on public.group_members
  for each row execute function public.activity_group_members();

create or replace function public.activity_tasks()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  base jsonb := jsonb_build_object('task_id', new.id, 'titulo', new.titulo);
begin
  if tg_op = 'INSERT' then
    perform public.log_activity(new.group_id, new.created_by, 'tarea_creada',
      base || jsonb_build_object('a', public.nombre_de(new.assigned_to), 'due_date', new.due_date));
    return new;
  end if;

  if new.estado = 'hecha' and old.estado <> 'hecha' then
    perform public.log_activity(new.group_id, coalesce(auth.uid(), new.assigned_to), 'tarea_completada', base);
  end if;
  if new.assigned_to is not null and new.assigned_to is distinct from old.assigned_to then
    perform public.log_activity(new.group_id, auth.uid(), 'tarea_asignada',
      base || jsonb_build_object('a', public.nombre_de(new.assigned_to)));
  end if;
  return new;
end;
$$;

create trigger tasks_activity
  after insert or update on public.tasks
  for each row execute function public.activity_tasks();

create or replace function public.activity_lock_requests()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.log_activity(new.group_id, new.requested_by, 'liberacion_pedida',
    jsonb_build_object('file_id', new.file_id, 'nombre', (select nombre from public.files where id = new.file_id),
                       'a', public.nombre_de(new.owner_id)));
  return new;
end;
$$;

create trigger lock_requests_activity
  after insert on public.lock_requests
  for each row execute function public.activity_lock_requests();

-- Aportes ----------------------------------------------------------------------
-- Cuenta todas las versiones (también las que el plan free no muestra).

create or replace function public.group_contributions(p_group_id uuid)
returns table (
  user_id uuid,
  nombre text,
  avatar_url text,
  rol public.rol_miembro,
  tareas_completadas integer,
  tareas_pendientes integer,
  versiones_subidas integer,
  ultima_actividad timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;

  return query
  select m.user_id, p.nombre, p.avatar_url, m.rol,
    (select count(*)::int from public.tasks t
      where t.group_id = p_group_id and t.assigned_to = m.user_id and t.estado = 'hecha'),
    (select count(*)::int from public.tasks t
      where t.group_id = p_group_id and t.assigned_to = m.user_id and t.estado <> 'hecha'),
    (select count(*)::int from public.file_versions v
      where v.group_id = p_group_id and v.uploaded_by = m.user_id),
    (select max(a.created_at) from public.activity a
      where a.group_id = p_group_id and a.user_id = m.user_id)
  from public.group_members m
  join public.profiles p on p.id = m.user_id
  where m.group_id = p_group_id
  order by p.nombre;
end;
$$;

revoke execute on function public.group_contributions(uuid) from public, anon;
grant execute on function public.group_contributions(uuid) to authenticated;

-- Realtime -----------------------------------------------------------------------

alter table public.tasks replica identity full;
alter table public.activity replica identity full;
alter publication supabase_realtime add table public.tasks, public.activity;
