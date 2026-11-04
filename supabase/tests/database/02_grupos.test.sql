begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

create or replace function pg_temp.crear_usuario(p_id uuid, p_email text, p_nombre text)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, p_email, jsonb_build_object('nombre', p_nombre), 'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.como_postgres()
returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Ana (a), Beto (b) y Caro (c)
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'ana@test.com', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'beto@test.com', 'Beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000c', 'caro@test.com', 'Caro');

-- Ana crea un grupo y queda como admin
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g on commit drop as select * from public.create_group('TP Física', 'Física I');
grant select on g to authenticated;

select is((select rol::text from public.group_members where user_id = auth.uid()), 'admin',
  'quien crea el grupo queda como admin');
select matches((select invite_code from g), '^[A-HJKMNP-Z2-9]{10}$',
  'el código tiene 10 caracteres sin ambiguos');
select throws_ok($$ insert into public.groups (nombre, invite_code) values ('x', 'XXXXXXXX') $$,
  '42501', null, 'no se puede insertar un grupo directo, solo con create_group');

-- Beto no lo ve hasta unirse
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.groups), 0, 'un no-miembro no ve el grupo');
select is((select count(*)::int from public.group_members), 0, 'un no-miembro no ve integrantes');
select throws_ok($$ select public.join_group('ZZZZZZZZ') $$, 'P0002', null, 'código inválido da error');
select throws_ok(
  format($$ insert into public.group_members (group_id, user_id) values (%L, auth.uid()) $$, (select id from g)),
  '42501', null, 'no se puede auto-agregar a un grupo sin código');

select lives_ok(format($$ select public.join_group(%L) $$, lower((select invite_code from g))),
  'unirse con el código (sin importar mayúsculas)');
select is((select count(*)::int from public.groups), 1, 'después de unirse ve el grupo');
select is((select rol::text from public.group_members where user_id = auth.uid()), 'miembro',
  'quien se une queda como miembro');
select is((select nombre from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 'Ana',
  've el perfil de su compañera de grupo');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000c'), 0,
  'no ve perfiles de gente con la que no comparte grupo');

-- Permisos de miembro
select throws_ok(format($$ select public.regenerate_invite_code(%L) $$, (select id from g)),
  '42501', null, 'un miembro no regenera el código');
select throws_ok(format($$ select public.remove_member(%L, %L) $$, (select id from g), '00000000-0000-0000-0000-00000000000a'),
  '42501', null, 'un miembro no quita integrantes');
update public.groups set nombre = 'Hackeado' where id = (select id from g);
select is((select nombre from public.groups), 'TP Física', 'un miembro no renombra el grupo');

-- Permisos de admin
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select throws_ok(format($$ select public.leave_group(%L) $$, (select id from g)),
  'P0001', null, 'el único admin no puede salir si quedan otros');
select isnt(public.regenerate_invite_code((select id from g)), (select invite_code from g),
  'el admin regenera el código');
select lives_ok(format($$ select public.remove_member(%L, %L) $$, (select id from g), '00000000-0000-0000-0000-00000000000b'),
  'el admin quita a un integrante');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select is((select count(*)::int from public.groups), 0, 'quien fue quitado deja de ver el grupo');

-- El último integrante que sale elimina el grupo
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select public.leave_group((select id from g));
select pg_temp.como_postgres();
select is((select count(*)::int from public.groups where id = (select id from g)), 0,
  'si sale el último integrante el grupo se elimina');

select * from finish();
rollback;
