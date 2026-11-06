-- Material del docente, fechas del curso y comentarios que citan el texto.

-- Material del curso ------------------------------------------------------------------
--
-- El docente sube un archivo (consigna, plantilla, apunte) una vez y lo ven
-- todos los grupos del curso, en solo lectura. Va al bucket "archivos" en
-- cursos/{curso_id}/material/{id}. Como las demás subidas, primero se reserva
-- la ruta (reservar_material) y Storage solo acepta rutas reservadas; después
-- terminar_material confirma que el objeto está.

create table public.material_curso (
  id            uuid primary key default gen_random_uuid(),
  curso_id      uuid not null references public.cursos (id) on delete cascade,
  nombre        text not null check (char_length(trim(nombre)) between 1 and 200),
  storage_path  text not null unique,
  size_bytes    bigint not null check (size_bytes between 0 and 52428800),
  mime_type     text,
  subido_por    uuid references public.profiles (id) on delete set null,
  -- false mientras se sube (no se muestra).
  subido        boolean not null default false,
  created_at    timestamptz not null default now()
);

create index material_curso_idx on public.material_curso (curso_id, created_at desc);

alter table public.material_curso enable row level security;
revoke all on public.material_curso from anon;
revoke insert, update, delete on public.material_curso from authenticated;

create policy "material: lo ve el curso"
  on public.material_curso for select to authenticated
  using (subido and (public.soy_docente_del_curso(curso_id) or public.curso_de_mis_grupos(curso_id)));

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
  -- Las reservas que no se terminaron en 2 horas se descartan.
  delete from public.material_curso m
  where m.curso_id = p_curso_id and not m.subido and m.created_at < now() - interval '2 hours';
  if (select count(*) from public.material_curso m where m.curso_id = p_curso_id) >= 200 then
    raise exception 'Un curso puede tener hasta 200 archivos de material' using errcode = 'P0001';
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
  update public.material_curso
  set subido = true,
      size_bytes = coalesce((o.metadata->>'size')::bigint, size_bytes),
      mime_type = o.metadata->>'mimetype'
  where id = p_id
  returning * into m;

  select nombre into curso from public.cursos where id = m.curso_id;
  insert into public.notificaciones (user_id, tipo, titulo, cuerpo, ruta, group_id)
  select gm.user_id, 'curso', left(format('Material nuevo en %s', curso), 200), left(m.nombre, 300),
         format('/grupos/%s/material', g.id), g.id
  from public.groups g
  join public.group_members gm on gm.group_id = g.id
  where g.curso_id = m.curso_id;
  return m;
end;
$$;

create or replace function public.borrar_material(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  -- El objeto de Storage queda huérfano y lo borra la limpieza diaria (mientras
  -- tanto nadie lo puede leer: no tiene fila).
  delete from public.material_curso m where m.id = p_id and public.soy_docente_del_curso(m.curso_id);
  if not found then
    raise exception 'Ese archivo no existe' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.reservar_material(uuid, text, bigint) from public, anon;
revoke execute on function public.terminar_material(uuid) from public, anon;
revoke execute on function public.borrar_material(uuid) from public, anon;
grant execute on function public.reservar_material(uuid, text, bigint) to authenticated;
grant execute on function public.terminar_material(uuid) to authenticated;
grant execute on function public.borrar_material(uuid) to authenticated;

-- Storage acepta también las rutas de material reservadas por quien sube.
create or replace function public.upload_reserved(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
           select 1 from public.pending_uploads
           where storage_path = p_path and user_id = auth.uid() and expires_at > now())
      or exists (
           select 1 from public.material_curso m
           where m.storage_path = p_path and m.subido_por = auth.uid() and not m.subido
             and m.created_at > now() - interval '2 hours')
$$;

create or replace function public.material_legible(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.material_curso m
    where m.storage_path = p_path and m.subido
      and (public.soy_docente_del_curso(m.curso_id) or public.curso_de_mis_grupos(m.curso_id))
  )
$$;

revoke execute on function public.material_legible(text) from public, anon;
grant execute on function public.material_legible(text) to authenticated;

create policy "material: lo lee el curso"
  on storage.objects for select to authenticated
  using (bucket_id = 'archivos' and (storage.foldername(name))[1] = 'cursos' and public.material_legible(name));

-- La limpieza no toca el material (ni las subidas en curso).
create or replace function public.orphan_storage_objects(p_edad_minima interval default '24:00:00', p_limite integer default 500)
returns setof text
language sql stable security definer set search_path = ''
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'archivos'
    and o.created_at < now() - p_edad_minima
    and not exists (select 1 from public.file_versions v where v.storage_path = o.name)
    and not exists (select 1 from public.material_curso m where m.storage_path = o.name)
  order by o.created_at
  limit p_limite
$$;

-- Fechas del curso ----------------------------------------------------------------------
--
-- Parciales, clases y entregas que pone el docente: aparecen en el calendario
-- de todos los alumnos del curso (y los vencimientos de los trabajos también).

create table public.fechas_curso (
  id          uuid primary key default gen_random_uuid(),
  curso_id    uuid not null references public.cursos (id) on delete cascade,
  titulo      text not null check (char_length(trim(titulo)) between 1 and 120),
  tipo        text not null default 'otro' check (tipo in ('parcial', 'entrega', 'clase', 'otro')),
  fecha       date not null,
  hora        time,
  nota        text check (nota is null or char_length(nota) <= 500),
  creado_por  uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

create index fechas_curso_idx on public.fechas_curso (curso_id, fecha);

alter table public.fechas_curso enable row level security;
revoke all on public.fechas_curso from anon;
revoke insert, update, delete on public.fechas_curso from authenticated;
grant insert (curso_id, titulo, tipo, fecha, hora, nota, creado_por) on public.fechas_curso to authenticated;
grant delete on public.fechas_curso to authenticated;

create policy "fechas_curso: las ve el curso"
  on public.fechas_curso for select to authenticated
  using (public.soy_docente_del_curso(curso_id) or public.curso_de_mis_grupos(curso_id));

create policy "fechas_curso: las cargan los docentes"
  on public.fechas_curso for insert to authenticated
  with check (public.soy_docente_del_curso(curso_id) and creado_por = (select auth.uid()));

create policy "fechas_curso: las borran los docentes"
  on public.fechas_curso for delete to authenticated
  using (public.soy_docente_del_curso(curso_id));

-- Hasta 50 fechas por día por curso.
create or replace function public.fechas_curso_tope()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('fechas_curso:' || new.curso_id::text));
  if (select count(*) from public.fechas_curso
      where curso_id = new.curso_id and created_at > now() - interval '1 day') >= 50 then
    raise exception 'Cargaste muchas fechas hoy. Probá mañana' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.fechas_curso_tope() from public, anon, authenticated;

create trigger fechas_curso_tope before insert on public.fechas_curso
  for each row execute function public.fechas_curso_tope();

-- Comentarios que citan un fragmento ---------------------------------------------------

alter table public.comentarios
  add column cita text check (cita is null or char_length(cita) between 1 and 500);
grant insert (cita) on public.comentarios to authenticated;
