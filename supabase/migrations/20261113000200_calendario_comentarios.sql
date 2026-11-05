-- Calendario de entregas y comentarios.

-- Eventos del grupo -----------------------------------------------------------------
-- Las fechas límite de las tareas ya van al calendario; esto suma lo que no es
-- una tarea: parciales, entregas a la cátedra, clases de consulta.

create type public.evento_tipo as enum ('parcial', 'entrega', 'clase', 'otro');

create table public.eventos (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  titulo     text not null check (char_length(trim(titulo)) between 1 and 120),
  tipo       public.evento_tipo not null default 'otro',
  fecha      date not null,
  hora       time,
  nota       text check (nota is null or char_length(nota) <= 500),
  created_by uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index eventos_grupo_fecha_idx on public.eventos (group_id, fecha);

alter table public.eventos enable row level security;

create policy "eventos: ver los de mis grupos"
  on public.eventos for select to authenticated
  using (public.is_group_member(group_id));

create policy "eventos: crear en mis grupos"
  on public.eventos for insert to authenticated
  with check (public.is_group_member(group_id) and created_by = (select auth.uid()));

create policy "eventos: editar quien lo creó o un admin"
  on public.eventos for update to authenticated
  using (public.is_group_member(group_id)
         and (created_by = (select auth.uid()) or public.is_group_admin(group_id)))
  with check (public.is_group_member(group_id));

create policy "eventos: borrar quien lo creó o un admin"
  on public.eventos for delete to authenticated
  using (public.is_group_member(group_id)
         and (created_by = (select auth.uid()) or public.is_group_admin(group_id)));

-- El cliente no elige id ni fecha de creación.
revoke insert, update on public.eventos from authenticated;
grant insert (group_id, titulo, tipo, fecha, hora, nota, created_by) on public.eventos to authenticated;
grant update (titulo, tipo, fecha, hora, nota) on public.eventos to authenticated;

create trigger eventos_avisar after insert or update or delete on public.eventos
  for each row execute function public.avisar_grupo('tareas');

create or replace function public.activity_eventos()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.log_activity(new.group_id, auth.uid(), 'evento_creado',
    jsonb_build_object('titulo', new.titulo, 'tipo', new.tipo, 'fecha', new.fecha));
  return null;
end;
$$;

revoke execute on function public.activity_eventos() from public, anon, authenticated;

create trigger eventos_activity after insert on public.eventos
  for each row execute function public.activity_eventos();

-- Comentarios en archivos ---------------------------------------------------------------

create table public.comentarios (
  id         uuid primary key default gen_random_uuid(),
  file_id    uuid not null references public.files (id) on delete cascade,
  group_id   uuid not null references public.groups (id) on delete cascade,
  autor      uuid references public.profiles (id) on delete set null default auth.uid(),
  texto      text not null check (char_length(trim(texto)) between 1 and 2000),
  -- A quiénes menciona con @usuario (lo completa un trigger; solo integrantes).
  menciones  uuid[] not null default '{}',
  created_at timestamptz not null default now()
);

create index comentarios_archivo_idx on public.comentarios (file_id, created_at);

alter table public.comentarios enable row level security;

create policy "comentarios: ver los de mis grupos"
  on public.comentarios for select to authenticated
  using (public.is_group_member(group_id));

create policy "comentarios: comentar archivos de mis grupos"
  on public.comentarios for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and autor = (select auth.uid())
    and exists (select 1 from public.files f
                where f.id = file_id and f.group_id = comentarios.group_id and f.deleted_at is null)
  );

create policy "comentarios: borrar los míos (o un admin)"
  on public.comentarios for delete to authenticated
  using (public.is_group_member(group_id)
         and (autor = (select auth.uid()) or public.is_group_admin(group_id)));

-- El cliente no elige id, fecha ni menciones (las calcula el trigger).
revoke insert, update on public.comentarios from authenticated;
grant insert (file_id, group_id, texto, autor) on public.comentarios to authenticated;

-- Menciones: @usuario de integrantes del grupo (el resto se ignora).
create or replace function public.comentarios_menciones()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.menciones := coalesce((
    select array_agg(distinct p.id)
    from regexp_matches(lower(new.texto), '@([a-z0-9][a-z0-9._]{1,18}[a-z0-9])', 'g') as m(u)
    join public.profiles p on p.username = m.u[1]
    join public.group_members gm on gm.user_id = p.id and gm.group_id = new.group_id
    where p.id is distinct from new.autor
  ), '{}');
  return new;
end;
$$;

revoke execute on function public.comentarios_menciones() from public, anon, authenticated;

create trigger comentarios_menciones before insert on public.comentarios
  for each row execute function public.comentarios_menciones();

-- En vivo: el hilo del archivo para todo el grupo, y un aviso a cada mencionado.
create or replace function public.avisar_comentario()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  fila public.comentarios := coalesce(new, old);
  u uuid;
begin
  perform realtime.send(jsonb_build_object('archivo', fila.file_id), 'cambio',
                        format('grupo:%s:comentarios', fila.group_id), true);
  if tg_op = 'INSERT' then
    foreach u in array new.menciones loop
      perform realtime.send(jsonb_build_object('comentario', new.id), 'mencion',
                            format('usuario:%s:menciones', u), true);
    end loop;
  end if;
  return null;
end;
$$;

revoke execute on function public.avisar_comentario() from public, anon, authenticated;

create trigger comentarios_avisar after insert or delete on public.comentarios
  for each row execute function public.avisar_comentario();

create or replace function public.activity_comentarios()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Sin el texto: si se borra el comentario, no queda copia en la actividad.
  perform public.log_activity(new.group_id, new.autor, 'comentario',
    jsonb_build_object('file_id', new.file_id,
                       'nombre', (select nombre from public.files where id = new.file_id)));
  return null;
end;
$$;

revoke execute on function public.activity_comentarios() from public, anon, authenticated;

create trigger comentarios_activity after insert on public.comentarios
  for each row execute function public.activity_comentarios();

-- Canales nuevos: grupo:{id}:comentarios y usuario:{id}:menciones.
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
                     format('usuario:%s:menciones', auth.uid()));
end;
$$;
