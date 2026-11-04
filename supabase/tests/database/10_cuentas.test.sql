begin;
create extension if not exists pgtap with schema extensions;

select plan(37);

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_id, 'role', 'authenticated', 'session_id', '00000000-0000-0000-0000-00000000aaaa')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

-- Usuarios con prefijo "t10", para no chocar con datos locales.
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  ('00000000-0000-0000-0000-0000000000a3', 't10.sofi@test.com',
   '{"nombre":"Sofía","username":"T10.Sofi","avatar_url":"https://atacante.com/pixel.png"}', '{"provider":"email"}',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b3', 't10.sofi@otro.com',
   '{"full_name":"Sofía Gómez","avatar_url":"https://lh3.googleusercontent.com/a/foto"}', '{"provider":"google"}',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c3', 't10.equis@test.com', '{"nombre":"Equis","username":"no válido!"}', '{"provider":"email"}',
   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000d3', 't10.otra@test.com', '{"nombre":"Otra","username":"t10.sofi"}', '{"provider":"email"}',
   'authenticated', 'authenticated');

select is((select username from public.profiles where id = '00000000-0000-0000-0000-0000000000a3'), 't10.sofi',
  'el usuario elegido en el registro se guarda en minúsculas');
select is((select username from public.profiles where id = '00000000-0000-0000-0000-0000000000b3'), 't10.sofi2',
  'sin usuario (Google) se genera uno libre a partir del email');
select ok(public.username_valido((select username from public.profiles where id = '00000000-0000-0000-0000-0000000000c3')),
  'si el elegido no es válido, se genera uno válido');
select isnt((select username from public.profiles where id = '00000000-0000-0000-0000-0000000000d3'), 't10.sofi',
  'si el elegido ya está tomado, se genera otro y el alta no falla');
select is((select count(*)::int from public.profiles where username is null), 0, 'ningún perfil queda sin usuario');

-- Foto del alta ----------------------------------------------------------------
select is((select avatar_url from public.profiles where id = '00000000-0000-0000-0000-0000000000a3'), null,
  'en el registro con email no se acepta una foto de los metadatos');
select is((select avatar_url from public.profiles where id = '00000000-0000-0000-0000-0000000000b3'),
  'https://lh3.googleusercontent.com/a/foto', 'la de Google sí');

-- Alta sin confirmar que se repite ---------------------------------------------
update auth.users set raw_user_meta_data = '{"nombre":"Equis Real","username":"t10.equis.real"}'
where id = '00000000-0000-0000-0000-0000000000c3';
select is((select nombre || ' @' || username from public.profiles where id = '00000000-0000-0000-0000-0000000000c3'),
  'Equis Real @t10.equis.real', 'si se registra de nuevo antes de confirmar, el perfil toma los datos nuevos');

-- generar_username --------------------------------------------------------------
select is(public.generar_username('Ñandú José-Pérez'), 'nandu.jose.perez', 'saca tildes y símbolos');
select is(public.generar_username('ab'), 'usuario', 'con una base muy corta usa "usuario"');
select ok(char_length(public.generar_username(repeat('x', 40))) <= 20, 'nunca pasa de 20 caracteres');

-- Disponibilidad -----------------------------------------------------------------
set local role anon;
select ok(not public.username_disponible('t10.sofi'), 'sin sesión se puede consultar: uno tomado no está disponible');
select ok(public.username_disponible('t10.libre'), 'uno libre sí');
select ok(not public.username_disponible('ab'), 'uno muy corto no está disponible');
select ok(not public.username_disponible('.t10'), 'ni uno que empieza con punto');
select ok(not public.username_disponible('t1..0'), 'ni con símbolos seguidos');
select throws_ok($$ select public.generar_username('x') $$, '42501', null, 'generar_username no se llama desde la API');
select throws_ok($$ select * from public.mis_sesiones() $$, '42501', null, 'sin sesión no se ven dispositivos');

-- Editar el perfil ---------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select lives_ok($$ update public.profiles set carrera = 'Ingeniería en Sistemas', universidad = 'UTN' where id = auth.uid() $$,
  'se pueden cargar carrera y universidad');
select throws_ok($$ update public.profiles set carrera = '  UTN  ' where id = auth.uid() $$,
  '23514', null, 'la carrera se guarda sin espacios de más');
select throws_ok(format($$ update public.profiles set carrera = %L where id = auth.uid() $$, repeat('x', 81)),
  '23514', null, 'ni con más de 80 caracteres');
select lives_ok($$ update public.profiles set username = 't10.sofia' where id = auth.uid() $$,
  'se puede cambiar el usuario');
select throws_ok($$ update public.profiles set username = 't10.sofi2' where id = auth.uid() $$,
  '23505', null, 'no se puede usar el usuario de otro');
select throws_ok($$ update public.profiles set username = 'Con Espacios' where id = auth.uid() $$,
  '23514', null, 'ni uno con formato inválido');
update public.profiles set nombre = 'Hackeado' where id = '00000000-0000-0000-0000-0000000000b3';
set local role postgres;
select is((select nombre from public.profiles where id = '00000000-0000-0000-0000-0000000000b3'), 'Sofía Gómez',
  'no se puede editar el perfil de otro');
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select throws_ok($$ update public.profiles set avatar_url = 'https://otro.sitio/x.png' where id = auth.uid() $$,
  '42501', null, 'la foto no se cambia escribiendo la URL');
select throws_ok($$ update public.profiles set plan = 'premium' where id = auth.uid() $$,
  '42501', null, 'ni el plan');

-- Foto ---------------------------------------------------------------------------
select throws_ok($$ select public.set_avatar('00000000-0000-0000-0000-0000000000b3/foto.jpg') $$,
  'P0002', null, 'no se puede usar la foto de la carpeta de otro');
select throws_ok($$ insert into storage.objects (bucket_id, name, owner, metadata)
                    values ('avatares', '00000000-0000-0000-0000-0000000000b3/x.jpg', auth.uid(), '{}') $$,
  '42501', null, 'no se puede subir a la carpeta de fotos de otro');
insert into storage.objects (bucket_id, name, owner, metadata)
values ('avatares', '00000000-0000-0000-0000-0000000000a3/x.jpg', auth.uid(), '{"mimetype":"image/jpeg","size":10}');
select is((public.set_avatar('00000000-0000-0000-0000-0000000000a3/x.jpg')).avatar_url,
  'storage:00000000-0000-0000-0000-0000000000a3/x.jpg', 'con la foto subida a su carpeta, queda como avatar');
select is((public.quitar_avatar()).avatar_url, null, 'y se puede quitar');
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('avatares', '00000000-0000-0000-0000-0000000000a3/y.jpg', auth.uid(), '{}'),
  ('avatares', '00000000-0000-0000-0000-0000000000a3/z.jpg', auth.uid(), '{}');
select throws_ok($$ insert into storage.objects (bucket_id, name, owner, metadata)
                    values ('avatares', '00000000-0000-0000-0000-0000000000a3/w.jpg', auth.uid(), '{}') $$,
  '42501', null, 'como mucho 3 fotos guardadas por persona');

-- Dispositivos -------------------------------------------------------------------
set local role postgres;
insert into auth.sessions (id, user_id, created_at, updated_at, user_agent, not_after) values
  ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000a3', now(), now(), 'Chrome', null),
  ('00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-0000000000a3', now() - interval '1 day', now() - interval '1 day', 'Dart/3.13 (dart:io)', null),
  ('00000000-0000-0000-0000-00000000dddd', '00000000-0000-0000-0000-0000000000a3', now() - interval '9 day', now() - interval '9 day', 'Viejo', now() - interval '1 day'),
  ('00000000-0000-0000-0000-00000000cccc', '00000000-0000-0000-0000-0000000000b3', now(), now(), 'Firefox', null);
select pg_temp.como('00000000-0000-0000-0000-0000000000a3');
select is((select array_agg(actual order by actual desc) from public.mis_sesiones()), array[true, false],
  'cada uno ve solo sus sesiones vigentes, con la actual marcada');
select throws_ok($$ select public.cerrar_sesion('00000000-0000-0000-0000-00000000aaaa') $$,
  'P0001', null, 'la sesión actual se cierra con «Cerrar sesión», no desde la lista');

select public.cerrar_sesion('00000000-0000-0000-0000-00000000cccc');
select public.cerrar_sesion('00000000-0000-0000-0000-00000000bbbb');
set local role postgres;
select is((select array_agg(id::text order by id) from auth.sessions
           where id in ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-00000000bbbb', '00000000-0000-0000-0000-00000000cccc')),
  array['00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-00000000cccc'],
  'se cierra una sesión propia, nunca la de otro');

-- Altas sin confirmar -------------------------------------------------------------
select ok(exists (select 1 from cron.job where jobname = 'borrar-altas-sin-confirmar'),
  'una tarea diaria borra las altas sin confirmar');
select ok((select command from cron.job where jobname = 'borrar-altas-sin-confirmar') like '%email_confirmed_at is null%',
  'y solo las que no confirmaron el email');

select * from finish();
rollback;
