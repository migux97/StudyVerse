-- Avisos y devoluciones del docente.
--
-- Avisos: el docente de un curso escribe a todos los grupos del curso o a uno
-- solo ("El parcial pasa al jueves"). Los ven los integrantes de esos grupos y
-- les llega un aviso en vivo.
--
-- Devoluciones: el docente comenta una tarea de un grupo de su curso ("Bien la
-- introducción, falta citar"). Las ve todo el grupo y avisa en vivo a quien
-- tiene la tarea y a quien la entregó.

create or replace function public.soy_docente_del_curso(p_curso_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.cursos c join public.profiles p on p.id = c.docente_id
    where c.id = p_curso_id and c.docente_id = auth.uid() and p.tipo_cuenta = 'docente'
  )
$$;

revoke execute on function public.soy_docente_del_curso(uuid) from public, anon;
grant execute on function public.soy_docente_del_curso(uuid) to authenticated;

-- Avisos -------------------------------------------------------------------------

create table public.avisos (
  id          uuid primary key default gen_random_uuid(),
  curso_id    uuid not null references public.cursos (id) on delete cascade,
  -- null = a todos los grupos del curso.
  group_id    uuid references public.groups (id) on delete cascade,
  autor       uuid references public.profiles (id) on delete set null,
  texto       text not null check (char_length(trim(texto)) between 1 and 2000),
  created_at  timestamptz not null default now()
);

create index avisos_curso_idx on public.avisos (curso_id, created_at desc);
create index avisos_grupo_idx on public.avisos (group_id, created_at desc) where group_id is not null;
create index avisos_autor_idx on public.avisos (autor, created_at desc);

alter table public.avisos enable row level security;

create policy "avisos: el docente ve los de su curso"
  on public.avisos for select to authenticated
  using (public.soy_docente_del_curso(curso_id));

-- Un integrante ve los avisos a todo el curso de su grupo (solo mientras el
-- grupo siga en ese curso) y los dirigidos a su grupo.
create policy "avisos: los integrantes ven los suyos"
  on public.avisos for select to authenticated
  using (
    case when group_id is null
         then public.curso_de_mis_grupos(curso_id)
         else public.is_group_member(group_id)
              and exists (select 1 from public.groups g where g.id = group_id and g.curso_id = avisos.curso_id)
    end
  );

create policy "avisos: el docente borra los suyos"
  on public.avisos for delete to authenticated
  using (autor = (select auth.uid()) and public.soy_docente_del_curso(curso_id));

-- Se mandan con mandar_aviso.
revoke insert, update on public.avisos from authenticated;

create or replace function public.mandar_aviso(p_curso_id uuid, p_group_id uuid, p_texto text)
returns public.avisos
language plpgsql security definer set search_path = ''
as $$
declare
  a public.avisos;
  texto text := trim(coalesce(p_texto, ''));
begin
  if not public.soy_docente_del_curso(p_curso_id) then
    raise exception 'Solo el docente del curso puede mandar avisos' using errcode = 'P0001';
  end if;
  if char_length(texto) not between 1 and 2000 then
    raise exception 'Escribí el aviso (hasta 2000 caracteres)' using errcode = 'P0001';
  end if;
  if p_group_id is not null
     and not exists (select 1 from public.groups where id = p_group_id and curso_id = p_curso_id) then
    raise exception 'Ese grupo no está en el curso' using errcode = 'P0001';
  end if;
  -- Cada aviso le llega a toda la clase: hasta 20 por hora.
  perform pg_advisory_xact_lock(hashtext('avisos:' || auth.uid()::text));
  if (select count(*) from public.avisos
      where autor = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Mandaste muchos avisos seguidos. Probá de nuevo en un rato' using errcode = 'P0001';
  end if;
  insert into public.avisos (curso_id, group_id, autor, texto)
  values (p_curso_id, p_group_id, auth.uid(), texto)
  returning * into a;
  return a;
end;
$$;

revoke execute on function public.mandar_aviso(uuid, uuid, text) from public, anon;
grant execute on function public.mandar_aviso(uuid, uuid, text) to authenticated;

-- En vivo: cada grupo destinatario se entera (para la lista) y cada integrante
-- recibe un aviso con solo el id (la app lo lee con su RLS). Además queda en
-- la actividad del grupo, sin copiar el texto.
create or replace function public.avisar_aviso()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  g uuid;
  u uuid;
begin
  for g in
    select id from public.groups
    where curso_id = new.curso_id and (new.group_id is null or id = new.group_id)
  loop
    perform realtime.send('{}'::jsonb, 'cambio', format('grupo:%s:avisos', g), true);
    perform public.log_activity(g, new.autor, 'aviso_docente', '{}'::jsonb);
    for u in select user_id from public.group_members where group_id = g loop
      perform realtime.send(jsonb_build_object('aviso', new.id), 'aviso', format('usuario:%s:avisos', u), true);
    end loop;
  end loop;
  return null;
end;
$$;

revoke execute on function public.avisar_aviso() from public, anon, authenticated;

create trigger avisos_avisar after insert on public.avisos
  for each row execute function public.avisar_aviso();

-- Al borrar un aviso, las listas de los grupos se actualizan en vivo.
create or replace function public.avisar_aviso_borrado()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  g uuid;
begin
  for g in
    select id from public.groups
    where curso_id = old.curso_id and (old.group_id is null or id = old.group_id)
  loop
    perform realtime.send('{}'::jsonb, 'cambio', format('grupo:%s:avisos', g), true);
  end loop;
  return null;
end;
$$;

revoke execute on function public.avisar_aviso_borrado() from public, anon, authenticated;

create trigger avisos_avisar_borrado after delete on public.avisos
  for each row execute function public.avisar_aviso_borrado();

-- Devoluciones en tareas ----------------------------------------------------------

create table public.devoluciones (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid not null references public.tasks (id) on delete cascade,
  group_id    uuid not null references public.groups (id) on delete cascade,
  autor       uuid references public.profiles (id) on delete set null default auth.uid(),
  texto       text not null check (char_length(trim(texto)) between 1 and 2000),
  created_at  timestamptz not null default now()
);

create index devoluciones_tarea_idx on public.devoluciones (task_id, created_at);
create index devoluciones_grupo_idx on public.devoluciones (group_id);
create index devoluciones_autor_idx on public.devoluciones (autor, created_at desc);

alter table public.devoluciones enable row level security;

create policy "devoluciones: las ve el grupo y su docente"
  on public.devoluciones for select to authenticated
  using (public.is_group_member(group_id) or public.es_docente_de_grupo(group_id));

create policy "devoluciones: las escribe el docente"
  on public.devoluciones for insert to authenticated
  with check (
    public.es_docente_de_grupo(group_id)
    and autor = (select auth.uid())
    and exists (select 1 from public.tasks t where t.id = task_id and t.group_id = devoluciones.group_id)
  );

create policy "devoluciones: el docente borra las suyas"
  on public.devoluciones for delete to authenticated
  using (autor = (select auth.uid()) and public.es_docente_de_grupo(group_id));

-- El cliente no elige id ni fecha.
revoke insert, update on public.devoluciones from authenticated;
grant insert (task_id, group_id, texto, autor) on public.devoluciones to authenticated;

-- Hasta 60 devoluciones por hora (cada una avisa al grupo).
create or replace function public.devoluciones_tope()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('devoluciones:' || coalesce(new.autor::text, '')));
  if (select count(*) from public.devoluciones
      where autor = new.autor and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Mandaste muchas devoluciones seguidas. Probá de nuevo en un rato' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.devoluciones_tope() from public, anon, authenticated;

create trigger devoluciones_tope before insert on public.devoluciones
  for each row execute function public.devoluciones_tope();

create trigger devoluciones_avisar after insert or delete on public.devoluciones
  for each row execute function public.avisar_grupo('tareas');

create or replace function public.avisar_devolucion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  t public.tasks;
  u uuid;
begin
  select * into t from public.tasks where id = new.task_id;
  perform public.log_activity(new.group_id, new.autor, 'devolucion',
    jsonb_build_object('task_id', t.id, 'titulo', t.titulo));
  for u in select distinct x from unnest(array[t.assigned_to, t.entregada_por]) as x
           where x is not null and public.is_member_of(new.group_id, x) loop
    -- Mismo evento que los avisos: la app escucha un solo canal y mira la clave.
    perform realtime.send(jsonb_build_object('devolucion', new.id), 'aviso',
                          format('usuario:%s:avisos', u), true);
  end loop;
  return null;
end;
$$;

revoke execute on function public.avisar_devolucion() from public, anon, authenticated;

create trigger devoluciones_aviso after insert on public.devoluciones
  for each row execute function public.avisar_devolucion();

-- Canales nuevos: grupo:{id}:avisos (integrantes y docente) y usuario:{id}:avisos.
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
                     format('usuario:%s:avisos', auth.uid()));
end;
$$;
