-- Varias materias en un mismo grupo. Una materia es una carpeta de la raíz del
-- grupo marcada como tal y con un color (como las carpetas de colores de
-- Drive): adentro van sus TPs y archivos. Las tareas ya se asocian a una
-- carpeta; los eventos del calendario ahora también.

alter table public.folders
  add column es_materia boolean not null default false,
  add column color smallint,
  add constraint folders_materia_en_raiz check (not es_materia or parent_id is null),
  add constraint folders_color_valido check (color is null or (es_materia and color between 0 and 7));

create index folders_materias_idx on public.folders (group_id) where es_materia;

-- Arreglo: la política comparaba p.id con p.parent_id (la columna de la
-- subconsulta, no la de la carpeta nueva), así que no se podían crear
-- subcarpetas desde la app.
drop policy "folders: crear en mis grupos" on public.folders;
create policy "folders: crear en mis grupos"
  on public.folders for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and created_by = (select auth.uid())
    and (parent_id is null
         or exists (select 1 from public.folders p where p.id = folders.parent_id and p.group_id = folders.group_id))
  );

-- El cliente crea carpetas comunes; las materias, con crear_materia.
revoke insert on public.folders from authenticated;
grant insert (group_id, parent_id, nombre, created_by) on public.folders to authenticated;

-- Cuántas materias puede tener un grupo, según su plan.
alter table public.plan_limits add column materias integer not null default 20;

create or replace function public.max_materias(p_group_id uuid)
returns integer
language sql stable security definer set search_path = ''
as $$
  select l.materias from public.groups g join public.plan_limits l on l.plan = g.plan where g.id = p_group_id
$$;

create or replace function public.crear_materia(p_group_id uuid, p_nombre text, p_color smallint default null)
returns public.folders
language plpgsql security definer set search_path = ''
as $$
declare
  c public.folders;
  nombre text := trim(coalesce(p_nombre, ''));
  cantidad integer;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No tenés acceso a este grupo' using errcode = '42501';
  end if;
  if char_length(nombre) not between 1 and 120 then
    raise exception 'Ingresá el nombre de la materia (hasta 120 caracteres)' using errcode = 'P0001';
  end if;
  if p_color is not null and p_color not between 0 and 7 then
    raise exception 'Ese color no existe' using errcode = 'P0001';
  end if;

  -- Serializa las altas del grupo para respetar el tope.
  perform 1 from public.groups where id = p_group_id for update;
  select count(*) into cantidad from public.folders where group_id = p_group_id and es_materia;
  if cantidad >= public.max_materias(p_group_id) then
    raise exception 'El grupo ya tiene % materias', cantidad using errcode = 'P0001';
  end if;

  begin
    insert into public.folders (group_id, parent_id, nombre, created_by, es_materia, color)
    values (p_group_id, null, nombre, auth.uid(), true, coalesce(p_color, (cantidad % 8)::smallint))
    returning * into c;
  exception when unique_violation then
    raise exception 'Ya hay una carpeta o materia con ese nombre' using errcode = 'P0001';
  end;
  return c;
end;
$$;

-- Cambia el color de una materia, convierte una carpeta de la raíz en materia,
-- o la vuelve carpeta común (no se borra nada).
create or replace function public.editar_materia(p_folder_id uuid, p_es_materia boolean, p_color smallint default null)
returns public.folders
language plpgsql security definer set search_path = ''
as $$
declare
  c public.folders;
  cantidad integer;
begin
  select * into c from public.folders where id = p_folder_id;
  if c.id is null or not public.is_group_member(c.group_id) then
    raise exception 'La carpeta no existe' using errcode = 'P0002';
  end if;
  if p_es_materia is null then
    raise exception 'Falta decir si es materia' using errcode = 'P0001';
  end if;
  if c.parent_id is not null then
    raise exception 'Solo las carpetas principales del grupo pueden ser materias' using errcode = 'P0001';
  end if;
  if p_color is not null and p_color not between 0 and 7 then
    raise exception 'Ese color no existe' using errcode = 'P0001';
  end if;

  if p_es_materia and not c.es_materia then
    perform 1 from public.groups where id = c.group_id for update;
    select count(*) into cantidad from public.folders where group_id = c.group_id and es_materia;
    if cantidad >= public.max_materias(c.group_id) then
      raise exception 'El grupo ya tiene % materias', cantidad using errcode = 'P0001';
    end if;
  end if;

  update public.folders
  set es_materia = p_es_materia,
      color = case when p_es_materia
                   then coalesce(p_color, c.color, ((select count(*) from public.folders
                                                     where group_id = c.group_id and es_materia) % 8)::smallint)
              end
  where id = p_folder_id
  returning * into c;
  return c;
end;
$$;

revoke execute on function public.crear_materia(uuid, text, smallint) from public, anon;
revoke execute on function public.editar_materia(uuid, boolean, smallint) from public, anon;
grant execute on function public.crear_materia(uuid, text, smallint) to authenticated;
grant execute on function public.editar_materia(uuid, boolean, smallint) to authenticated;
revoke execute on function public.max_materias(uuid) from public, anon, authenticated;

-- Crear un grupo con varias materias de una vez ----------------------------------

drop function public.create_group(text, text);

create or replace function public.create_group(p_nombre text, p_materia text default null, p_materias text[] default null)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  g public.groups;
  m text;
  i integer := 0;
  vistas text[] := '{}';
  pedidas text[] := coalesce(p_materias, case when nullif(trim(p_materia), '') is null then '{}'::text[]
                                              else array[trim(p_materia)] end);
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;
  if cardinality(pedidas) > 50 then
    raise exception 'Son demasiadas materias' using errcode = 'P0001';
  end if;

  -- groups.materia ya no se usa: las materias son carpetas.
  insert into public.groups (nombre, invite_code, created_by)
  values (trim(p_nombre), public.generate_invite_code(), auth.uid())
  returning * into g;

  insert into public.group_members (group_id, user_id, rol)
  values (g.id, auth.uid(), 'admin');

  -- Cada materia, una carpeta (sin repetir, sin vacías, hasta el tope).
  foreach m in array pedidas loop
    exit when i >= public.max_materias(g.id);
    m := trim(m);
    continue when m is null or m = '' or char_length(m) > 120 or lower(m) = any (vistas);
    insert into public.folders (group_id, parent_id, nombre, created_by, es_materia, color)
    values (g.id, null, m, auth.uid(), true, (i % 8)::smallint);
    vistas := vistas || lower(m);
    i := i + 1;
  end loop;

  return g;
end;
$$;

revoke execute on function public.create_group(text, text, text[]) from public, anon;
grant execute on function public.create_group(text, text, text[]) to authenticated;

-- Grupos que ya tenían su materia: pasa a ser su primera materia (si ya hay
-- una carpeta con ese nombre en la raíz, se marca esa).
update public.folders c
set es_materia = true, color = 0
from public.groups g
where c.group_id = g.id and c.parent_id is null and g.materia is not null
  and lower(c.nombre) = lower(trim(g.materia));

insert into public.folders (group_id, parent_id, nombre, created_by, es_materia, color)
select g.id, null, trim(g.materia), g.created_by, true, 0
from public.groups g
where nullif(trim(g.materia), '') is not null
  and not exists (select 1 from public.folders c
                  where c.group_id = g.id and c.parent_id is null and lower(c.nombre) = lower(trim(g.materia)));

-- Esas carpetas las armó la migración, no alguien del grupo: sin actividad.
delete from public.activity where tipo = 'carpeta_creada' and created_at >= now();

-- groups.materia queda solo como dato viejo: ya no se edita.
revoke update on public.groups from authenticated;
grant update (nombre) on public.groups to authenticated;

-- Eventos del calendario con materia ------------------------------------------------

alter table public.eventos add column folder_id uuid references public.folders (id) on delete set null;
create index eventos_folder_idx on public.eventos (folder_id) where folder_id is not null;

grant insert (folder_id) on public.eventos to authenticated;
grant update (folder_id) on public.eventos to authenticated;

-- La materia tiene que ser del mismo grupo que el evento.
create or replace function public.eventos_materia_del_grupo()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.folder_id is not null and not exists (
    select 1 from public.folders where id = new.folder_id and group_id = new.group_id and es_materia
  ) then
    raise exception 'Esa materia no es de este grupo' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.eventos_materia_del_grupo() from public, anon, authenticated;

create trigger eventos_materia_del_grupo
  before insert or update of folder_id, group_id on public.eventos
  for each row execute function public.eventos_materia_del_grupo();
