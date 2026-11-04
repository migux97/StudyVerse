-- Avisos en vivo por canales privados (Realtime Broadcast).
--
-- Con postgres_changes, Supabase no aplica la RLS a los eventos DELETE:
-- cualquiera que se suscribiera con el group_id de un grupo ajeno veía qué se
-- borraba y quién salía (las claves primarias). Ahora:
--   * las tablas salen de la publicación supabase_realtime (no hay eventos de
--     filas para nadie);
--   * los triggers mandan un aviso sin datos ("cambió algo") a un canal
--     privado, y la app vuelve a leer con su RLS;
--   * la RLS de realtime.messages decide quién puede escuchar cada canal.
--
-- Canales:
--   grupo:{id}:archivos   carpetas, archivos, versiones, pedidos de liberación
--   grupo:{id}:tareas     tareas
--   grupo:{id}:actividad  feed
--   grupo:{id}:telegram   chats vinculados
--   usuario:{id}:grupos   mis grupos (altas, bajas, renombres, integrantes)
--   usuario:{id}:pedidos  me piden que libere un archivo ({"pedido": id})

-- ¿Puedo escuchar este canal? -------------------------------------------------

create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram)$');
  if m is not null then
    return public.is_group_member(m[1]::uuid);
  end if;
  return auth.uid() is not null
     and p_topic in (format('usuario:%s:grupos', auth.uid()), format('usuario:%s:pedidos', auth.uid()));
end;
$$;

revoke execute on function public.realtime_topic_allowed(text) from public, anon;
grant execute on function public.realtime_topic_allowed(text) to authenticated;

-- Solo lectura: sin política de insert, los clientes no pueden mandar
-- mensajes a estos canales.
create policy "realtime: escuchar mis canales"
  on realtime.messages for select to authenticated
  using (extension = 'broadcast' and public.realtime_topic_allowed((select realtime.topic())));

-- Triggers que avisan ----------------------------------------------------------

-- Para tablas con group_id. TG_ARGV[0] es el canal (archivos, tareas, …).
create or replace function public.avisar_grupo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  gid text := to_jsonb(coalesce(new, old)) ->> 'group_id';
begin
  perform realtime.send('{}'::jsonb, 'cambio', format('grupo:%s:%s', gid, tg_argv[0]), true);
  return null;
end;
$$;

-- groups y group_members: avisa a cada integrante (y a quien entra o sale).
create or replace function public.avisar_mis_grupos()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  fila jsonb := to_jsonb(coalesce(new, old));
  gid uuid := coalesce(fila ->> 'group_id', fila ->> 'id')::uuid;
  u uuid;
begin
  for u in
    select m.user_id from public.group_members m where m.group_id = gid
    union
    select (fila ->> 'user_id')::uuid where fila ? 'user_id'
  loop
    perform realtime.send('{}'::jsonb, 'cambio', format('usuario:%s:grupos', u), true);
  end loop;
  return null;
end;
$$;

-- Pedido de liberación: a quien tiene el archivo bloqueado.
create or replace function public.avisar_pedido()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform realtime.send(jsonb_build_object('pedido', new.id), 'pedido',
                        format('usuario:%s:pedidos', new.owner_id), true);
  return null;
end;
$$;

revoke execute on function public.avisar_grupo() from public, anon, authenticated;
revoke execute on function public.avisar_mis_grupos() from public, anon, authenticated;
revoke execute on function public.avisar_pedido() from public, anon, authenticated;

create trigger groups_avisar after insert or update or delete on public.groups
  for each row execute function public.avisar_mis_grupos();
create trigger group_members_avisar after insert or update or delete on public.group_members
  for each row execute function public.avisar_mis_grupos();

create trigger folders_avisar after insert or update or delete on public.folders
  for each row execute function public.avisar_grupo('archivos');
create trigger files_avisar after insert or update or delete on public.files
  for each row execute function public.avisar_grupo('archivos');
create trigger file_versions_avisar after insert or update or delete on public.file_versions
  for each row execute function public.avisar_grupo('archivos');
create trigger lock_requests_avisar after insert or update or delete on public.lock_requests
  for each row execute function public.avisar_grupo('archivos');
create trigger lock_requests_avisar_duenio after insert or update on public.lock_requests
  for each row execute function public.avisar_pedido();

create trigger tasks_avisar after insert or update or delete on public.tasks
  for each row execute function public.avisar_grupo('tareas');
create trigger activity_avisar after insert on public.activity
  for each row execute function public.avisar_grupo('actividad');
create trigger telegram_links_avisar after insert or update or delete on public.telegram_links
  for each row execute function public.avisar_grupo('telegram');

-- Sin eventos de filas --------------------------------------------------------

alter publication supabase_realtime drop table
  public.groups, public.group_members, public.folders, public.files, public.file_versions,
  public.lock_requests, public.tasks, public.activity, public.telegram_links;

alter table public.groups replica identity default;
alter table public.group_members replica identity default;
alter table public.folders replica identity default;
alter table public.files replica identity default;
alter table public.file_versions replica identity default;
alter table public.lock_requests replica identity default;
alter table public.tasks replica identity default;
alter table public.activity replica identity default;
alter table public.telegram_links replica identity default;
