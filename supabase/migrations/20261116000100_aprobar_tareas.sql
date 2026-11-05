-- Aprobación de tareas (opcional por grupo). Con "aprobar_tareas" activado,
-- quien hace la tarea la marca como entregada y un admin la aprueba (pasa a
-- hecha) o pide cambios (vuelve a en progreso, con una nota). Solo un admin
-- puede dejar una tarea como hecha.

alter table public.groups add column aprobar_tareas boolean not null default false;

-- El admin cambia el nombre y si se aprueban las tareas (la política de
-- update de groups ya pide ser admin).
revoke update on public.groups from authenticated;
grant update (nombre, aprobar_tareas) on public.groups to authenticated;

alter table public.tasks
  add column entregada_por uuid references public.profiles (id) on delete set null,
  add column entregada_at timestamptz,
  add column entrega_nota text check (entrega_nota is null or char_length(entrega_nota) <= 500),
  add column revisada_por uuid references public.profiles (id) on delete set null,
  add column revision_nota text check (revision_nota is null or char_length(revision_nota) <= 500);

-- Las columnas nuevas las ponen la base y las funciones de abajo: el cliente
-- puede cambiar solo (titulo, assigned_to, due_date, estado, folder_id), y al
-- insertar el trigger las pone en null.

create or replace function public.tasks_aprobacion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  aprobar boolean;
  admin boolean;
  antes public.estado_tarea := case when tg_op = 'UPDATE' then old.estado end;
begin
  if tg_op = 'INSERT' then
    new.entregada_por := null;
    new.entregada_at := null;
    new.entrega_nota := null;
    new.revisada_por := null;
    new.revision_nota := null;
  end if;

  -- Sin cambio de estado (por ejemplo, guardar el formulario), nada que ver.
  if new.estado is not distinct from antes then
    return new;
  end if;

  select g.aprobar_tareas into aprobar from public.groups g where g.id = new.group_id;
  -- Sin usuario (cron, bot) no se frena nada.
  admin := auth.uid() is null or public.is_group_admin(new.group_id);

  -- Con aprobación, solo un admin deja una tarea hecha, y solo un admin saca
  -- una tarea de "entregada" o de "hecha" (si no, se podría deshacer la
  -- revisión). Entregar pasa por entregar_tarea.
  if coalesce(aprobar, false) and not admin then
    if new.estado = 'hecha' then
      raise exception 'Un admin tiene que aprobarla: marcala como entregada' using errcode = 'P0001';
    end if;
    if antes in ('entregada', 'hecha') then
      raise exception 'Ya está %: solo un admin puede cambiarla', case antes when 'hecha' then 'aprobada' else 'entregada' end
        using errcode = 'P0001';
    end if;
  end if;

  if new.estado = 'entregada' then
    new.entregada_por := auth.uid();
    new.entregada_at := now();
    new.revisada_por := null;
    new.revision_nota := null;
  elsif new.estado = 'hecha' and antes = 'entregada' then
    new.revisada_por := auth.uid();
  elsif new.estado = 'hecha' then
    new.revisada_por := null;
    new.revision_nota := null;
  elsif antes in ('entregada', 'hecha') then
    -- Volvió atrás: la entrega anterior ya no vale (la nota de cambios, si la
    -- puso revisar_tarea en el mismo update, se conserva).
    new.entregada_por := null;
    new.entregada_at := null;
    new.entrega_nota := null;
  end if;
  return new;
end;
$$;

revoke execute on function public.tasks_aprobacion() from public, anon, authenticated;

create trigger tasks_aprobacion
  before insert or update of estado on public.tasks
  for each row execute function public.tasks_aprobacion();

-- Entregar: cualquier integrante (normalmente el responsable), con una nota.
create or replace function public.entregar_tarea(p_task_id uuid, p_nota text default null)
returns public.tasks
language plpgsql security definer set search_path = ''
as $$
declare
  t public.tasks;
  nota text := nullif(trim(coalesce(p_nota, '')), '');
begin
  select * into t from public.tasks where id = p_task_id for update;
  if t.id is null or not public.is_group_member(t.group_id) then
    raise exception 'La tarea no existe' using errcode = 'P0002';
  end if;
  if t.estado = 'hecha' then
    raise exception 'Esta tarea ya está hecha' using errcode = 'P0001';
  end if;
  if char_length(nota) > 500 then
    raise exception 'La nota puede tener hasta 500 caracteres' using errcode = 'P0001';
  end if;
  update public.tasks set estado = 'entregada', entrega_nota = nota where id = p_task_id returning * into t;
  return t;
end;
$$;

-- Revisar (solo admin): aprobar, o pedir cambios con una nota.
create or replace function public.revisar_tarea(p_task_id uuid, p_aprobar boolean, p_nota text default null)
returns public.tasks
language plpgsql security definer set search_path = ''
as $$
declare
  t public.tasks;
  nota text := nullif(trim(coalesce(p_nota, '')), '');
begin
  select * into t from public.tasks where id = p_task_id for update;
  if t.id is null or not public.is_group_member(t.group_id) then
    raise exception 'La tarea no existe' using errcode = 'P0002';
  end if;
  if not public.is_group_admin(t.group_id) then
    raise exception 'Solo un admin puede revisar tareas' using errcode = 'P0001';
  end if;
  if t.estado <> 'entregada' then
    raise exception 'Esta tarea no está entregada' using errcode = 'P0001';
  end if;
  if p_aprobar is null then
    raise exception 'Falta decir si se aprueba' using errcode = 'P0001';
  end if;
  if not p_aprobar and nota is null then
    raise exception 'Contale qué hay que cambiar' using errcode = 'P0001';
  end if;
  if char_length(nota) > 500 then
    raise exception 'La nota puede tener hasta 500 caracteres' using errcode = 'P0001';
  end if;

  if p_aprobar then
    update public.tasks set estado = 'hecha' where id = p_task_id returning * into t;
  else
    update public.tasks set estado = 'en_progreso', revision_nota = nota, revisada_por = auth.uid()
    where id = p_task_id returning * into t;
  end if;
  return t;
end;
$$;

revoke execute on function public.entregar_tarea(uuid, text) from public, anon;
revoke execute on function public.revisar_tarea(uuid, boolean, text) from public, anon;
grant execute on function public.entregar_tarea(uuid, text) to authenticated;
grant execute on function public.revisar_tarea(uuid, boolean, text) to authenticated;

-- Actividad: entregada, aprobada y cambios pedidos (sin copiar las notas).
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

  if new.estado = 'hecha' and old.estado = 'entregada' and auth.uid() is not null
     and public.is_group_admin(new.group_id) then
    perform public.log_activity(new.group_id, coalesce(auth.uid(), new.revisada_por), 'tarea_aprobada',
      base || jsonb_build_object('a', public.nombre_de(old.entregada_por)));
  elsif new.estado = 'hecha' and old.estado <> 'hecha' then
    perform public.log_activity(new.group_id, coalesce(auth.uid(), new.assigned_to), 'tarea_completada', base);
  elsif new.estado = 'entregada' and old.estado <> 'entregada' then
    perform public.log_activity(new.group_id, coalesce(auth.uid(), new.entregada_por), 'tarea_entregada', base);
  elsif new.estado = 'en_progreso' and old.estado = 'entregada' and auth.uid() is not null
        and public.is_group_admin(new.group_id) then
    perform public.log_activity(new.group_id, auth.uid(), 'tarea_cambios_pedidos',
      base || jsonb_build_object('a', public.nombre_de(old.entregada_por)));
  end if;
  if new.assigned_to is not null and new.assigned_to is distinct from old.assigned_to then
    perform public.log_activity(new.group_id, auth.uid(), 'tarea_asignada',
      base || jsonb_build_object('a', public.nombre_de(new.assigned_to)));
  end if;
  return new;
end;
$$;

-- Aviso en vivo a quien entregó cuando un admin la revisa.
create or replace function public.avisar_revision()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Solo el id: la app vuelve a leer la tarea con su RLS.
  if old.estado = 'entregada' and new.estado in ('hecha', 'en_progreso')
     and auth.uid() is not null and public.is_group_admin(new.group_id)
     and old.entregada_por is not null and old.entregada_por is distinct from auth.uid()
     and public.is_member_of(new.group_id, old.entregada_por) then
    perform realtime.send(jsonb_build_object('tarea', new.id), 'revision',
                          format('usuario:%s:tareas', old.entregada_por), true);
  end if;
  return null;
end;
$$;

revoke execute on function public.avisar_revision() from public, anon, authenticated;

create trigger tasks_avisar_revision
  after update of estado on public.tasks
  for each row execute function public.avisar_revision();

create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram|documentos|comentarios)$');
  if m is not null then
    return public.is_group_member(m[1]::uuid);
  end if;
  return auth.uid() is not null
     and p_topic in (format('usuario:%s:grupos', auth.uid()),
                     format('usuario:%s:pedidos', auth.uid()),
                     format('usuario:%s:menciones', auth.uid()),
                     format('usuario:%s:tareas', auth.uid()));
end;
$$;

-- Telegram: también avisa entregas y aprobaciones.
create or replace function public.telegram_notifica(p_tipo text)
returns boolean language sql immutable as $$
  select p_tipo in (
    'version_subida', 'version_restaurada',
    'archivo_bloqueado', 'archivo_desbloqueado', 'desbloqueo_forzado', 'liberacion_pedida',
    'tarea_completada', 'tarea_entregada', 'tarea_aprobada'
  )
$$;

-- Recordatorios de vencimiento: una tarea entregada ya no se recuerda.
create or replace function public.enqueue_due_reminders(p_ahora timestamptz default now())
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  local timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  n integer;
begin
  if local::time < time '10:00' then
    return 0;
  end if;

  with avisar as (
    update public.tasks t
    set reminder_sent_at = p_ahora
    where t.estado not in ('hecha', 'entregada')
      and t.due_date = local::date + 1
      and t.reminder_sent_at is null
    returning t.id, t.group_id
  ), encoladas as (
    insert into public.telegram_outbox (chat_id, group_id, kind, task_id)
    select l.chat_id, a.group_id, 'recordatorio', a.id
    from avisar a join public.telegram_links l on l.group_id = a.group_id
    returning 1
  )
  select (select count(*) from avisar) into n;

  if n > 0 then
    perform public.telegram_kick();
  end if;
  return n;
end;
$$;

revoke execute on function public.enqueue_due_reminders(timestamptz) from public, anon, authenticated;
