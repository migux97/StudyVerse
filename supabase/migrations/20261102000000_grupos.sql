-- Fase 2: grupos, miembros, roles e invitaciones por código.

create type public.rol_miembro as enum ('admin', 'miembro');

create table public.groups (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null check (char_length(trim(nombre)) between 1 and 80),
  materia       text check (materia is null or char_length(trim(materia)) <= 80),
  invite_code   text not null unique,
  plan          public.plan_tipo not null default 'free',
  storage_used  bigint not null default 0 check (storage_used >= 0),
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

create table public.group_members (
  group_id   uuid not null references public.groups (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  rol        public.rol_miembro not null default 'miembro',
  joined_at  timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

-- Helpers de permisos -----------------------------------------------------
-- security definer para que las políticas puedan consultar group_members sin
-- caer en recursión de RLS.

create or replace function public.is_group_member(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_group_admin(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid() and rol = 'admin'
  );
$$;

-- ¿Comparten algún grupo el usuario actual y otro?
create or replace function public.shares_group_with(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on b.group_id = a.group_id
    where a.user_id = auth.uid() and b.user_id = p_user_id
  );
$$;

-- Código de invitación: 8 caracteres sin ambiguos (sin 0/O, 1/I/L).
create or replace function public.generate_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  codigo text;
begin
  loop
    codigo := '';
    for i in 1..8 loop
      codigo := codigo || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
    end loop;
    exit when not exists (select 1 from public.groups where invite_code = codigo);
  end loop;
  return codigo;
end;
$$;

-- RLS ---------------------------------------------------------------------

alter table public.groups enable row level security;
alter table public.group_members enable row level security;

create policy "groups: ver si soy miembro"
  on public.groups for select to authenticated
  using (public.is_group_member(id));

create policy "groups: el admin edita"
  on public.groups for update to authenticated
  using (public.is_group_admin(id))
  with check (public.is_group_admin(id));

create policy "groups: el admin elimina"
  on public.groups for delete to authenticated
  using (public.is_group_admin(id));

-- Altas de grupos y miembros: solo por las funciones de abajo.
revoke insert, update on public.groups from authenticated;
grant update (nombre, materia) on public.groups to authenticated;

create policy "group_members: ver los de mis grupos"
  on public.group_members for select to authenticated
  using (public.is_group_member(group_id));

revoke insert, update, delete on public.group_members from authenticated;

-- Ahora los integrantes de un mismo grupo pueden verse los perfiles.
create policy "profiles: ver compañeros de grupo"
  on public.profiles for select to authenticated
  using (public.shares_group_with(id));

-- Operaciones -------------------------------------------------------------

create or replace function public.create_group(p_nombre text, p_materia text default null)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  g public.groups;
begin
  if auth.uid() is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  insert into public.groups (nombre, materia, invite_code, created_by)
  values (trim(p_nombre), nullif(trim(p_materia), ''), public.generate_invite_code(), auth.uid())
  returning * into g;

  insert into public.group_members (group_id, user_id, rol)
  values (g.id, auth.uid(), 'admin');

  return g;
end;
$$;

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

  insert into public.group_members (group_id, user_id, rol)
  values (g.id, auth.uid(), 'miembro')
  on conflict do nothing;

  return g;
end;
$$;

create or replace function public.regenerate_invite_code(p_group_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  codigo text;
begin
  if not public.is_group_admin(p_group_id) then
    raise exception 'Solo el admin puede cambiar el código' using errcode = '42501';
  end if;

  codigo := public.generate_invite_code();
  update public.groups set invite_code = codigo where id = p_group_id;
  return codigo;
end;
$$;

create or replace function public.remove_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_group_admin(p_group_id) then
    raise exception 'Solo el admin puede quitar integrantes' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Para salir del grupo usá "Salir del grupo"' using errcode = 'P0001';
  end if;

  delete from public.group_members where group_id = p_group_id and user_id = p_user_id;
end;
$$;

create or replace function public.set_member_role(p_group_id uuid, p_user_id uuid, p_rol public.rol_miembro)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_group_admin(p_group_id) then
    raise exception 'Solo el admin puede cambiar roles' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() and p_rol <> 'admin' then
    raise exception 'No podés quitarte el rol de admin a vos mismo' using errcode = 'P0001';
  end if;

  update public.group_members set rol = p_rol
  where group_id = p_group_id and user_id = p_user_id;
end;
$$;

-- Salir de un grupo. Si sos el último integrante, el grupo se elimina.
-- Si sos el único admin y quedan otros, tenés que nombrar otro admin antes.
create or replace function public.leave_group(p_group_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  total int;
  admins int;
  soy_admin boolean;
begin
  if not public.is_group_member(p_group_id) then
    raise exception 'No sos integrante de este grupo' using errcode = '42501';
  end if;

  select count(*), count(*) filter (where rol = 'admin')
  into total, admins
  from public.group_members where group_id = p_group_id;

  soy_admin := public.is_group_admin(p_group_id);

  if total = 1 then
    delete from public.groups where id = p_group_id;
    return;
  end if;

  if soy_admin and admins = 1 then
    raise exception 'Nombrá a otro admin antes de salir del grupo' using errcode = 'P0001';
  end if;

  delete from public.group_members where group_id = p_group_id and user_id = auth.uid();
end;
$$;

revoke execute on function public.generate_invite_code() from public, anon, authenticated;
revoke execute on function public.create_group(text, text) from public, anon;
revoke execute on function public.join_group(text) from public, anon;
revoke execute on function public.regenerate_invite_code(uuid) from public, anon;
revoke execute on function public.remove_member(uuid, uuid) from public, anon;
revoke execute on function public.set_member_role(uuid, uuid, public.rol_miembro) from public, anon;
revoke execute on function public.leave_group(uuid) from public, anon;
grant execute on function public.create_group(text, text) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.regenerate_invite_code(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, public.rol_miembro) to authenticated;
grant execute on function public.leave_group(uuid) to authenticated;

-- Realtime: la lista de grupos y de integrantes se actualiza en vivo.
-- replica identity full: los DELETE también llegan (con la clave primaria).
alter table public.groups replica identity full;
alter table public.group_members replica identity full;
alter publication supabase_realtime add table public.groups, public.group_members;
