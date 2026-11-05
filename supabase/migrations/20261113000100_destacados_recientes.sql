-- Destacados, recientes y búsqueda (lo de arriba de "Mis grupos", como en Drive).

-- Destacados: cada uno marca los suyos -------------------------------------------

create table public.destacados (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  file_id    uuid not null references public.files (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, file_id)
);

alter table public.destacados enable row level security;

create or replace function public.archivo_de_mis_grupos(p_file_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.files f
    where f.id = p_file_id and f.deleted_at is null and public.is_group_member(f.group_id)
  )
$$;

revoke execute on function public.archivo_de_mis_grupos(uuid) from public, anon;
grant execute on function public.archivo_de_mis_grupos(uuid) to authenticated;

create policy "destacados: ver los míos"
  on public.destacados for select to authenticated
  using (user_id = (select auth.uid()));

create policy "destacados: marcar archivos de mis grupos"
  on public.destacados for insert to authenticated
  with check (user_id = (select auth.uid()) and public.archivo_de_mis_grupos(file_id));

create policy "destacados: desmarcar los míos"
  on public.destacados for delete to authenticated
  using (user_id = (select auth.uid()));

revoke update on public.destacados from authenticated;

-- Recientes: lo que abrí, el último primero ----------------------------------------

create table public.vistos (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  file_id  uuid not null references public.files (id) on delete cascade,
  visto_at timestamptz not null default now(),
  primary key (user_id, file_id)
);

create index vistos_recientes_idx on public.vistos (user_id, visto_at desc);

alter table public.vistos enable row level security;

create policy "vistos: ver los míos"
  on public.vistos for select to authenticated
  using (user_id = (select auth.uid()));

-- Se escriben con marcar_visto.
revoke insert, update, delete on public.vistos from anon, authenticated;

create or replace function public.marcar_visto(p_file_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.archivo_de_mis_grupos(p_file_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;
  insert into public.vistos (user_id, file_id, visto_at) values (auth.uid(), p_file_id, now())
  on conflict (user_id, file_id) do update set visto_at = excluded.visto_at;
  -- Se guardan los últimos 50.
  delete from public.vistos v
  where v.user_id = auth.uid()
    and v.file_id not in (select file_id from public.vistos where user_id = auth.uid() order by visto_at desc limit 50);
end;
$$;

revoke execute on function public.marcar_visto(uuid) from public, anon;
grant execute on function public.marcar_visto(uuid) to authenticated;

-- Búsqueda en todos mis grupos ----------------------------------------------------
-- Por nombre, sin importar mayúsculas ni tildes ("practico" encuentra
-- "Trabajo Práctico"). Corre con los permisos de quien busca (RLS).

create or replace function public.sin_tildes(p text)
returns text language sql immutable set search_path = '' as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p, '')))
$$;

create index files_nombre_busqueda_idx on public.files (public.sin_tildes(nombre)) where deleted_at is null;

create or replace function public.buscar_archivos(p_texto text)
returns table (
  file_id uuid, group_id uuid, grupo text, folder_id uuid, carpeta text,
  nombre text, actualizado timestamptz
)
language sql stable set search_path = ''
as $$
  select f.id, f.group_id, g.nombre, f.folder_id, c.nombre, f.nombre,
         coalesce(v.created_at, f.created_at)
  from public.files f
  join public.groups g on g.id = f.group_id
  left join public.folders c on c.id = f.folder_id
  left join public.file_versions v on v.id = f.current_version_id
  where f.deleted_at is null
    and char_length(trim(p_texto)) >= 2
    and public.sin_tildes(f.nombre) like '%' || replace(replace(public.sin_tildes(trim(p_texto)), '%', ''), '_', '') || '%'
  order by (public.sin_tildes(f.nombre) like public.sin_tildes(trim(p_texto)) || '%') desc,
           coalesce(v.created_at, f.created_at) desc
  limit 50
$$;

revoke execute on function public.buscar_archivos(text) from public, anon;
grant execute on function public.buscar_archivos(text) to authenticated;
