-- Chat del grupo: para coordinar el TP sin salir de la app.
--
-- Solo los integrantes leen y escriben (el docente del curso no: es el espacio
-- de los alumnos; para hablarles tiene avisos y devoluciones). Un mensaje puede
-- citar a otro, adjuntar un archivo del grupo y mencionar con @usuario. Se
-- edita el propio; se borra el propio (o un admin), y queda "Mensaje eliminado".
-- Avisa por push solo a quien mencionan o le responden.

create table public.mensajes (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups (id) on delete cascade,
  autor       uuid references public.profiles (id) on delete set null default auth.uid(),
  texto       text check (texto is null or char_length(texto) <= 4000),
  file_id     uuid references public.files (id) on delete set null,
  responde_a  uuid references public.mensajes (id) on delete set null,
  menciones   uuid[] not null default '{}',
  created_at  timestamptz not null default clock_timestamp(),
  editado_at  timestamptz,
  borrado_at  timestamptz,
  -- Con texto o con archivo (salvo que esté borrado).
  constraint mensajes_con_contenido check (
    borrado_at is not null or (nullif(trim(texto), '') is not null or file_id is not null)
  )
);

create index mensajes_grupo_idx on public.mensajes (group_id, created_at desc);
create index mensajes_autor_idx on public.mensajes (autor, created_at desc);
create index mensajes_responde_idx on public.mensajes (responde_a) where responde_a is not null;
create index mensajes_archivo_idx on public.mensajes (file_id) where file_id is not null;

alter table public.mensajes enable row level security;
revoke all on public.mensajes from anon;

create policy "mensajes: los ven los integrantes"
  on public.mensajes for select to authenticated
  using (public.is_group_member(group_id));

create policy "mensajes: los escriben los integrantes"
  on public.mensajes for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and autor = (select auth.uid())
    -- Columnas calificadas: sin "mensajes.", responde_a sería la de r.
    and (mensajes.file_id is null or exists (
      select 1 from public.files f
      where f.id = mensajes.file_id and f.group_id = mensajes.group_id and f.deleted_at is null))
    and (mensajes.responde_a is null or exists (
      select 1 from public.mensajes r
      where r.id = mensajes.responde_a and r.group_id = mensajes.group_id and r.borrado_at is null))
  );

create policy "mensajes: cada uno edita los suyos"
  on public.mensajes for update to authenticated
  using (autor = (select auth.uid()) and borrado_at is null and public.is_group_member(group_id))
  with check (autor = (select auth.uid()));

-- El cliente elige solo esto; id, fechas, menciones y el borrado los pone la base.
revoke insert, update, delete on public.mensajes from authenticated;
grant insert (group_id, autor, texto, file_id, responde_a) on public.mensajes to authenticated;
grant update (texto) on public.mensajes to authenticated;

-- Menciones (solo integrantes) y tope: 30 mensajes por minuto por persona.
create or replace function public.mensajes_antes()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtext('chat:' || coalesce(new.autor::text, '')));
    if (select count(*) from public.mensajes
        where autor = new.autor and created_at > now() - interval '1 minute') >= 30 then
      raise exception 'Mandaste muchos mensajes seguidos. Esperá un momento' using errcode = 'P0001';
    end if;
  elsif new.borrado_at is null and new.texto is distinct from old.texto then
    if nullif(trim(new.texto), '') is null and new.file_id is null then
      raise exception 'El mensaje no puede quedar vacío' using errcode = 'P0001';
    end if;
    new.editado_at := clock_timestamp();
  end if;

  new.texto := nullif(trim(new.texto), '');
  new.menciones := coalesce((
    select array_agg(distinct p.id)
    from regexp_matches(lower(coalesce(new.texto, '')), '@([a-z0-9][a-z0-9._]{1,18}[a-z0-9])', 'g') as m(u)
    join public.profiles p on p.username = m.u[1]
    join public.group_members gm on gm.user_id = p.id and gm.group_id = new.group_id
    where p.id is distinct from new.autor
  ), '{}');
  return new;
end;
$$;

revoke execute on function public.mensajes_antes() from public, anon, authenticated;

create trigger mensajes_antes before insert or update of texto on public.mensajes
  for each row execute function public.mensajes_antes();

-- Si se elimina para siempre un archivo que iba solo en un mensaje, el mensaje
-- queda como borrado (si no, el check frenaría el borrado y la purga de la papelera).
create or replace function public.mensajes_sin_archivo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.mensajes
  set menciones = '{}', borrado_at = clock_timestamp()
  where file_id = old.id and texto is null and borrado_at is null;
  return old;
end;
$$;

revoke execute on function public.mensajes_sin_archivo() from public, anon, authenticated;

create trigger mensajes_sin_archivo before delete on public.files
  for each row execute function public.mensajes_sin_archivo();

-- Borrar: el autor o un admin. Queda el lugar ("Mensaje eliminado").
create or replace function public.borrar_mensaje(p_mensaje_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.mensajes;
begin
  select * into m from public.mensajes where id = p_mensaje_id for update;
  if m.id is null or not public.is_group_member(m.group_id) then
    raise exception 'El mensaje no existe' using errcode = 'P0002';
  end if;
  if m.autor is distinct from auth.uid() and not public.is_group_admin(m.group_id) then
    raise exception 'Solo quien lo mandó o un admin pueden borrarlo' using errcode = 'P0001';
  end if;
  update public.mensajes
  set texto = null, file_id = null, menciones = '{}', borrado_at = clock_timestamp()
  where id = p_mensaje_id;
  -- Que el texto no siga en la campanita.
  delete from public.notificaciones where mensaje_id = p_mensaje_id;
end;
$$;

revoke execute on function public.borrar_mensaje(uuid) from public, anon;
grant execute on function public.borrar_mensaje(uuid) to authenticated;

-- Leídos ------------------------------------------------------------------------

create table public.chat_leido (
  group_id     uuid not null references public.groups (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  leido_hasta  timestamptz not null default now(),
  primary key (group_id, user_id)
);

alter table public.chat_leido enable row level security;
revoke all on public.chat_leido from anon;

create policy "chat_leido: lo mío"
  on public.chat_leido for select to authenticated
  using (user_id = (select auth.uid()));

revoke insert, update, delete on public.chat_leido from authenticated;

-- "Leí hasta acá" (al abrir el chat y mientras está abierto).
create or replace function public.marcar_chat_leido(p_group_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;
  insert into public.chat_leido (group_id, user_id, leido_hasta)
  values (p_group_id, auth.uid(), clock_timestamp())
  on conflict (group_id, user_id) do update set leido_hasta = excluded.leido_hasta;
end;
$$;

-- Mensajes sin leer en cada uno de mis grupos (los míos no cuentan).
create or replace function public.chat_sin_leer()
returns table (group_id uuid, cantidad integer)
language sql stable security definer set search_path = ''
as $$
  -- Primero el límite de cada grupo y después se cuenta por el índice (group_id, created_at).
  select gm.group_id, c.cantidad
  from public.group_members gm
  left join public.chat_leido l on l.group_id = gm.group_id and l.user_id = gm.user_id
  cross join lateral (
    select count(*)::int as cantidad
    from public.mensajes m
    where m.group_id = gm.group_id
      and m.created_at > coalesce(l.leido_hasta, gm.joined_at)
      and m.autor is distinct from gm.user_id
      and m.borrado_at is null
  ) c
  where gm.user_id = auth.uid() and c.cantidad > 0
$$;

revoke execute on function public.marcar_chat_leido(uuid) from public, anon;
revoke execute on function public.chat_sin_leer() from public, anon;
grant execute on function public.marcar_chat_leido(uuid) to authenticated;
grant execute on function public.chat_sin_leer() to authenticated;

-- En vivo y notificaciones --------------------------------------------------------

-- Al grupo, solo el id del mensaje (la app lo lee con su RLS).
create or replace function public.avisar_mensaje()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform realtime.send(jsonb_build_object('mensaje', new.id), 'cambio',
                        format('grupo:%s:chat', new.group_id), true);
  return null;
end;
$$;

revoke execute on function public.avisar_mensaje() from public, anon, authenticated;

create trigger mensajes_avisar after insert or update on public.mensajes
  for each row execute function public.avisar_mensaje();

alter table public.notificaciones drop constraint notificaciones_tipo_check;
alter table public.notificaciones add constraint notificaciones_tipo_check
  check (tipo in ('mencion', 'aviso', 'devolucion', 'revision', 'pedido', 'tarea_asignada', 'chat'));

-- Para sacarlas de la campanita si se borra el mensaje.
alter table public.notificaciones
  add column mensaje_id uuid references public.mensajes (id) on delete cascade;
create index notificaciones_mensaje_idx on public.notificaciones (mensaje_id) where mensaje_id is not null;

-- Push solo a quien mencionan o le responden (todo en una sentencia).
create or replace function public.notificar_mensaje()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  grupo text := (select nombre from public.groups where id = new.group_id);
  quien text := public.nombre_de(new.autor);
  respondido uuid := (select autor from public.mensajes where id = new.responde_a);
begin
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id, mensaje_id)
  select distinct on (d.u) d.u, 'chat',
         left(case when d.mencion then format('%s te mencionó en el chat de %s', quien, grupo)
                   else format('%s te respondió en el chat de %s', quien, grupo) end, 200),
         left(coalesce(new.texto, 'Mandó un archivo'), 300),
         format('/grupos/%s/chat', new.group_id), new.group_id, new.id
  from (
    select u, true as mencion from unnest(new.menciones) as u
    union all
    select respondido, false where respondido is not null
  ) d
  where d.u is distinct from new.autor and public.is_member_of(new.group_id, d.u)
  order by d.u, d.mencion desc;
  return null;
end;
$$;

revoke execute on function public.notificar_mensaje() from public, anon, authenticated;

create trigger mensajes_notificar after insert on public.mensajes
  for each row execute function public.notificar_mensaje();

-- Canal nuevo: grupo:{id}:chat (solo integrantes; el docente no).
create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram|documentos|comentarios|avisos|chat)$');
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
