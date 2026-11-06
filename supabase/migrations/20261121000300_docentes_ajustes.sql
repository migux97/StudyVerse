-- Ajustes de la revisión de las funciones para docentes.

-- Las entregas son del curso del trabajo (no del curso en el que esté hoy el
-- grupo): si el grupo se cambia de curso, el docente nuevo no ve ni califica
-- lo que se entregó en el anterior.
drop policy "entregas: las ven el grupo y sus docentes" on public.entregas;
create policy "entregas: las ven el grupo y los docentes del trabajo"
  on public.entregas for select to authenticated
  using (
    public.is_group_member(group_id)
    or exists (select 1 from public.trabajos t
               where t.id = entregas.trabajo_id and public.soy_docente_del_curso(t.curso_id))
  );

-- "8", "8,5": la nota como se escribe acá (to_char redondea los decimales).
create or replace function public.nota_texto(p_nota numeric)
returns text
language sql immutable set search_path = ''
as $$
  select replace(case when p_nota = trunc(p_nota) then trunc(p_nota)::text
                      else rtrim(p_nota::text, '0') end, '.', ',')
$$;

-- Nadie se corrige a sí mismo, y se corrige solo como docente del curso del trabajo.
create or replace function public.corregir_entrega(p_entrega_id uuid, p_estado text, p_nota numeric, p_devolucion text)
returns public.entregas
language plpgsql security definer set search_path = ''
as $$
declare
  e public.entregas;
  t public.trabajos;
  etiqueta text;
begin
  select * into e from public.entregas where id = p_entrega_id for update;
  select * into t from public.trabajos where id = e.trabajo_id;
  if e.id is null or not public.soy_docente_del_curso(t.curso_id) then
    raise exception 'Esa entrega no existe' using errcode = 'P0002';
  end if;
  if public.is_group_member(e.group_id) then
    raise exception 'No podés corregir la entrega de un grupo del que sos integrante' using errcode = 'P0001';
  end if;
  if p_estado is null or p_estado not in ('aprobada', 'a_rehacer', 'desaprobada') then
    raise exception 'Elegí cómo quedó la entrega' using errcode = 'P0001';
  end if;
  if p_nota is not null and (p_nota < 0 or p_nota > t.nota_maxima) then
    raise exception 'La nota va de 0 a %', public.nota_texto(t.nota_maxima) using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_devolucion, '')) > 4000 then
    raise exception 'La devolución puede tener hasta 4000 caracteres' using errcode = 'P0001';
  end if;

  update public.entregas
  set estado = p_estado, nota = p_nota, devolucion = nullif(trim(coalesce(p_devolucion, '')), ''),
      corregida_por = auth.uid(), corregida_at = now()
  where id = p_entrega_id
  returning * into e;

  etiqueta := case p_estado when 'aprobada' then 'Aprobado' when 'a_rehacer' then 'A rehacer' else 'Desaprobado' end
              || coalesce(' · ' || public.nota_texto(p_nota), '');
  perform public.log_activity(e.group_id, auth.uid(), 'trabajo_corregido',
    jsonb_build_object('trabajo', t.titulo, 'resultado', etiqueta));

  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select gm.user_id, 'nota', left(format('Corrigieron %s: %s', t.titulo, etiqueta), 200),
         left(e.devolucion, 300), format('/grupos/%s/entregas', e.group_id), e.group_id
  from public.group_members gm
  where gm.group_id = e.group_id;
  return e;
end;
$$;

-- Un grupo con un docente del curso entre sus integrantes no se suma al curso.
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
  if exists (select 1 from public.group_members gm
             where gm.group_id = p_group_id and public.es_docente_del_curso(c.id, gm.user_id)) then
    raise exception 'Un docente del curso no puede ser integrante de un grupo del curso' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.groups where id = p_group_id and curso_id is not null and curso_id <> c.id for update) then
    raise exception 'El grupo ya está en otro curso: quitalo primero' using errcode = 'P0001';
  end if;
  update public.groups set curso_id = c.id where id = p_group_id;
  perform public.log_activity(p_group_id, auth.uid(), 'curso_sumado', jsonb_build_object('curso', c.nombre));
  return c;
end;
$$;

-- Topes que no se saltean borrando: se cuentan en un registro aparte.
create table public.envios_curso (
  curso_id    uuid not null references public.cursos (id) on delete cascade,
  tipo        text not null check (tipo in ('trabajo', 'material', 'fecha')),
  created_at  timestamptz not null default now()
);

create index envios_curso_idx on public.envios_curso (curso_id, tipo, created_at desc);
alter table public.envios_curso enable row level security;
revoke all on public.envios_curso from anon, authenticated;

-- Cuenta y registra: true si todavía hay lugar hoy.
create or replace function public.hay_lugar(p_curso_id uuid, p_tipo text, p_tope integer)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('envios:' || p_curso_id::text || p_tipo));
  if (select count(*) from public.envios_curso
      where curso_id = p_curso_id and tipo = p_tipo and created_at > now() - interval '1 day') >= p_tope then
    return false;
  end if;
  insert into public.envios_curso (curso_id, tipo) values (p_curso_id, p_tipo);
  return true;
end;
$$;

revoke execute on function public.hay_lugar(uuid, text, integer) from public, anon, authenticated;

create or replace function public.crear_trabajo(
  p_curso_id uuid, p_titulo text, p_consigna text, p_vence_at timestamptz, p_nota_maxima numeric default 10
)
returns public.trabajos
language plpgsql security definer set search_path = ''
as $$
declare
  t public.trabajos;
  curso text;
begin
  if not public.soy_docente_del_curso(p_curso_id) then
    raise exception 'Solo los docentes del curso pueden crear trabajos' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_titulo, ''))) not between 1 and 120 then
    raise exception 'Ingresá el nombre del trabajo (hasta 120 caracteres)' using errcode = 'P0001';
  end if;
  if p_vence_at is null then
    raise exception 'Elegí cuándo vence' using errcode = 'P0001';
  end if;
  if coalesce(p_nota_maxima, 10) <= 0 or coalesce(p_nota_maxima, 10) > 100 then
    raise exception 'La nota máxima va de 1 a 100' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_consigna, '')) > 4000 then
    raise exception 'La consigna puede tener hasta 4000 caracteres' using errcode = 'P0001';
  end if;
  if not public.hay_lugar(p_curso_id, 'trabajo', 20) then
    raise exception 'Creaste muchos trabajos hoy. Probá mañana' using errcode = 'P0001';
  end if;
  insert into public.trabajos (curso_id, titulo, consigna, vence_at, nota_maxima)
  values (p_curso_id, trim(p_titulo), nullif(trim(coalesce(p_consigna, '')), ''), p_vence_at, coalesce(p_nota_maxima, 10))
  returning * into t;

  select nombre into curso from public.cursos where id = p_curso_id;
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select gm.user_id, 'entrega', left(format('Nuevo trabajo en %s: %s', curso, t.titulo), 200),
         'Vence el ' || to_char(t.vence_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM "a las" HH24:MI'),
         format('/grupos/%s/entregas', g.id), g.id
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  where g.curso_id = p_curso_id;
  return t;
end;
$$;

create or replace function public.editar_trabajo(
  p_trabajo_id uuid, p_titulo text, p_consigna text, p_vence_at timestamptz, p_nota_maxima numeric
)
returns public.trabajos
language plpgsql security definer set search_path = ''
as $$
declare
  t public.trabajos;
begin
  select * into t from public.trabajos where id = p_trabajo_id for update;
  if t.id is null or not public.soy_docente_del_curso(t.curso_id) then
    raise exception 'Ese trabajo no existe' using errcode = 'P0002';
  end if;
  if char_length(trim(coalesce(p_titulo, ''))) not between 1 and 120 or p_vence_at is null then
    raise exception 'Completá el nombre y el vencimiento' using errcode = 'P0001';
  end if;
  if p_nota_maxima is not null and (p_nota_maxima <= 0 or p_nota_maxima > 100) then
    raise exception 'La nota máxima va de 1 a 100' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_consigna, '')) > 4000 then
    raise exception 'La consigna puede tener hasta 4000 caracteres' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.entregas e where e.trabajo_id = p_trabajo_id and e.nota > p_nota_maxima) then
    raise exception 'Hay notas más altas que la nota máxima nueva' using errcode = 'P0001';
  end if;
  update public.trabajos
  set titulo = trim(p_titulo), consigna = nullif(trim(coalesce(p_consigna, '')), ''),
      vence_at = p_vence_at, nota_maxima = coalesce(p_nota_maxima, nota_maxima)
  where id = p_trabajo_id
  returning * into t;
  return t;
end;
$$;

-- Reentregar después de "a rehacer" borra la nota anterior (la devolución queda
-- como referencia), y dos entregas a la vez no avisan dos veces.
create or replace function public.entregar_trabajo(p_trabajo_id uuid, p_group_id uuid, p_file_id uuid)
returns public.entregas
language plpgsql security definer set search_path = ''
as $$
declare
  t public.trabajos;
  f public.files;
  anterior public.entregas;
  e public.entregas;
  version integer;
  grupo text;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;
  select * into t from public.trabajos where id = p_trabajo_id;
  if t.id is null or not exists (select 1 from public.groups g where g.id = p_group_id and g.curso_id = t.curso_id) then
    raise exception 'Ese trabajo no es del curso de tu grupo' using errcode = 'P0001';
  end if;
  select * into f from public.files where id = p_file_id and group_id = p_group_id and deleted_at is null;
  if f.id is null then
    raise exception 'Elegí un archivo del grupo' using errcode = 'P0001';
  end if;
  select max(v.version_number) into version from public.file_versions v where v.file_id = f.id;
  if version is null then
    raise exception 'Ese archivo todavía no tiene versiones' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('entrega:' || p_trabajo_id::text || p_group_id::text));
  select * into anterior from public.entregas
  where trabajo_id = p_trabajo_id and group_id = p_group_id for update;
  if anterior.estado in ('aprobada', 'desaprobada') then
    raise exception 'Este trabajo ya está corregido' using errcode = 'P0001';
  end if;

  insert into public.entregas (trabajo_id, group_id, file_id, version_number, entregada_por, entregada_at, estado)
  values (p_trabajo_id, p_group_id, f.id, version, auth.uid(), now(), 'entregada')
  on conflict (trabajo_id, group_id) do update
    set file_id = excluded.file_id, version_number = excluded.version_number,
        entregada_por = excluded.entregada_por, entregada_at = excluded.entregada_at, estado = 'entregada',
        nota = null, corregida_por = null, corregida_at = null
  returning * into e;

  perform public.log_activity(p_group_id, auth.uid(), 'trabajo_entregado',
    jsonb_build_object('trabajo', t.titulo, 'archivo', f.nombre, 'version', version));

  if anterior.id is null or anterior.estado = 'a_rehacer' then
    select nombre into grupo from public.groups where id = p_group_id;
    insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta)
    select d, 'entrega',
           left(format('%s %s %s', grupo, case when anterior.id is null then 'entregó' else 'volvió a entregar' end, t.titulo), 200),
           left(f.nombre, 300), format('/cursos/%s/trabajos/%s', t.curso_id, t.id)
    from public.docentes_de(t.curso_id) d;
  end if;
  return e;
end;
$$;

-- Material: 100 archivos y 500 MB por curso; el aviso a los alumnos, hasta 30
-- por día (después se sube igual, sin avisar). Las reservas vencidas de
-- cualquier curso se descartan (su objeto lo borra la limpieza diaria).
create or replace function public.reservar_material(p_curso_id uuid, p_nombre text, p_size_bytes bigint)
returns table (id uuid, storage_path text)
language plpgsql security definer set search_path = ''
as $$
declare
  nuevo uuid := gen_random_uuid();
  ruta text;
begin
  if not public.soy_docente_del_curso(p_curso_id) then
    raise exception 'Solo los docentes del curso pueden subir material' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_nombre, ''))) not between 1 and 200 or p_nombre ~ '[/\\]' then
    raise exception 'Ese nombre de archivo no sirve' using errcode = 'P0001';
  end if;
  if coalesce(p_size_bytes, -1) not between 0 and 52428800 then
    raise exception 'El archivo puede pesar hasta 50 MB' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('material:' || p_curso_id::text));
  delete from public.material_curso m where not m.subido and m.created_at < now() - interval '2 hours';
  if (select count(*) from public.material_curso m where m.curso_id = p_curso_id) >= 100 then
    raise exception 'Un curso puede tener hasta 100 archivos de material' using errcode = 'P0001';
  end if;
  if (select coalesce(sum(m.size_bytes), 0) from public.material_curso m where m.curso_id = p_curso_id)
     + p_size_bytes > 524288000 then
    raise exception 'El material del curso puede ocupar hasta 500 MB' using errcode = 'P0001';
  end if;
  ruta := format('cursos/%s/material/%s', p_curso_id, nuevo);
  insert into public.material_curso (id, curso_id, nombre, storage_path, size_bytes, subido_por)
  values (nuevo, p_curso_id, trim(p_nombre), ruta, p_size_bytes, auth.uid());
  return query select nuevo, ruta;
end;
$$;

create or replace function public.terminar_material(p_id uuid)
returns public.material_curso
language plpgsql security definer set search_path = ''
as $$
declare
  m public.material_curso;
  o record;
  curso text;
begin
  select * into m from public.material_curso x where x.id = p_id and x.subido_por = auth.uid() and not x.subido for update;
  if m.id is null then
    raise exception 'No encontramos esa subida' using errcode = 'P0002';
  end if;
  select metadata into o from storage.objects where bucket_id = 'archivos' and name = m.storage_path;
  if not found then
    raise exception 'El archivo no se terminó de subir. Probá de nuevo' using errcode = 'P0001';
  end if;
  if coalesce((o.metadata->>'size')::bigint, 0) > 52428800 then
    raise exception 'El archivo puede pesar hasta 50 MB' using errcode = 'P0001';
  end if;
  update public.material_curso
  set subido = true,
      size_bytes = coalesce((o.metadata->>'size')::bigint, size_bytes),
      mime_type = o.metadata->>'mimetype'
  where id = p_id
  returning * into m;

  if public.hay_lugar(m.curso_id, 'material', 30) then
    select nombre into curso from public.cursos where id = m.curso_id;
    insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
    select gm.user_id, 'curso', left(format('Material nuevo en %s', curso), 200), left(m.nombre, 300),
           format('/grupos/%s/material', g.id), g.id
    from public.groups g
    join public.group_members gm on gm.group_id = g.id
    where g.curso_id = m.curso_id;
  end if;
  return m;
end;
$$;

create or replace function public.fechas_curso_tope()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.hay_lugar(new.curso_id, 'fecha', 50) then
    raise exception 'Cargaste muchas fechas hoy. Probá mañana' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- Colegas: parte de mis cursos (sin recorrer todos).
create or replace function public.es_mi_colega(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  with mios as (
    select c.id from public.cursos c where c.docente_id = auth.uid()
    union
    select d.curso_id from public.curso_docentes d where d.user_id = auth.uid()
  )
  select p_user_id is distinct from auth.uid() and exists (
    select 1 from mios
    where exists (select 1 from public.cursos c where c.id = mios.id and c.docente_id = p_user_id)
       or exists (select 1 from public.curso_docentes d where d.curso_id = mios.id and d.user_id = p_user_id)
  )
$$;

-- Solo la usan otras funciones (security definer): no hace falta exponerla.
revoke execute on function public.es_docente_del_curso(uuid, uuid) from authenticated;

-- "Vencidas" según el día en Buenos Aires.
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
                               where t.group_id = g.id and t.estado <> 'hecha'
                                 and t.due_date < (now() at time zone 'America/Argentina/Buenos_Aires')::date),
           'materias', (select coalesce(jsonb_agg(f.nombre order by f.nombre), '[]')
                        from public.folders f where f.group_id = g.id and f.es_materia),
           'ultima_actividad', (select max(a.created_at) from public.activity a where a.group_id = g.id),
           'versiones_semana', (select count(*) from public.file_versions v
                                where v.group_id = g.id and v.created_at > now() - interval '7 days'))
         order by g.nombre), '[]')
  from public.groups g
  where g.curso_id = p_curso_id and public.soy_docente_del_curso(p_curso_id)
$$;

-- Índices para el tablero y los aportes.
create index if not exists file_versions_grupo_fecha_idx on public.file_versions (group_id, created_at desc);
create index if not exists file_versions_grupo_autor_idx on public.file_versions (group_id, uploaded_by);
create index if not exists comentarios_grupo_autor_idx on public.comentarios (group_id, autor);
create index if not exists activity_grupo_usuario_idx on public.activity (group_id, user_id, created_at desc);
create index if not exists tasks_grupo_asignada_idx on public.tasks (group_id, assigned_to);
