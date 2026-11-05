-- Versiones guardadas: como "Mantener para siempre" en Drive. Una versión con
-- nombre ("Entrega 1", "Antes de la corrección") queda a mano en el historial y
-- se sigue viendo aunque el plan gratis muestre solo las últimas.

alter table public.file_versions
  add column guardada_nombre text
    check (guardada_nombre is null or char_length(trim(guardada_nombre)) between 1 and 60),
  add column guardada_por uuid references public.profiles (id) on delete set null,
  add column guardada_at timestamptz,
  add constraint file_versions_guardada_completa
    check ((guardada_nombre is null) = (guardada_at is null));

create index file_versions_guardadas_idx on public.file_versions (file_id) where guardada_nombre is not null;

-- Cuántas se pueden guardar por archivo, según el plan (para que guardar no
-- sea una forma de saltear el límite de versiones visibles).
alter table public.plan_limits add column versiones_guardadas integer not null default 10;
update public.plan_limits set versiones_guardadas = 50 where plan = 'premium';

create or replace function public.max_versiones_guardadas(p_file_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  select l.versiones_guardadas
  from public.files f
  join public.groups g on g.id = f.group_id
  join public.plan_limits l on l.plan = g.plan
  where f.id = p_file_id
$$;

-- Visible = entre las últimas N del plan, o guardada.
create or replace function public.version_visible(p_file_id uuid, p_version integer)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    p_version > (select max(v.version_number) from public.file_versions v where v.file_id = p_file_id)
                - (select l.versiones_visibles
                   from public.files f
                   join public.groups g on g.id = f.group_id
                   join public.plan_limits l on l.plan = g.plan
                   where f.id = p_file_id),
    true)  -- versiones_visibles null (premium) = historial completo
  or exists (
    select 1 from public.file_versions v
    where v.file_id = p_file_id and v.version_number = p_version and v.guardada_nombre is not null)
$$;

-- Guarda una versión con nombre, le cambia el nombre, o la quita de las
-- guardadas (p_nombre vacío o null). Quitarla puede volver a ocultarla con el
-- plan gratis: eso (y cambiarle el nombre) solo lo hace quien la guardó o un admin.
create or replace function public.guardar_version(p_version_id uuid, p_nombre text)
returns public.file_versions
language plpgsql security definer set search_path = ''
as $$
declare
  v public.file_versions;
  f public.files;
  nombre text := nullif(trim(p_nombre), '');
  limite integer;
begin
  select * into v from public.file_versions where id = p_version_id;
  if v.id is null or not public.is_group_member(v.group_id) then
    raise exception 'La versión no existe' using errcode = 'P0002';
  end if;

  -- Bloquea el archivo: dos personas guardando a la vez no pasan el tope, y
  -- una subida que termina mientras tanto no deja guardar algo ya oculto.
  select * into f from public.files where id = v.file_id for update;
  if not public.version_visible(v.file_id, v.version_number) then
    raise exception 'La versión no existe' using errcode = 'P0002';
  end if;
  if f.deleted_at is not null then
    raise exception 'Está en la papelera: restauralo para usarlo' using errcode = 'P0001';
  end if;
  select * into v from public.file_versions where id = p_version_id;

  if v.guardada_nombre is not null
     and v.guardada_por is distinct from auth.uid()
     and not public.is_group_admin(v.group_id) then
    raise exception 'Solo quien la guardó o un admin pueden cambiarla' using errcode = '42501';
  end if;

  if nombre is null then
    if v.guardada_nombre is null then
      return v;  -- No estaba guardada: nada que hacer.
    end if;
    update public.file_versions
    set guardada_nombre = null, guardada_por = null, guardada_at = null
    where id = v.id
    returning * into v;
    return v;
  end if;

  if char_length(nombre) > 60 then
    raise exception 'Usá 60 caracteres como máximo' using errcode = 'P0001';
  end if;
  limite := public.max_versiones_guardadas(v.file_id);
  if v.guardada_nombre is null and (
       select count(*) from public.file_versions
       where file_id = v.file_id and guardada_nombre is not null) >= limite then
    raise exception 'Ya hay % versiones guardadas de este archivo. Quitá alguna para guardar otra', limite
      using errcode = 'P0001';
  end if;

  update public.file_versions
  set guardada_nombre = nombre,
      guardada_por = coalesce(v.guardada_por, auth.uid()),
      guardada_at = coalesce(v.guardada_at, now())
  where id = v.id
  returning * into v;
  return v;
end;
$$;

revoke execute on function public.guardar_version(uuid, text) from public, anon;
grant execute on function public.guardar_version(uuid, text) to authenticated;
revoke execute on function public.max_versiones_guardadas(uuid) from public, anon, authenticated;
