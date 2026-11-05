-- Docentes y cursos. Al registrarse se elige "estudiante" o "docente". Un
-- docente crea cursos ("Física II · Comisión 3") con un código; el admin de un
-- grupo lo suma al curso con ese código, y desde ahí el docente ve el grupo en
-- solo lectura: archivos y versiones, tareas, actividad y aportes, y puede
-- comentar. No edita nada ni entra como integrante.
--
-- El acceso del docente va en políticas aparte ("docente: …"), sumadas a las
-- de los integrantes, así las de siempre no cambian.

-- Tipo de cuenta -------------------------------------------------------------------

create type public.tipo_cuenta as enum ('estudiante', 'docente');

alter table public.profiles add column tipo_cuenta public.tipo_cuenta not null default 'estudiante';

-- Se puede cambiar desde el perfil (no da permisos sobre grupos ajenos: solo
-- deja crear cursos).
grant update (tipo_cuenta) on public.profiles to authenticated;

-- El tipo elegido al registrarse viene en los metadatos ('tipo').
create or replace function public.tipo_cuenta_desde_alta()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles
  set tipo_cuenta = case when new.raw_user_meta_data ->> 'tipo' = 'docente'
                         then 'docente'::public.tipo_cuenta else 'estudiante'::public.tipo_cuenta end
  where id = new.id;
  return new;
end;
$$;

revoke execute on function public.tipo_cuenta_desde_alta() from public, anon, authenticated;

-- Corre después de on_auth_user_created (los triggers van por orden alfabético).
create trigger on_auth_user_tipo
  after insert on auth.users
  for each row execute function public.tipo_cuenta_desde_alta();

-- Si se vuelve a registrar sin haber confirmado, vale el último intento.
create trigger on_auth_user_unconfirmed_tipo
  after update of raw_user_meta_data on auth.users
  for each row
  when (new.email_confirmed_at is null and new.raw_user_meta_data is distinct from old.raw_user_meta_data)
  execute function public.tipo_cuenta_desde_alta();

-- Cursos ---------------------------------------------------------------------------

create table public.cursos (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (char_length(trim(nombre)) between 1 and 120),
  codigo      text not null unique,
  docente_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index cursos_docente_idx on public.cursos (docente_id);

alter table public.groups add column curso_id uuid references public.cursos (id) on delete set null;
create index groups_curso_idx on public.groups (curso_id) where curso_id is not null;

-- ¿Soy el docente del curso de este grupo?
create or replace function public.es_docente_de_grupo(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.groups g
    join public.cursos c on c.id = g.curso_id
    join public.profiles p on p.id = c.docente_id
    where g.id = p_group_id and c.docente_id = auth.uid() and p.tipo_cuenta = 'docente'
  )
$$;

-- ¿Está [p_curso_id] en alguno de mis grupos? (para ver el curso y su docente)
create or replace function public.curso_de_mis_grupos(p_curso_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.groups g
    where g.curso_id = p_curso_id and public.is_group_member(g.id)
  )
$$;

-- ¿[p_user_id] es alumno de alguno de mis cursos? (el docente ve su perfil)
create or replace function public.es_mi_alumno(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    join public.cursos c on c.id = g.curso_id
    where gm.user_id = p_user_id and c.docente_id = auth.uid()
  )
$$;

-- ¿[p_user_id] es docente del curso de alguno de mis grupos? (lo veo al comentar)
create or replace function public.es_mi_docente(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.cursos c
    join public.groups g on g.curso_id = c.id
    where c.docente_id = p_user_id and public.is_group_member(g.id)
  )
$$;

revoke execute on function public.es_docente_de_grupo(uuid) from public, anon;
revoke execute on function public.curso_de_mis_grupos(uuid) from public, anon;
revoke execute on function public.es_mi_alumno(uuid) from public, anon;
revoke execute on function public.es_mi_docente(uuid) from public, anon;
grant execute on function public.es_docente_de_grupo(uuid) to authenticated;
grant execute on function public.curso_de_mis_grupos(uuid) to authenticated;
grant execute on function public.es_mi_alumno(uuid) to authenticated;
grant execute on function public.es_mi_docente(uuid) to authenticated;

alter table public.cursos enable row level security;

create policy "cursos: el docente ve los suyos"
  on public.cursos for select to authenticated
  using (docente_id = (select auth.uid()));

-- Los integrantes ven el curso de su grupo (nombre, docente y código: el
-- código es el que el docente reparte a toda la clase).
create policy "cursos: los grupos del curso lo ven"
  on public.cursos for select to authenticated
  using (public.curso_de_mis_grupos(id));

create policy "cursos: el docente cambia el nombre"
  on public.cursos for update to authenticated
  using (docente_id = (select auth.uid()))
  with check (docente_id = (select auth.uid()));

create policy "cursos: el docente lo borra"
  on public.cursos for delete to authenticated
  using (docente_id = (select auth.uid()));

-- Altas y códigos, solo con las funciones de abajo.
revoke insert, update on public.cursos from authenticated;
grant update (nombre) on public.cursos to authenticated;

create or replace function public.codigo_curso_nuevo()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  nuevo text;
begin
  loop
    nuevo := public.generate_invite_code();
    exit when not exists (select 1 from public.cursos c where c.codigo = nuevo);
  end loop;
  return nuevo;
end;
$$;

revoke execute on function public.codigo_curso_nuevo() from public, anon, authenticated;

create or replace function public.crear_curso(p_nombre text)
returns public.cursos
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cursos;
  nombre text := trim(coalesce(p_nombre, ''));
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and tipo_cuenta = 'docente') then
    raise exception 'Solo una cuenta de docente puede crear cursos' using errcode = 'P0001';
  end if;
  if char_length(nombre) not between 1 and 120 then
    raise exception 'Ingresá el nombre del curso (hasta 120 caracteres)' using errcode = 'P0001';
  end if;
  -- Dos altas a la vez no pasan el tope.
  perform pg_advisory_xact_lock(hashtext('cursos:' || auth.uid()::text));
  if (select count(*) from public.cursos where docente_id = auth.uid()) >= 50 then
    raise exception 'Llegaste al máximo de 50 cursos' using errcode = 'P0001';
  end if;
  insert into public.cursos (nombre, codigo, docente_id)
  values (nombre, public.codigo_curso_nuevo(), auth.uid())
  returning * into c;
  return c;
end;
$$;

create or replace function public.regenerar_codigo_curso(p_curso_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  nuevo text := public.codigo_curso_nuevo();
begin
  update public.cursos set codigo = nuevo where id = p_curso_id and docente_id = auth.uid();
  if not found then
    raise exception 'El curso no existe' using errcode = 'P0002';
  end if;
  return nuevo;
end;
$$;

-- El admin de un grupo lo suma a un curso con el código del docente.
create or replace function public.sumar_grupo_a_curso(p_group_id uuid, p_codigo text)
returns public.cursos
language plpgsql security definer set search_path = ''
as $$
declare
  c public.cursos;
  buscado text := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not public.is_group_admin(p_group_id) then
    raise exception 'Solo un admin del grupo puede sumarlo a un curso' using errcode = 'P0001';
  end if;
  select * into c from public.cursos x where x.codigo = buscado;
  if c.id is null then
    raise exception 'No encontramos un curso con ese código' using errcode = 'P0001';
  end if;
  -- Un grupo está en un curso a la vez: para cambiarlo, primero se quita.
  if exists (select 1 from public.groups where id = p_group_id and curso_id is not null and curso_id <> c.id for update) then
    raise exception 'El grupo ya está en otro curso: quitalo primero' using errcode = 'P0001';
  end if;
  update public.groups set curso_id = c.id where id = p_group_id;
  perform public.log_activity(p_group_id, auth.uid(), 'curso_sumado', jsonb_build_object('curso', c.nombre));
  return c;
end;
$$;

-- Lo saca un admin del grupo o el docente del curso.
create or replace function public.quitar_grupo_de_curso(p_group_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  curso text;
begin
  if not (public.is_group_admin(p_group_id) or public.es_docente_de_grupo(p_group_id)) then
    raise exception 'Solo un admin del grupo o el docente pueden hacerlo' using errcode = 'P0001';
  end if;
  select c.nombre into curso from public.groups g join public.cursos c on c.id = g.curso_id where g.id = p_group_id;
  if curso is null then
    return;
  end if;
  update public.groups set curso_id = null where id = p_group_id;
  perform public.log_activity(p_group_id, auth.uid(), 'curso_quitado', jsonb_build_object('curso', curso));
end;
$$;

revoke execute on function public.crear_curso(text) from public, anon;
revoke execute on function public.regenerar_codigo_curso(uuid) from public, anon;
revoke execute on function public.sumar_grupo_a_curso(uuid, text) from public, anon;
revoke execute on function public.quitar_grupo_de_curso(uuid) from public, anon;
grant execute on function public.crear_curso(text) to authenticated;
grant execute on function public.regenerar_codigo_curso(uuid) to authenticated;
grant execute on function public.sumar_grupo_a_curso(uuid, text) to authenticated;
grant execute on function public.quitar_grupo_de_curso(uuid) to authenticated;

-- Lo que ve el docente (solo lectura) -------------------------------------------------

-- El docente NO lee la tabla groups: tiene el código de invitación, y con él
-- podría entrar como integrante. Lo que necesita lo dan estas funciones.

-- Mis cursos, con cuántos grupos tiene cada uno.
create or replace function public.mis_cursos()
returns table (id uuid, nombre text, codigo text, docente_id uuid, created_at timestamptz, cantidad_grupos integer)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.nombre, c.codigo, c.docente_id, c.created_at,
         (select count(*)::int from public.groups g where g.curso_id = c.id)
  from public.cursos c
  where c.docente_id = auth.uid()
  order by c.created_at desc
$$;

-- Los grupos de un curso mío: integrantes, estado de las tareas y materias.
create or replace function public.grupos_del_curso(p_curso_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id,
           'nombre', g.nombre,
           'integrantes', (select coalesce(jsonb_agg(p.nombre order by p.nombre), '[]')
                           from public.group_members gm join public.profiles p on p.id = gm.user_id
                           where gm.group_id = g.id),
           'tareas', (select coalesce(jsonb_agg(t.estado), '[]') from public.tasks t where t.group_id = g.id),
           'materias', (select coalesce(jsonb_agg(f.nombre order by f.nombre), '[]')
                        from public.folders f where f.group_id = g.id and f.es_materia))
         order by g.nombre), '[]')
  from public.groups g
  join public.cursos c on c.id = g.curso_id
  where c.id = p_curso_id and c.docente_id = auth.uid()
$$;

-- Un grupo de mi curso, sin el código de invitación ni datos del plan.
create or replace function public.grupo_para_docente(p_group_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id, 'nombre', g.nombre, 'created_at', g.created_at, 'created_by', g.created_by,
    'aprobar_tareas', g.aprobar_tareas, 'curso_id', g.curso_id,
    'curso', jsonb_build_object('nombre', c.nombre),
    'cantidad_miembros', (select count(*) from public.group_members gm where gm.group_id = g.id),
    'materias', (select coalesce(jsonb_agg(jsonb_build_object('nombre', f.nombre, 'es_materia', true)), '[]')
                 from public.folders f where f.group_id = g.id and f.es_materia))
  from public.groups g
  join public.cursos c on c.id = g.curso_id
  where g.id = p_group_id and public.es_docente_de_grupo(g.id)
$$;

revoke execute on function public.mis_cursos() from public, anon;
revoke execute on function public.grupos_del_curso(uuid) from public, anon;
revoke execute on function public.grupo_para_docente(uuid) from public, anon;
grant execute on function public.mis_cursos() to authenticated;
grant execute on function public.grupos_del_curso(uuid) to authenticated;
grant execute on function public.grupo_para_docente(uuid) to authenticated;

-- Y aunque consiguiera un código, el docente no entra como integrante.
create or replace function public.join_group(p_code text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  g public.groups;
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  select * into g from public.groups
  where invite_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));

  if g.id is null then
    raise exception 'Código de invitación inválido' using errcode = 'P0002';
  end if;
  if public.es_docente_de_grupo(g.id) then
    raise exception 'Sos docente del curso de este grupo: lo ves desde tus cursos' using errcode = 'P0001';
  end if;

  insert into public.group_members (group_id, user_id, rol)
  values (g.id, auth.uid(), 'miembro')
  on conflict do nothing;

  return g;
end;
$$;

create policy "docente: ver integrantes"
  on public.group_members for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: ver a sus alumnos"
  on public.profiles for select to authenticated
  using (public.es_mi_alumno(id));

create policy "integrantes: ver a su docente"
  on public.profiles for select to authenticated
  using (public.es_mi_docente(id));

create policy "docente: ver carpetas"
  on public.folders for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: ver archivos"
  on public.files for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: ver versiones visibles"
  on public.file_versions for select to authenticated
  using (public.es_docente_de_grupo(group_id) and public.version_visible(file_id, version_number));

create policy "docente: ver tareas"
  on public.tasks for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: ver actividad"
  on public.activity for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: ver comentarios"
  on public.comentarios for select to authenticated
  using (public.es_docente_de_grupo(group_id));

create policy "docente: comentar"
  on public.comentarios for insert to authenticated
  with check (
    public.es_docente_de_grupo(group_id)
    and autor = (select auth.uid())
    and exists (select 1 from public.files f
                where f.id = file_id and f.group_id = comentarios.group_id and f.deleted_at is null)
  );

create policy "docente: borrar sus comentarios"
  on public.comentarios for delete to authenticated
  using (public.es_docente_de_grupo(group_id) and autor = (select auth.uid()));

create policy "docente: leer archivos visibles"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'archivos'
    and public.es_docente_de_grupo(((storage.foldername(name))[2])::uuid)
    and public.storage_object_readable(name)
  );

-- Aportes: también los ve el docente.
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
  if not (public.is_group_member(p_group_id) or public.es_docente_de_grupo(p_group_id)) then
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

-- En vivo: el docente escucha archivos, tareas, actividad y comentarios de los
-- grupos de sus cursos (no documentos en edición ni Telegram).
create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram|documentos|comentarios)$');
  if m is not null then
    return public.is_group_member(m[1]::uuid)
        or (m[2] in ('archivos', 'tareas', 'actividad', 'comentarios') and public.es_docente_de_grupo(m[1]::uuid));
  end if;
  return auth.uid() is not null
     and p_topic in (format('usuario:%s:grupos', auth.uid()),
                     format('usuario:%s:pedidos', auth.uid()),
                     format('usuario:%s:menciones', auth.uid()),
                     format('usuario:%s:tareas', auth.uid()));
end;
$$;
