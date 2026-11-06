begin;
create extension if not exists pgtap with schema extensions;

select plan(29);

create or replace function pg_temp.crear_usuario(p_id uuid, p_nombre text, p_tipo text default null)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, lower(p_nombre) || '@test.com',
          jsonb_build_object('nombre', p_nombre, 'username', lower(p_nombre)) || coalesce(jsonb_build_object('tipo', p_tipo), '{}'),
          'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, null, p_nombre, 10);
  perform set_config('role', 'postgres', true);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user, jsonb_build_object('size', 10, 'mimetype', 'text/plain'));
  perform pg_temp.como(p_user);
  select * into fv from public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number, null);
  return fv;
end;
$$;

create or replace function pg_temp.notifs(p_user uuid)
returns integer language sql security definer as $$
  select count(*)::int from public.notificaciones where user_id = p_user and tipo = 'chat'
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000019a1', 'Ana19');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000019b2', 'Beto19');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000019c3', 'Caro19');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000019d4', 'Profe19', 'docente');

select pg_temp.como('00000000-0000-0000-0000-0000000019a1');
create temp table g on commit drop as select * from public.create_group('TP chat', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000019b2');
select public.join_group((select invite_code from g));
select pg_temp.subir('00000000-0000-0000-0000-0000000019a1', (select id from g), 'Consigna.pdf');

-- Escribir ----------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000019a1');
select lives_ok(
  format($$ insert into public.mensajes (group_id, texto, autor) values (%L, '  Hola @beto19, ¿arrancamos?  ', auth.uid()) $$, (select id from g)),
  'un integrante escribe');
create temp table m1 on commit drop as
  select id from public.mensajes where group_id = (select id from g) order by created_at limit 1;
grant select on m1 to authenticated;
select is((select texto from public.mensajes where id = (select id from m1)), 'Hola @beto19, ¿arrancamos?', 'sin espacios de más');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000019b2'), 1, 'a Beto le llega la mención');

select throws_ok(
  format($$ insert into public.mensajes (group_id, texto, autor) values (%L, '   ', auth.uid()) $$, (select id from g)),
  '23514', null, 'no se manda un mensaje vacío');
select throws_ok(
  format($$ insert into public.mensajes (group_id, texto, autor, menciones) values (%L, 'x', auth.uid(), '{}') $$, (select id from g)),
  '42501', null, 'las menciones las pone la base');
select lives_ok(
  format($$ insert into public.mensajes (group_id, file_id, autor) values (%L, %L, auth.uid()) $$,
         (select id from g), (select id from public.files where group_id = (select id from g))),
  'se adjunta un archivo del grupo, sin texto');

-- Responder ----------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000019b2');
select lives_ok(
  format($$ insert into public.mensajes (group_id, texto, autor, responde_a) values (%L, 'Dale', auth.uid(), %L) $$,
         (select id from g), (select id from m1)),
  'Beto responde');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000019a1'), 1, 'a Ana le llega la respuesta');

-- Leídos ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000019a1');
select is((select cantidad from public.chat_sin_leer() where group_id = (select id from g)), 1,
  'Ana tiene 1 sin leer (los suyos no cuentan)');
select public.marcar_chat_leido((select id from g));
select is((select cantidad from public.chat_sin_leer() where group_id = (select id from g)), null,
  'al abrir el chat queda leído');

-- Editar y borrar --------------------------------------------------------------------
update public.mensajes set texto = 'Hola @beto19, ¿arrancamos mañana?' where id = (select id from m1);
select ok((select editado_at is not null from public.mensajes where id = (select id from m1)), 'Ana edita el suyo y queda marcado');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000019b2'), 1, 'editar no vuelve a avisar');

select pg_temp.como('00000000-0000-0000-0000-0000000019b2');
update public.mensajes set texto = 'Hackeado' where id = (select id from m1);
select is((select texto from public.mensajes where id = (select id from m1)), 'Hola @beto19, ¿arrancamos mañana?',
  'Beto no edita el de Ana');
select throws_ok(format($$ select public.borrar_mensaje(%L) $$, (select id from m1)),
  'P0001', null, 'ni lo borra');

select pg_temp.como('00000000-0000-0000-0000-0000000019a1');
select public.borrar_mensaje((select id from m1));
select is((select row(texto, borrado_at is not null)::text from public.mensajes where id = (select id from m1)),
  row(null::text, true)::text, 'Ana lo borra: queda el lugar sin el texto');
update public.mensajes set texto = 'Volví' where id = (select id from m1);
select is((select texto from public.mensajes where id = (select id from m1)), null, 'un mensaje borrado no se edita');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000019b2'), 0, 'y la mención sale de la campanita de Beto');
select throws_ok(
  format($$ insert into public.mensajes (group_id, texto, autor, responde_a) values (%L, 'Eh', auth.uid(), %L) $$,
         (select id from g), (select id from m1)),
  '42501', null, 'no se responde a un mensaje borrado');
select lives_ok(
  format($$ select public.borrar_mensaje(%L) $$,
         (select id from public.mensajes where group_id = (select id from g) and texto = 'Dale')),
  'la admin borra el de Beto');
select throws_ok(
  format($$ insert into public.chat_leido (group_id, user_id) values (%L, auth.uid()) $$, (select id from g)),
  '42501', null, 'chat_leido se escribe solo con marcar_chat_leido');

-- Si el archivo se elimina para siempre, el mensaje que lo tenía solo queda borrado.
set local role postgres;
delete from public.files where group_id = (select id from g);
select is((select count(*)::int from public.mensajes
           where group_id = (select id from g) and texto is null and file_id is null and borrado_at is null), 0,
  'eliminar para siempre un adjunto no deja mensajes vacíos');

-- Afuera, el docente y el tope ------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000019c3');
select is((select count(*)::int from public.mensajes where group_id = (select id from g)), 0, 'alguien de afuera no lee el chat');
select throws_ok(
  format($$ insert into public.mensajes (group_id, texto, autor) values (%L, 'Hola', auth.uid()) $$, (select id from g)),
  '42501', null, 'ni escribe');
select ok(not public.realtime_topic_allowed(format('grupo:%s:chat', (select id from g))), 'ni lo escucha en vivo');

select pg_temp.como('00000000-0000-0000-0000-0000000019d4');
create temp table curso on commit drop as select * from public.crear_curso('Curso chat');
grant select on curso to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000019a1');
select public.sumar_grupo_a_curso((select id from g), (select codigo from curso));
select pg_temp.como('00000000-0000-0000-0000-0000000019d4');
select is((select count(*)::int from public.mensajes where group_id = (select id from g)), 0,
  'el docente del curso tampoco lee el chat');
select ok(not public.realtime_topic_allowed(format('grupo:%s:chat', (select id from g))), 'ni lo escucha');

select pg_temp.como('00000000-0000-0000-0000-0000000019b2');
select ok(public.realtime_topic_allowed(format('grupo:%s:chat', (select id from g))), 'un integrante sí lo escucha');
create or replace function pg_temp.rafaga(p_n integer)
returns void language plpgsql as $$
begin
  for i in 1..p_n loop
    insert into public.mensajes (group_id, texto, autor) values ((select id from g), 'spam ' || i, auth.uid());
  end loop;
end;
$$;
grant execute on all functions in schema pg_temp to authenticated;
select throws_ok($$ select pg_temp.rafaga(40) $$, 'P0001', null, 'no se mandan más de 30 mensajes por minuto');
select is((select count(*)::int from public.mensajes where group_id = (select id from g) and texto like 'spam%'), 0,
  'y la ráfaga no queda a medias');

select * from finish();
rollback;
