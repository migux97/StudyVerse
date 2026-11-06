-- Notificaciones: lo que antes solo llegaba con la app abierta (avisos en vivo)
-- ahora queda guardado en un centro de notificaciones (la campanita) y sale
-- como push al celular o al navegador, aunque la app esté cerrada.
--
-- Cada evento que le importa a una persona (una mención, un aviso del docente,
-- una devolución, la revisión de su entrega, un pedido de archivo, una tarea
-- asignada) inserta una fila en `notificaciones`. La Edge Function
-- `enviar-push` las manda por Firebase Cloud Messaging a los dispositivos de
-- esa persona (`dispositivos_push`).

-- Dispositivos -------------------------------------------------------------------

create table public.dispositivos_push (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  token       text not null unique check (char_length(token) between 20 and 4096),
  plataforma  text not null check (plataforma in ('android', 'web')),
  created_at  timestamptz not null default now(),
  ultimo_uso  timestamptz not null default now()
);

create index dispositivos_push_usuario_idx on public.dispositivos_push (user_id);

alter table public.dispositivos_push enable row level security;

-- Un token de FCM es secreto del dispositivo: solo lo conoce quien lo usa.
-- Si otra cuenta registra el mismo token (se cerró sesión y entró otra
-- persona), pasa a esa cuenta. Robarlo exige acceso al equipo.
revoke all on public.dispositivos_push from anon;

create policy "dispositivos_push: ver los míos"
  on public.dispositivos_push for select to authenticated
  using (user_id = (select auth.uid()));

create policy "dispositivos_push: borrar los míos"
  on public.dispositivos_push for delete to authenticated
  using (user_id = (select auth.uid()));

-- Se registran con registrar_dispositivo.
revoke insert, update on public.dispositivos_push from authenticated;

-- Registra (o renueva) el token de este dispositivo para mí. Si el token era
-- de otra cuenta (se cerró sesión y entró otra persona en el mismo
-- dispositivo), pasa a ser mío: los push van a quien está usando el equipo.
create or replace function public.registrar_dispositivo(p_token text, p_plataforma text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  if p_plataforma not in ('android', 'web') then
    raise exception 'Plataforma desconocida' using errcode = 'P0001';
  end if;
  -- Hasta 10 dispositivos por persona: se descartan los más viejos.
  delete from public.dispositivos_push
  where user_id = auth.uid() and token <> p_token
    and id not in (select id from public.dispositivos_push
                   where user_id = auth.uid() order by ultimo_uso desc limit 9);
  insert into public.dispositivos_push (user_id, token, plataforma)
  values (auth.uid(), p_token, p_plataforma)
  on conflict (token) do update
    set user_id = excluded.user_id, plataforma = excluded.plataforma, ultimo_uso = now();
end;
$$;

-- Al cerrar sesión: este dispositivo deja de recibir mis push.
create or replace function public.quitar_dispositivo(p_token text)
returns void
language sql security definer set search_path = ''
as $$
  delete from public.dispositivos_push where token = p_token and user_id = auth.uid()
$$;

revoke execute on function public.registrar_dispositivo(text, text) from public, anon;
revoke execute on function public.quitar_dispositivo(text) from public, anon;
grant execute on function public.registrar_dispositivo(text, text) to authenticated;
grant execute on function public.quitar_dispositivo(text) to authenticated;

-- Notificaciones -----------------------------------------------------------------

create table public.notificaciones (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  tipo         text not null check (tipo in ('mencion', 'aviso', 'devolucion', 'revision', 'pedido', 'tarea_asignada')),
  titulo       text not null check (char_length(titulo) between 1 and 200),
  cuerpo       text check (cuerpo is null or char_length(cuerpo) <= 300),
  -- Pantalla de la app que abre (ruta de go_router, p. ej. /grupos/…/tareas).
  ruta         text not null check (ruta ~ '^/[A-Za-z0-9/_-]*$'),
  group_id     uuid references public.groups (id) on delete cascade,
  created_at   timestamptz not null default now(),
  leida_at     timestamptz,
  -- Envío por push.
  push_estado  text not null default 'pendiente'
               check (push_estado in ('pendiente', 'enviada', 'sin_dispositivos', 'fallida')),
  push_intentos integer not null default 0,
  push_bloqueo  timestamptz
);

create index notificaciones_usuario_idx on public.notificaciones (user_id, created_at desc);
create index notificaciones_no_leidas_idx on public.notificaciones (user_id) where leida_at is null;
create index notificaciones_push_idx on public.notificaciones (created_at) where push_estado = 'pendiente';
create index notificaciones_grupo_idx on public.notificaciones (group_id) where group_id is not null;
-- Para el tope de repetidas.
create index notificaciones_repetidas_idx on public.notificaciones (user_id, tipo, created_at desc);

revoke all on public.notificaciones from anon;

alter table public.notificaciones enable row level security;

create policy "notificaciones: ver las mías"
  on public.notificaciones for select to authenticated
  using (user_id = (select auth.uid()));

create policy "notificaciones: marcar las mías como leídas"
  on public.notificaciones for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "notificaciones: borrar las mías"
  on public.notificaciones for delete to authenticated
  using (user_id = (select auth.uid()));

-- Las crea la base; el cliente solo marca leída.
revoke insert, update on public.notificaciones from authenticated;
grant update (leida_at) on public.notificaciones to authenticated;

-- Para los triggers de abajo. No notifica a quien hizo la acción.
create or replace function public.notificar(
  p_user_id uuid, p_tipo text, p_titulo text, p_cuerpo text, p_ruta text, p_group_id uuid
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_user_id is null or p_user_id is not distinct from auth.uid() then
    return;
  end if;
  -- La misma notificación a la misma persona, una vez por minuto (alguien
  -- que reasigna o menciona en bucle no llena de push a nadie).
  if exists (select 1 from public.notificaciones
             where user_id = p_user_id and tipo = p_tipo and titulo = left(p_titulo, 200)
               and created_at > now() - interval '1 minute') then
    return;
  end if;
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  values (p_user_id, p_tipo, left(p_titulo, 200), nullif(left(trim(coalesce(p_cuerpo, '')), 300), ''), p_ruta, p_group_id);
end;
$$;

revoke execute on function public.notificar(uuid, text, text, text, text, uuid) from public, anon, authenticated;

-- Ruta del visor o del editor según el archivo.
create or replace function public.ruta_archivo(p_file_id uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select case when lower(f.nombre) like '%.svdoc'
              then format('/grupos/%s/documentos/%s', f.group_id, f.id)
              else format('/grupos/%s/archivos/%s', f.group_id, f.id) end
  from public.files f where f.id = p_file_id
$$;

revoke execute on function public.ruta_archivo(uuid) from public, anon, authenticated;

-- Menciones en comentarios.
create or replace function public.notificar_menciones()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  archivo text := regexp_replace(coalesce((select nombre from public.files where id = new.file_id), 'un archivo'),
                                 '\.svdoc$', '', 'i');
begin
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select distinct u, 'mencion', left(format('%s te mencionó en %s', public.nombre_de(new.autor), archivo), 200),
         left(new.texto, 300), public.ruta_archivo(new.file_id), new.group_id
  from unnest(new.menciones) as u
  where u is distinct from new.autor;
  return null;
end;
$$;

create trigger comentarios_notificar after insert on public.comentarios
  for each row execute function public.notificar_menciones();

-- Avisos del docente: a cada integrante de los grupos destinatarios.
create or replace function public.notificar_aviso()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Todas en una sola sentencia: un solo aviso en vivo y una sola llamada
  -- para el push, aunque el curso tenga cientos de alumnos.
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select distinct on (gm.user_id)
         gm.user_id, 'aviso', left(format('Aviso de %s', public.nombre_de(new.autor)), 200),
         left(new.texto, 300), format('/grupos/%s', g.id), g.id
  from public.groups g join public.group_members gm on gm.group_id = g.id
  where g.curso_id = new.curso_id and (new.group_id is null or g.id = new.group_id)
    and gm.user_id is distinct from new.autor
  order by gm.user_id, g.nombre;
  return null;
end;
$$;

create trigger avisos_notificar after insert on public.avisos
  for each row execute function public.notificar_aviso();

-- Devoluciones: a quien tiene la tarea y a quien la entregó.
create or replace function public.notificar_devolucion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  t public.tasks;
  u uuid;
begin
  select * into t from public.tasks where id = new.task_id;
  for u in select distinct x from unnest(array[t.assigned_to, t.entregada_por]) as x
           where x is not null and public.is_member_of(new.group_id, x) loop
    perform public.notificar(u, 'devolucion', format('%s dejó una devolución en «%s»', public.nombre_de(new.autor), t.titulo),
      new.texto, format('/grupos/%s/tareas', new.group_id), new.group_id);
  end loop;
  return null;
end;
$$;

create trigger devoluciones_notificar after insert on public.devoluciones
  for each row execute function public.notificar_devolucion();

-- Tareas: la revisión de una entrega y las tareas asignadas.
create or replace function public.notificar_tareas()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  ruta text := format('/grupos/%s/tareas', new.group_id);
begin
  if tg_op = 'UPDATE' and old.estado = 'entregada' and new.estado in ('hecha', 'en_progreso')
     and auth.uid() is not null and public.is_group_admin(new.group_id)
     and public.is_member_of(new.group_id, old.entregada_por) then
    perform public.notificar(old.entregada_por, 'revision',
      case when new.estado = 'hecha'
           then format('%s aprobó «%s»', public.nombre_de(auth.uid()), new.titulo)
           else format('%s te pidió cambios en «%s»', public.nombre_de(auth.uid()), new.titulo) end,
      case when new.estado = 'en_progreso' then new.revision_nota end, ruta, new.group_id);
  end if;

  if new.assigned_to is not null
     and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to) then
    perform public.notificar(new.assigned_to, 'tarea_asignada',
      format('%s te asignó «%s»', coalesce(public.nombre_de(auth.uid()), 'Alguien'), new.titulo),
      case when new.due_date is not null then format('Vence el %s', to_char(new.due_date, 'DD/MM')) end,
      ruta, new.group_id);
  end if;
  return null;
end;
$$;

create trigger tasks_notificar after insert or update of estado, assigned_to on public.tasks
  for each row execute function public.notificar_tareas();

-- Pedidos de archivo: a quien lo está editando.
create or replace function public.notificar_pedido()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.notificar(new.owner_id, 'pedido',
    format('%s necesita editar %s', public.nombre_de(new.requested_by),
           regexp_replace(coalesce((select nombre from public.files where id = new.file_id), 'un archivo'), '\.svdoc$', '', 'i')),
    'Si ya terminaste, liberalo para que pueda seguir.', public.ruta_archivo(new.file_id), new.group_id);
  return null;
end;
$$;

-- También al volver a pedirlo (request_unlock actualiza la fila existente).
create trigger lock_requests_notificar after insert or update on public.lock_requests
  for each row execute function public.notificar_pedido();

revoke execute on function public.notificar_menciones() from public, anon, authenticated;
revoke execute on function public.notificar_aviso() from public, anon, authenticated;
revoke execute on function public.notificar_devolucion() from public, anon, authenticated;
revoke execute on function public.notificar_tareas() from public, anon, authenticated;
revoke execute on function public.notificar_pedido() from public, anon, authenticated;

-- En vivo y push -------------------------------------------------------------------

-- La campanita se actualiza en vivo (solo el aviso, sin datos), y se despierta
-- a la función que manda los push.
create or replace function public.notificaciones_nuevas()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  u uuid;
begin
  for u in select distinct user_id from nuevas loop
    perform realtime.send('{}'::jsonb, 'cambio', format('usuario:%s:notificaciones', u), true);
  end loop;
  if exists (select 1 from nuevas n join public.dispositivos_push d on d.user_id = n.user_id) then
    perform public.call_internal_function('enviar-push');
  end if;
  return null;
end;
$$;

revoke execute on function public.notificaciones_nuevas() from public, anon, authenticated;

create trigger notificaciones_nuevas after insert on public.notificaciones
  referencing new table as nuevas
  for each statement execute function public.notificaciones_nuevas();

-- Para la Edge Function: toma hasta p_limite notificaciones para mandar, con
-- los tokens de cada persona. Las que no tienen a dónde ir quedan como
-- 'sin_dispositivos'. Solo las de las últimas 24 h: si el push se configura
-- después, no se manda todo lo viejo de golpe.
create or replace function public.tomar_push(p_limite integer default 50)
returns table (id uuid, titulo text, cuerpo text, ruta text, tokens jsonb)
language plpgsql security definer set search_path = ''
as $$
begin
  update public.notificaciones n
  set push_estado = 'sin_dispositivos'
  where n.push_estado = 'pendiente'
    and not exists (select 1 from public.dispositivos_push d where d.user_id = n.user_id);

  update public.notificaciones n
  set push_estado = 'fallida'
  where n.push_estado = 'pendiente' and (n.created_at < now() - interval '24 hours' or n.push_intentos >= 5);

  return query
  with tomadas as (
    update public.notificaciones n
    set push_intentos = n.push_intentos + 1, push_bloqueo = now() + interval '2 minutes'
    where n.id in (
      select x.id from public.notificaciones x
      where x.push_estado = 'pendiente' and (x.push_bloqueo is null or x.push_bloqueo < now())
      order by x.created_at
      limit p_limite
      for update skip locked
    )
    returning n.*
  )
  select t.id, t.titulo, t.cuerpo, t.ruta,
         (select coalesce(jsonb_agg(jsonb_build_object('token', d.token, 'plataforma', d.plataforma)), '[]')
          from public.dispositivos_push d where d.user_id = t.user_id)
  from tomadas t
  order by t.created_at;
end;
$$;

revoke execute on function public.tomar_push(integer) from public, anon, authenticated;

-- Reintentos cada minuto y limpieza: las notificaciones duran 60 días.
select cron.schedule('push-reintentos', '* * * * *',
  $$select public.call_internal_function('enviar-push')
    where exists (select 1 from public.notificaciones n
                  where n.push_estado = 'pendiente' and n.created_at > now() - interval '24 hours'
                    and exists (select 1 from public.dispositivos_push d where d.user_id = n.user_id))$$);
select cron.schedule('notificaciones-viejas', '15 5 * * *',
  $$delete from public.notificaciones where created_at < now() - interval '60 days';
    update public.notificaciones set push_estado = 'fallida'
    where push_estado = 'pendiente' and created_at < now() - interval '24 hours'$$);

-- Canal nuevo: usuario:{id}:notificaciones.
create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram|documentos|comentarios|avisos)$');
  if m is not null then
    return public.is_group_member(m[1]::uuid)
        or (m[2] in ('archivos', 'tareas', 'actividad', 'comentarios', 'avisos')
            and public.es_docente_de_grupo(m[1]::uuid));
  end if;
  return auth.uid() is not null
     and p_topic in (format('usuario:%s:grupos', auth.uid()),
                     format('usuario:%s:pedidos', auth.uid()),
                     format('usuario:%s:menciones', auth.uid()),
                     format('usuario:%s:tareas', auth.uid()),
                     format('usuario:%s:avisos', auth.uid()),
                     format('usuario:%s:notificaciones', auth.uid()));
end;
$$;
