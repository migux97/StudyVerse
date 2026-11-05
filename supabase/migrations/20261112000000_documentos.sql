-- Documentos de StudyVerse (.svdoc): texto con formato que se edita en la app.
--
-- Cada versión es un objeto de Storage con el documento en JSON (Delta de
-- Quill), como cualquier archivo. Mientras alguien lo edita (con el archivo
-- bloqueado), la app autoguarda en `documentos` cada pocos segundos: así no se
-- pierde nada si se cierra la app y los demás lo ven en vivo. Al terminar de
-- editar se sube una versión y el borrador se descarta.
--
-- El borrador solo vale como "lo último" mientras su autor tenga el archivo
-- bloqueado. Si el bloqueo se libera sin versión (venció, o lo forzó un admin),
-- los demás ven la última versión y el autor lo recupera al volver a editar.

create table public.documentos (
  file_id      uuid primary key references public.files (id) on delete cascade,
  group_id     uuid not null references public.groups (id) on delete cascade,
  contenido    jsonb not null check (jsonb_typeof(contenido) = 'array'),
  -- Última versión cuando se empezó el borrador.
  base_version integer,
  updated_by   uuid references public.profiles (id) on delete set null,
  updated_at   timestamptz not null default now()
);

create index documentos_group_idx on public.documentos (group_id);

alter table public.documentos enable row level security;

create policy "documentos: ver los de mis grupos"
  on public.documentos for select to authenticated
  using (public.is_group_member(group_id));

-- Se escriben solo con guardar_documento.
revoke insert, update, delete on public.documentos from anon, authenticated;

create or replace function public.es_documento(p_nombre text)
returns boolean language sql immutable as $$
  select lower(p_nombre) like '%.svdoc'
$$;

revoke execute on function public.es_documento(text) from public, anon, authenticated;

-- Límites de los borradores (no cuentan en el espacio del plan: son chicos y temporales).
create or replace function public.max_bytes_borrador() returns integer language sql immutable as $$ select 1024 * 1024 $$;
create or replace function public.max_borradores_por_persona() returns integer language sql immutable as $$ select 10 $$;

-- Autoguardado. Solo quien tiene el archivo bloqueado (y vigente) puede guardar.
create or replace function public.guardar_documento(p_file_id uuid, p_contenido jsonb)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  ahora timestamptz := clock_timestamp();
begin
  -- for update: si finish_upload está liberando el archivo, espera y ve el cambio.
  select * into f from public.files where id = p_file_id for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El documento no existe' using errcode = 'P0002';
  end if;
  if not public.es_documento(f.nombre) then
    raise exception 'Solo se editan documentos de StudyVerse' using errcode = 'P0001';
  end if;
  if f.locked_by is distinct from auth.uid() or public.lock_expires_at(f) <= now() then
    raise exception 'Para guardar, primero tocá «Editar»' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_contenido) <> 'array' then
    raise exception 'El contenido del documento no es válido' using errcode = 'P0001';
  end if;
  if octet_length(p_contenido::text) > public.max_bytes_borrador() then
    raise exception 'El documento es demasiado grande para guardarlo así. Tocá «Listo» para guardar la versión' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.documentos where file_id = f.id)
     and (select count(*) from public.documentos where updated_by = auth.uid()) >= public.max_borradores_por_persona() then
    raise exception 'Tenés muchos documentos sin terminar. Tocá «Listo» en alguno' using errcode = 'P0001';
  end if;

  insert into public.documentos (file_id, group_id, contenido, base_version, updated_by, updated_at)
  values (
    f.id, f.group_id, p_contenido,
    (select max(v.version_number) from public.file_versions v where v.file_id = f.id),
    auth.uid(), ahora
  )
  on conflict (file_id) do update
    set contenido = excluded.contenido, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  return ahora;
end;
$$;

revoke execute on function public.guardar_documento(uuid, jsonb) from public, anon;
grant execute on function public.guardar_documento(uuid, jsonb) to authenticated;

-- Una versión nueva (subida al terminar, o una restaurada) reemplaza al borrador.
create or replace function public.descartar_borrador()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.documentos where file_id = new.file_id;
  return null;
end;
$$;

revoke execute on function public.descartar_borrador() from public, anon, authenticated;

create trigger file_versions_descartar_borrador
  after insert on public.file_versions
  for each row execute function public.descartar_borrador();

-- En vivo: canal grupo:{id}:documentos, con el id del documento que cambió
-- (así solo vuelve a leer quien lo tiene abierto).
create or replace function public.avisar_documento()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  fila public.documentos := coalesce(new, old);
begin
  perform realtime.send(jsonb_build_object('documento', fila.file_id), 'cambio',
                        format('grupo:%s:documentos', fila.group_id), true);
  return null;
end;
$$;

revoke execute on function public.avisar_documento() from public, anon, authenticated;

create trigger documentos_avisar after insert or update or delete on public.documentos
  for each row execute function public.avisar_documento();

create or replace function public.realtime_topic_allowed(p_topic text)
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare
  m text[];
begin
  m := regexp_match(p_topic, '^grupo:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(archivos|tareas|actividad|telegram|documentos)$');
  if m is not null then
    return public.is_group_member(m[1]::uuid);
  end if;
  return auth.uid() is not null
     and p_topic in (format('usuario:%s:grupos', auth.uid()), format('usuario:%s:pedidos', auth.uid()));
end;
$$;
