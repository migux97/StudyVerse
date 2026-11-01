begin;
create extension if not exists pgtap with schema extensions;

select plan(8);

-- Helpers de prueba: crear usuarios y actuar como ellos.
create or replace function pg_temp.crear_usuario(p_id uuid, p_email text, p_meta jsonb default '{}')
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, p_email, p_meta, 'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'ana@test.com', '{"nombre": "Ana"}');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'juan.perez@test.com');

-- Trigger de alta
select is(
  (select nombre from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'Ana', 'el perfil toma el nombre del registro');
select is(
  (select nombre from public.profiles where id = '00000000-0000-0000-0000-00000000000b'),
  'juan.perez', 'sin nombre, usa la parte local del email');
select is(
  (select plan::text from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'free', 'plan free por defecto');

-- RLS
select pg_temp.como('00000000-0000-0000-0000-00000000000a');

select is((select count(*)::int from public.profiles), 1, 'Ana solo ve su perfil');

update public.profiles set nombre = 'Juan hackeado' where id = '00000000-0000-0000-0000-00000000000b';
select is(
  (select count(*)::int from public.profiles where nombre = 'Juan hackeado'), 0,
  'Ana no puede editar el perfil de Juan');

update public.profiles set nombre = 'Ana María' where id = '00000000-0000-0000-0000-00000000000a';
select is((select nombre from public.profiles), 'Ana María', 'Ana edita su nombre');

select throws_ok(
  $$ update public.profiles set plan = 'premium' where id = '00000000-0000-0000-0000-00000000000a' $$,
  '42501', null, 'el cliente no puede cambiarse el plan');

select is((select count(*)::int from public.plan_limits), 2, 'los límites de planes son legibles');

select * from finish();
rollback;
