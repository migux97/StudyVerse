begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

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

-- Notificaciones de alguien (como postgres, para no depender de la RLS).
create or replace function pg_temp.notifs(p_user uuid, p_tipo text)
returns integer language sql security definer as $$
  select count(*)::int from public.notificaciones where user_id = p_user and tipo = p_tipo
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000018a1', 'Ana18');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000018b2', 'Beto18');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000018c3', 'Caro18');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000018d4', 'Profe18', 'docente');

select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
create temp table g on commit drop as select * from public.create_group('TP notifs', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000018b2');
select public.join_group((select invite_code from g));

-- Dispositivos ------------------------------------------------------------------
select lives_ok($$ select public.registrar_dispositivo(repeat('t', 40), 'android') $$, 'Beto registra su celular');
select throws_ok($$ insert into public.dispositivos_push (user_id, token, plataforma) values (auth.uid(), repeat('x', 40), 'web') $$,
  '42501', null, 'los dispositivos no se insertan a mano');
select throws_ok($$ select public.registrar_dispositivo(repeat('t', 41), 'ios') $$, 'P0001', null, 'solo android y web');

select pg_temp.como('00000000-0000-0000-0000-0000000018c3');
select is((select count(*)::int from public.dispositivos_push), 0, 'nadie ve los dispositivos de otro');
-- El mismo equipo pasa a otra cuenta: el token queda solo para la nueva.
select public.registrar_dispositivo(repeat('t', 40), 'android');
select is((select count(*)::int from public.dispositivos_push), 1, 'si Caro entra en el mismo equipo, el token es de ella');
select public.quitar_dispositivo(repeat('t', 40));
select is((select count(*)::int from public.dispositivos_push), 0, 'al cerrar sesión se quita');

select pg_temp.como('00000000-0000-0000-0000-0000000018b2');
select public.registrar_dispositivo(repeat('b', 40), 'web');

-- Tareas asignadas ----------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
insert into public.tasks (group_id, titulo, assigned_to, due_date, created_by)
values ((select id from g), 'Introducción', '00000000-0000-0000-0000-0000000018b2', '2026-12-01', auth.uid());
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018b2', 'tarea_asignada'), 1, 'Beto recibe la tarea que le asignaron');
insert into public.tasks (group_id, titulo, assigned_to, created_by)
values ((select id from g), 'Mía', auth.uid(), auth.uid());
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018a1', 'tarea_asignada'), 0, 'no se avisa a quien se asigna a sí mismo');

-- Menciones -----------------------------------------------------------------------
select pg_temp.subir('00000000-0000-0000-0000-0000000018a1', (select id from g), 'Informe.svdoc');
select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
insert into public.comentarios (file_id, group_id, texto, autor)
values ((select id from public.files where group_id = (select id from g)), (select id from g), 'Mirá esto @beto18', auth.uid());
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018b2', 'mencion'), 1, 'Beto recibe la mención');
select is((select count(*)::int from public.notificaciones), 0, 'Ana no ve las notificaciones de Beto');

-- Lo que ve y puede tocar Beto ------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000018b2');
select is((select titulo from public.notificaciones where tipo = 'mencion' and group_id = (select id from g)),
  'Ana18 te mencionó en Informe', 'Beto ve su mención, sin la extensión del documento');
select ok((select ruta like '/grupos/%/documentos/%' from public.notificaciones where tipo = 'mencion' and group_id = (select id from g)),
  'y abre el documento');
update public.notificaciones set leida_at = now() where tipo = 'mencion' and group_id = (select id from g);
select is((select count(*)::int from public.notificaciones where leida_at is not null and group_id = (select id from g)), 1,
  'la marca como leída');
select throws_ok($$ update public.notificaciones set titulo = 'x' $$, '42501', null, 'pero no cambia otra cosa');
select throws_ok($$ insert into public.notificaciones (user_id, tipo, titulo, ruta) values (auth.uid(), 'aviso', 'x', '/') $$,
  '42501', null, 'ni las crea');
select ok(public.realtime_topic_allowed(format('usuario:%s:notificaciones', auth.uid())), 'escucha su campanita en vivo');
select ok(not public.realtime_topic_allowed('usuario:00000000-0000-0000-0000-0000000018a1:notificaciones'),
  'pero no la de otro');

-- Avisos del docente ----------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000018d4');
create temp table curso on commit drop as select * from public.crear_curso('Curso notifs');
grant select on curso to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
select public.sumar_grupo_a_curso((select id from g), (select codigo from curso));
select pg_temp.como('00000000-0000-0000-0000-0000000018d4');
select public.mandar_aviso((select id from curso), null, 'El parcial pasa al jueves');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018a1', 'aviso')
        + pg_temp.notifs('00000000-0000-0000-0000-0000000018b2', 'aviso'), 2, 'el aviso le llega a cada integrante');

-- Sin repetidas: la misma tarea reasignada en bucle no manda diez push.
select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
update public.tasks set assigned_to = null where titulo = 'Introducción' and group_id = (select id from g);
update public.tasks set assigned_to = '00000000-0000-0000-0000-0000000018b2' where titulo = 'Introducción' and group_id = (select id from g);
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018b2', 'tarea_asignada'), 1, 'la misma notificación no se repite al minuto');

-- Pedido de archivo, también al volver a pedirlo.
select pg_temp.como('00000000-0000-0000-0000-0000000018a1');
select public.lock_file((select id from public.files where group_id = (select id from g)), 60);
select pg_temp.como('00000000-0000-0000-0000-0000000018b2');
select public.request_unlock((select id from public.files where group_id = (select id from g)));
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000018a1', 'pedido'), 1, 'a quien edita le llega el pedido');

-- Cola de push ------------------------------------------------------------------------
set local role postgres;
select ok((select count(*) from public.tomar_push(100000) t
           where exists (select 1 from public.notificaciones n where n.id = t.id and n.user_id = '00000000-0000-0000-0000-0000000018b2')) >= 1,
  'las de Beto (que tiene un dispositivo) se toman para mandar');
select is((select push_estado from public.notificaciones
           where user_id = '00000000-0000-0000-0000-0000000018a1' and tipo = 'aviso'), 'sin_dispositivos',
  'las de Ana (sin dispositivos) quedan como sin_dispositivos');

select * from finish();
rollback;
