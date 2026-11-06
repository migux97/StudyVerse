-- Varios docentes por curso y tablero del curso.
--
-- El titular (cursos.docente_id) suma ayudantes (otras cuentas de docente) por
-- su @usuario. Un ayudante ve y hace lo mismo que el titular con los grupos del
-- curso (verlos, comentar, avisos, devoluciones, entregas y notas), pero no
-- cambia el curso: nombre, código, borrarlo y los ayudantes son del titular.
--
-- Todo lo que preguntaba "¿soy el docente?" pasa por es_docente_del_curso, así
-- las políticas "docente: …" ya existentes valen también para los ayudantes.

-- Tipos nuevos de notificación: curso (te sumaron), entrega (TP nuevo o un grupo
-- entregó) y nota (corrigieron la entrega de tu grupo).
alter table public.notificaciones drop constraint notificaciones_tipo_check;
alter table public.notificaciones add constraint notificaciones_tipo_check
  check (tipo in ('mencion', 'aviso', 'devolucion', 'revision', 'pedido', 'tarea_asignada', 'chat',
                  'curso', 'entrega', 'nota'));

create table public.curso_docentes (
  curso_id    uuid not null references public.cursos (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (curso_id, user_id)
);

create index curso_docentes_user_idx on public.curso_docentes (user_id);

-- ¿[p_user_id] es docente (titular o ayudante) de [p_curso_id]?
create or replace function public.es_docente_del_curso(p_curso_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_curso_id is not null and p_user_id is not null
     and exists (select 1 from public.profiles p where p.id = p_user_id and p.tipo_cuenta = 'docente')
     and (exists (select 1 from public.cursos c where c.id = p_curso_id and c.docente_id = p_user_id)
          or exists (select 1 from public.curso_docentes d where d.curso_id = p_curso_id and d.user_id = p_user_id))
$$;

revoke execute on function public.es_docente_del_curso(uuid, uuid) from public, anon;
grant execute on function public.es_docente_del_curso(uuid, uuid) to authenticated;

create or replace function public.soy_docente_del_curso(p_curso_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.es_docente_del_curso(p_curso_id, auth.uid())
$$;

create or replace function public.soy_titular_del_curso(p_curso_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.cursos c join public.profiles p on p.id = c.docente_id
    where c.id = p_curso_id and c.docente_id = auth.uid() and p.tipo_cuenta = 'docente'
  )
$$;

revoke execute on function public.soy_titular_del_curso(uuid) from public, anon;
grant execute on function public.soy_titular_del_curso(uuid) to authenticated;

create or replace function public.es_docente_de_grupo(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.es_docente_del_curso((select g.curso_id from public.groups g where g.id = p_group_id), auth.uid())
$$;

create or replace function public.es_mi_alumno(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members gm
    join public.groups g on g.id = gm.group_id
    where gm.user_id = p_user_id and g.curso_id is not null
      and public.es_docente_del_curso(g.curso_id, auth.uid())
  )
$$;

create or replace function public.es_mi_docente(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.groups g
    where g.curso_id is not null and public.is_group_member(g.id)
      and public.es_docente_del_curso(g.curso_id, p_user_id)
  )
$$;

-- ¿[p_user_id] da clases conmigo en algún curso? (titular y ayudantes se ven)
create or replace function public.es_mi_colega(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.cursos c
    where public.es_docente_del_curso(c.id, auth.uid())
      and public.es_docente_del_curso(c.id, p_user_id)
      and (c.docente_id in (auth.uid(), p_user_id)
           or exists (select 1 from public.curso_docentes d where d.curso_id = c.id and d.user_id in (auth.uid(), p_user_id)))
  )
$$;

revoke execute on function public.es_mi_colega(uuid) from public, anon;
grant execute on function public.es_mi_colega(uuid) to authenticated;

create policy "docente: ver a los docentes de sus cursos"
  on public.profiles for select to authenticated
  using (public.es_mi_colega(id));

-- El ayudante ve el curso (no lo cambia: las políticas de update/delete son del titular).
create policy "cursos: los ayudantes lo ven"
  on public.cursos for select to authenticated
  using (exists (select 1 from public.curso_docentes d where d.curso_id = cursos.id and d.user_id = (select auth.uid())));

alter table public.curso_docentes enable row level security;
revoke all on public.curso_docentes from anon;
revoke insert, update, delete on public.curso_docentes from authenticated;

create policy "curso_docentes: los ven los docentes del curso"
  on public.curso_docentes for select to authenticated
  using (user_id = (select auth.uid()) or public.soy_docente_del_curso(curso_id));

-- Sumar un ayudante por su @usuario (solo el titular).
create or replace function public.sumar_ayudante(p_curso_id uuid, p_usuario text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  buscado text := lower(trim(leading '@' from trim(coalesce(p_usuario, ''))));
  u public.profiles;
  curso text;
begin
  if not public.soy_titular_del_curso(p_curso_id) then
    raise exception 'Solo quien creó el curso puede sumar docentes' using errcode = 'P0001';
  end if;
  select * into u from public.profiles where username = buscado;
  if u.id is null or u.tipo_cuenta <> 'docente' then
    raise exception 'No encontramos una cuenta de docente con ese usuario' using errcode = 'P0001';
  end if;
  if u.id = auth.uid() then
    raise exception 'Ya sos el docente de este curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.group_members gm join public.groups g on g.id = gm.group_id
             where gm.user_id = u.id and g.curso_id = p_curso_id) then
    raise exception 'Esa persona es integrante de un grupo del curso' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('ayudantes:' || p_curso_id::text));
  if (select count(*) from public.curso_docentes where curso_id = p_curso_id) >= 10 then
    raise exception 'Un curso puede tener hasta 10 docentes ayudantes' using errcode = 'P0001';
  end if;
  insert into public.curso_docentes (curso_id, user_id) values (p_curso_id, u.id)
  on conflict do nothing;
  if found then
    select nombre into curso from public.cursos where id = p_curso_id;
    perform public.notificar(u.id, 'curso',
      left(format('%s te sumó como docente de %s', public.nombre_de(auth.uid()), curso), 200),
      null, format('/cursos/%s', p_curso_id), null);
  end if;
  return jsonb_build_object('id', u.id, 'nombre', u.nombre, 'username', u.username, 'titular', false);
end;
$$;

-- Lo saca el titular, o el ayudante se va solo.
create or replace function public.quitar_ayudante(p_curso_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not (public.soy_titular_del_curso(p_curso_id) or p_user_id = auth.uid()) then
    raise exception 'Solo quien creó el curso puede quitar docentes' using errcode = 'P0001';
  end if;
  delete from public.curso_docentes where curso_id = p_curso_id and user_id = p_user_id;
end;
$$;

-- Titular y ayudantes, para la pantalla del curso.
create or replace function public.docentes_del_curso(p_curso_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x order by (x->>'titular')::boolean desc, x->>'nombre'), '[]')
  from (
    select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'username', p.username,
                              'avatar_url', p.avatar_url, 'titular', true) as x
    from public.cursos c join public.profiles p on p.id = c.docente_id
    where c.id = p_curso_id
    union all
    select jsonb_build_object('id', p.id, 'nombre', p.nombre, 'username', p.username,
                              'avatar_url', p.avatar_url, 'titular', false)
    from public.curso_docentes d join public.profiles p on p.id = d.user_id
    where d.curso_id = p_curso_id
  ) t
  where public.soy_docente_del_curso(p_curso_id)
$$;

revoke execute on function public.sumar_ayudante(uuid, text) from public, anon;
revoke execute on function public.quitar_ayudante(uuid, uuid) from public, anon;
revoke execute on function public.docentes_del_curso(uuid) from public, anon;
grant execute on function public.sumar_ayudante(uuid, text) to authenticated;
grant execute on function public.quitar_ayudante(uuid, uuid) to authenticated;
grant execute on function public.docentes_del_curso(uuid) to authenticated;

-- Mis cursos: los que doy y en los que soy ayudante.
drop function public.mis_cursos();
create function public.mis_cursos()
returns table (id uuid, nombre text, codigo text, docente_id uuid, created_at timestamptz,
               cantidad_grupos integer, soy_titular boolean)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.nombre, c.codigo, c.docente_id, c.created_at,
         (select count(*)::int from public.groups g where g.curso_id = c.id),
         c.docente_id = auth.uid()
  from public.cursos c
  where public.es_docente_del_curso(c.id, auth.uid())
  order by c.created_at desc
$$;

revoke execute on function public.mis_cursos() from public, anon;
grant execute on function public.mis_cursos() to authenticated;

-- Tablero: cada grupo con integrantes, tareas, materias y cuánto se mueve.
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
           'tareas_vencidas', (select count(*) from public.tasks t
                               where t.group_id = g.id and t.estado <> 'hecha' and t.due_date < current_date),
           'materias', (select coalesce(jsonb_agg(f.nombre order by f.nombre), '[]')
                        from public.folders f where f.group_id = g.id and f.es_materia),
           'ultima_actividad', (select max(a.created_at) from public.activity a where a.group_id = g.id),
           'versiones_semana', (select count(*) from public.file_versions v
                                where v.group_id = g.id and v.created_at > now() - interval '7 days'))
         order by g.nombre), '[]')
  from public.groups g
  where g.curso_id = p_curso_id and public.soy_docente_del_curso(p_curso_id)
$$;

-- Aportes de cada alumno del curso (para evaluar a cada uno y exportar).
create or replace function public.aportes_del_curso(p_curso_id uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', m.user_id,
           'nombre', p.nombre,
           'username', p.username,
           'group_id', g.id,
           'grupo', g.nombre,
           'tareas_hechas', (select count(*) from public.tasks t
                             where t.group_id = g.id and t.assigned_to = m.user_id and t.estado = 'hecha'),
           'tareas_pendientes', (select count(*) from public.tasks t
                                 where t.group_id = g.id and t.assigned_to = m.user_id and t.estado <> 'hecha'),
           'versiones', (select count(*) from public.file_versions v
                         where v.group_id = g.id and v.uploaded_by = m.user_id),
           'comentarios', (select count(*) from public.comentarios c
                           where c.group_id = g.id and c.autor = m.user_id),
           'ultima_actividad', (select max(a.created_at) from public.activity a
                                where a.group_id = g.id and a.user_id = m.user_id))
         order by g.nombre, p.nombre), '[]')
  from public.groups g
  join public.group_members m on m.group_id = g.id
  join public.profiles p on p.id = m.user_id
  where g.curso_id = p_curso_id and public.soy_docente_del_curso(p_curso_id)
$$;

revoke execute on function public.aportes_del_curso(uuid) from public, anon;
grant execute on function public.aportes_del_curso(uuid) to authenticated;
