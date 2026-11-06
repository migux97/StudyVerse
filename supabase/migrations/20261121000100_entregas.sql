-- Entregas de TP con corrección y nota.
--
-- El docente (titular o ayudante) crea un trabajo para todo el curso ("TP 2",
-- consigna, vencimiento y nota máxima). Cada grupo entrega un archivo: queda
-- registrada la versión de ese momento, que se ve siempre (aunque el plan
-- oculte versiones viejas) y el archivo ya no se puede eliminar. Si el grupo
-- sube cambios después, la entrega sigue apuntando a esa versión.
--
-- El docente corrige: aprobado, a rehacer o desaprobado, con nota y devolución.
-- Con "a rehacer" el grupo puede volver a entregar.

create table public.trabajos (
  id           uuid primary key default gen_random_uuid(),
  curso_id     uuid not null references public.cursos (id) on delete cascade,
  titulo       text not null check (char_length(trim(titulo)) between 1 and 120),
  consigna     text check (consigna is null or char_length(consigna) <= 4000),
  vence_at     timestamptz not null,
  nota_maxima  numeric(5, 2) not null default 10 check (nota_maxima > 0 and nota_maxima <= 100),
  creado_por   uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now()
);

create index trabajos_curso_idx on public.trabajos (curso_id, vence_at);

create table public.entregas (
  id              uuid primary key default gen_random_uuid(),
  trabajo_id      uuid not null references public.trabajos (id) on delete cascade,
  group_id        uuid not null references public.groups (id) on delete cascade,
  -- Sin "on delete": un archivo entregado no se borra (ver entregas_protegen_archivo).
  file_id         uuid not null references public.files (id),
  version_number  integer not null,
  entregada_por   uuid references public.profiles (id) on delete set null,
  entregada_at    timestamptz not null default now(),
  estado          text not null default 'entregada'
                  check (estado in ('entregada', 'aprobada', 'a_rehacer', 'desaprobada')),
  nota            numeric(5, 2) check (nota is null or nota >= 0),
  devolucion      text check (devolucion is null or char_length(devolucion) <= 4000),
  corregida_por   uuid references public.profiles (id) on delete set null,
  corregida_at    timestamptz,
  unique (trabajo_id, group_id)
);

create index entregas_grupo_idx on public.entregas (group_id);
create index entregas_archivo_idx on public.entregas (file_id, version_number);

alter table public.trabajos enable row level security;
alter table public.entregas enable row level security;
revoke all on public.trabajos from anon;
revoke all on public.entregas from anon;
-- Todo se escribe con las funciones de abajo.
revoke insert, update, delete on public.trabajos from authenticated;
revoke insert, update, delete on public.entregas from authenticated;

create policy "trabajos: los ve el curso"
  on public.trabajos for select to authenticated
  using (public.soy_docente_del_curso(curso_id) or public.curso_de_mis_grupos(curso_id));

create policy "entregas: las ven el grupo y sus docentes"
  on public.entregas for select to authenticated
  using (public.is_group_member(group_id) or public.es_docente_de_grupo(group_id));

-- La versión entregada se ve siempre.
create or replace function public.version_visible(p_file_id uuid, p_version integer)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    p_version > (select max(v.version_number) from public.file_versions v where v.file_id = p_file_id)
              - (select l.versiones_visibles from public.files f
                 join public.groups g on g.id = f.group_id
                 join public.plan_limits l on l.plan = g.plan
                 where f.id = p_file_id),
    true)
  or exists (select 1 from public.file_versions v
             where v.file_id = p_file_id and v.version_number = p_version and v.guardada_nombre is not null)
  or exists (select 1 from public.entregas e where e.file_id = p_file_id and e.version_number = p_version)
$$;

-- Un archivo entregado no va a la papelera (así nunca se elimina para siempre).
create or replace function public.entregas_protegen_archivo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.deleted_at is null and new.deleted_at is not null
     and exists (select 1 from public.entregas e where e.file_id = new.id) then
    raise exception 'Este archivo está entregado en un TP: no se puede eliminar' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.entregas_protegen_archivo() from public, anon, authenticated;

create trigger entregas_protegen_archivo before update of deleted_at on public.files
  for each row execute function public.entregas_protegen_archivo();

-- Docentes del curso (titular y ayudantes), para avisarles.
create or replace function public.docentes_de(p_curso_id uuid)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select c.docente_id from public.cursos c where c.id = p_curso_id
  union
  select d.user_id from public.curso_docentes d where d.curso_id = p_curso_id
$$;

revoke execute on function public.docentes_de(uuid) from public, anon, authenticated;

-- Trabajos ------------------------------------------------------------------------

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
  perform pg_advisory_xact_lock(hashtext('trabajos:' || p_curso_id::text));
  if (select count(*) from public.trabajos where curso_id = p_curso_id and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Creaste muchos trabajos hoy. Probá mañana' using errcode = 'P0001';
  end if;
  insert into public.trabajos (curso_id, titulo, consigna, vence_at, nota_maxima)
  values (p_curso_id, trim(p_titulo), nullif(trim(coalesce(p_consigna, '')), ''), p_vence_at, coalesce(p_nota_maxima, 10))
  returning * into t;

  -- Aviso a todos los alumnos del curso (una sola sentencia).
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

create or replace function public.borrar_trabajo(p_trabajo_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.trabajos t
                 where t.id = p_trabajo_id and public.soy_docente_del_curso(t.curso_id)) then
    raise exception 'Ese trabajo no existe' using errcode = 'P0002';
  end if;
  delete from public.trabajos where id = p_trabajo_id;
end;
$$;

-- Entregar ------------------------------------------------------------------------

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

  select * into anterior from public.entregas
  where trabajo_id = p_trabajo_id and group_id = p_group_id for update;
  if anterior.estado in ('aprobada', 'desaprobada') then
    raise exception 'Este trabajo ya está corregido' using errcode = 'P0001';
  end if;

  insert into public.entregas (trabajo_id, group_id, file_id, version_number, entregada_por, entregada_at, estado)
  values (p_trabajo_id, p_group_id, f.id, version, auth.uid(), now(), 'entregada')
  on conflict (trabajo_id, group_id) do update
    set file_id = excluded.file_id, version_number = excluded.version_number,
        entregada_por = excluded.entregada_por, entregada_at = excluded.entregada_at, estado = 'entregada'
  returning * into e;

  perform public.log_activity(p_group_id, auth.uid(), 'trabajo_entregado',
    jsonb_build_object('trabajo', t.titulo, 'archivo', f.nombre, 'version', version));

  -- A los docentes, solo la primera vez y cuando vuelve después de "a rehacer"
  -- (cambiar el archivo antes de la corrección no les manda otro aviso).
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

-- Corregir ------------------------------------------------------------------------

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
  if e.id is null or not public.es_docente_de_grupo(e.group_id) then
    raise exception 'Esa entrega no existe' using errcode = 'P0002';
  end if;
  select * into t from public.trabajos where id = e.trabajo_id;
  if p_estado not in ('aprobada', 'a_rehacer', 'desaprobada') then
    raise exception 'Elegí cómo quedó la entrega' using errcode = 'P0001';
  end if;
  if p_nota is not null and (p_nota < 0 or p_nota > t.nota_maxima) then
    raise exception 'La nota va de 0 a %', trim(to_char(t.nota_maxima, 'FM999990.##')) using errcode = 'P0001';
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
              || coalesce(' · ' || trim(to_char(p_nota, 'FM999990.##')), '');
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

revoke execute on function public.crear_trabajo(uuid, text, text, timestamptz, numeric) from public, anon;
revoke execute on function public.editar_trabajo(uuid, text, text, timestamptz, numeric) from public, anon;
revoke execute on function public.borrar_trabajo(uuid) from public, anon;
revoke execute on function public.entregar_trabajo(uuid, uuid, uuid) from public, anon;
revoke execute on function public.corregir_entrega(uuid, text, numeric, text) from public, anon;
grant execute on function public.crear_trabajo(uuid, text, text, timestamptz, numeric) to authenticated;
grant execute on function public.editar_trabajo(uuid, text, text, timestamptz, numeric) to authenticated;
grant execute on function public.borrar_trabajo(uuid) to authenticated;
grant execute on function public.entregar_trabajo(uuid, uuid, uuid) to authenticated;
grant execute on function public.corregir_entrega(uuid, text, numeric, text) to authenticated;
