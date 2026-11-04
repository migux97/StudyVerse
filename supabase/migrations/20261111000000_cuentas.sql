-- Cuentas: nombre de usuario, datos de perfil, foto y sesiones.

-- Nombre de usuario --------------------------------------------------------------

create extension if not exists unaccent with schema extensions;

-- 3 a 20 caracteres: minúsculas, números, punto y guion bajo; empieza y
-- termina con letra o número (como en Instagram).

create or replace function public.username_valido(p text)
returns boolean language sql immutable as $$
  select p ~ '^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$' and p !~ '[._]{2}'
$$;

-- Arma un usuario libre a partir de un texto (email, nombre): "Ana María" → "ana.maria", "ana.maria2"…
-- Tiene que ser volatile: cada consulta ve las filas que ya se insertaron o
-- actualizaron en la misma sentencia (lo usa el backfill de abajo).
create or replace function public.generar_username(p_base text)
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  base text;
  candidato text;
  n integer := 1;
begin
  base := lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_base, '')));
  base := regexp_replace(base, '[^a-z0-9._]+', '.', 'g');
  base := regexp_replace(base, '[._]{2,}', '.', 'g');
  base := trim(both '._' from left(base, 20));
  if char_length(base) < 3 then
    base := 'usuario';
  end if;
  candidato := base;
  while exists (select 1 from public.profiles where username = candidato) loop
    n := n + 1;
    -- Siempre entra en 20 caracteres, aunque haya muchos con la misma base.
    candidato := trim(both '._' from left(base, 20 - char_length(n::text))) || n;
  end loop;
  return candidato;
end;
$$;

alter table public.profiles
  add column username    text,
  add column carrera     text check (carrera is null or (carrera = trim(carrera) and char_length(carrera) between 1 and 80)),
  add column universidad text check (universidad is null or (universidad = trim(universidad) and char_length(universidad) between 1 and 80));

-- Usuarios para los perfiles que ya existían: en orden de alta, así el más
-- antiguo se queda con "ana" y el siguiente con "ana2".
do $$
declare
  r record;
begin
  for r in
    select p.id, coalesce(split_part(u.email, '@', 1), p.nombre) as base
    from public.profiles p left join auth.users u on u.id = p.id
    where p.username is null
    order by p.created_at, p.id
  loop
    update public.profiles set username = public.generar_username(r.base) where id = r.id;
  end loop;
end;
$$;

alter table public.profiles
  alter column username set not null,
  add constraint profiles_username_formato check (public.username_valido(username)),
  add constraint profiles_username_unico unique (username);

revoke execute on function public.generar_username(text) from public, anon, authenticated;

-- Nombre, usuario y foto que salen de los metadatos del alta. En el registro
-- con email los metadatos los manda el cliente: la foto solo se toma si viene
-- de Google (una URL cualquiera dejaba ver la IP de quien la mostrara, y
-- 'storage:…' permitiría usar la foto de otro).
create or replace function public.perfil_desde_alta(u auth.users)
returns table (nombre text, username text, avatar_url text)
language plpgsql stable security definer set search_path = ''
as $$
declare
  foto text := u.raw_user_meta_data ->> 'avatar_url';
begin
  nombre := left(coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'nombre'), ''),
    nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
    split_part(u.email, '@', 1)
  ), 80);
  username := lower(trim(u.raw_user_meta_data ->> 'username'));
  if username is null or not public.username_valido(username) then
    username := null;
  end if;
  if coalesce(u.raw_app_meta_data ->> 'provider', 'email') <> 'email'
     and foto ~ '^https://[a-z0-9-]+\.googleusercontent\.com/' then
    avatar_url := foto;
  end if;
  return next;
end;
$$;

revoke execute on function public.perfil_desde_alta(auth.users) from public, anon, authenticated;

-- El perfil nuevo toma el usuario que se eligió al registrarse. Si no vino
-- (Google), no es válido o ya lo tiene otra persona, se genera uno libre; se
-- puede cambiar después. Si dos altas eligen el mismo a la vez, la segunda
-- reintenta con otro en vez de fallar.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  datos record;
  usuario text;
  restriccion text;
begin
  select * into datos from public.perfil_desde_alta(new);
  usuario := datos.username;
  if usuario is null or exists (select 1 from public.profiles where username = usuario) then
    usuario := public.generar_username(split_part(new.email, '@', 1));
  end if;

  loop
    begin
      insert into public.profiles (id, nombre, avatar_url, username)
      values (new.id, datos.nombre, datos.avatar_url, usuario);
      exit;
    exception when unique_violation then
      get stacked diagnostics restriccion = constraint_name;
      if restriccion <> 'profiles_username_unico' then
        raise;
      end if;
      usuario := public.generar_username(split_part(new.email, '@', 1));
    end;
  end loop;
  return new;
end;
$$;

-- Si alguien se vuelve a registrar con un email que todavía no confirmó, Auth
-- actualiza el mismo usuario: el perfil toma los datos del último intento, así
-- un alta ajena sin confirmar no deja su nombre o usuario en tu cuenta.
create or replace function public.actualizar_perfil_sin_confirmar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  datos record;
begin
  select * into datos from public.perfil_desde_alta(new);
  update public.profiles p
  set nombre = datos.nombre,
      avatar_url = datos.avatar_url,
      username = case
        when datos.username is not null
         and not exists (select 1 from public.profiles o where o.username = datos.username and o.id <> new.id)
        then datos.username
        else p.username
      end
  where p.id = new.id;
  return new;
exception when unique_violation then
  -- Justo lo tomó otra persona: queda el usuario anterior.
  return new;
end;
$$;

create trigger on_auth_user_unconfirmed_updated
  after update of raw_user_meta_data on auth.users
  for each row
  when (new.email_confirmed_at is null and new.raw_user_meta_data is distinct from old.raw_user_meta_data)
  execute function public.actualizar_perfil_sin_confirmar();

-- Las altas que nadie confirmó en 7 días se borran y liberan su usuario.
select cron.schedule(
  'borrar-altas-sin-confirmar',
  '15 4 * * *',
  $$delete from auth.users
    where email_confirmed_at is null and phone_confirmed_at is null
      and created_at < now() - interval '7 days'$$
);

-- Para el registro: avisa si el usuario está libre antes de enviar el formulario.
create or replace function public.username_disponible(p_username text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.username_valido(lower(trim(p_username)))
     and not exists (select 1 from public.profiles where username = lower(trim(p_username)))
$$;

-- Decisión: como en Instagram, cualquiera puede ver si un usuario existe (es
-- un nombre público dentro de la app, no un dato privado).
revoke execute on function public.username_disponible(text) from public;
grant execute on function public.username_disponible(text) to anon, authenticated;

revoke update on public.profiles from anon, authenticated;
grant update (nombre, username, carrera, universidad) on public.profiles to authenticated;

-- Foto de perfil ------------------------------------------------------------------
-- Bucket público (la foto la ven los compañeros, como en Google), una carpeta
-- por usuario. avatar_url guarda "storage:{ruta}" y la app arma la URL pública;
-- las de Google quedan como URL.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares', 'avatares', true, 1024 * 1024, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "avatares: ver los míos"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Pocas fotos por persona: la app borra la anterior al cambiarla.
create or replace function public.mis_fotos_guardadas()
returns integer
language sql stable security definer set search_path = ''
as $$
  select count(*)::int from storage.objects
  where bucket_id = 'avatares' and (storage.foldername(name))[1] = auth.uid()::text
$$;

revoke execute on function public.mis_fotos_guardadas() from public, anon;
grant execute on function public.mis_fotos_guardadas() to authenticated;

create policy "avatares: subir a mi carpeta"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatares'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.mis_fotos_guardadas() < 3
  );

create policy "avatares: borrar los míos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);

create or replace function public.set_avatar(p_path text)
returns public.profiles
language plpgsql security definer set search_path = ''
as $$
declare
  p public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Iniciá sesión para seguir' using errcode = '42501';
  end if;
  if p_path is null or split_part(p_path, '/', 1) <> auth.uid()::text
     or not exists (select 1 from storage.objects where bucket_id = 'avatares' and name = p_path) then
    raise exception 'No encontramos la foto' using errcode = 'P0002';
  end if;
  update public.profiles set avatar_url = 'storage:' || p_path where id = auth.uid() returning * into p;
  return p;
end;
$$;

create or replace function public.quitar_avatar()
returns public.profiles
language sql security definer set search_path = ''
as $$
  update public.profiles set avatar_url = null where id = auth.uid() returning *
$$;

revoke execute on function public.set_avatar(text) from public, anon;
revoke execute on function public.quitar_avatar() from public, anon;
grant execute on function public.set_avatar(text) to authenticated;
grant execute on function public.quitar_avatar() to authenticated;

-- Dispositivos conectados -----------------------------------------------------------
-- Las sesiones no vencen (como en Drive); desde el perfil se ven y se cierran.

create or replace function public.mis_sesiones()
returns table (id uuid, user_agent text, ip text, creada timestamptz, ultimo_uso timestamptz, actual boolean)
language sql stable security definer set search_path = ''
as $$
  select s.id,
         s.user_agent,
         host(s.ip),
         s.created_at,
         coalesce(s.refreshed_at at time zone 'UTC', s.updated_at, s.created_at),
         s.id::text = (auth.jwt() ->> 'session_id')
  from auth.sessions s
  where s.user_id = auth.uid()
    and (s.not_after is null or s.not_after > now())
  order by 6 desc, 5 desc
$$;

-- Cierra otra sesión. La propia se cierra con "Cerrar sesión" (signOut).
create or replace function public.cerrar_sesion(p_session_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_session_id::text = (auth.jwt() ->> 'session_id') then
    raise exception 'Para salir de este dispositivo usá «Cerrar sesión»' using errcode = 'P0001';
  end if;
  delete from auth.sessions where id = p_session_id and user_id = auth.uid();
end;
$$;

revoke execute on function public.mis_sesiones() from public, anon;
revoke execute on function public.cerrar_sesion(uuid) from public, anon;
grant execute on function public.mis_sesiones() to authenticated;
grant execute on function public.cerrar_sesion(uuid) to authenticated;
