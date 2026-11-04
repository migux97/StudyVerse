begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

create or replace function pg_temp.crear_usuario(p_id uuid, p_nombre text)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, lower(p_nombre) || '@test.com', jsonb_build_object('nombre', p_nombre), 'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Mensajes que mandaron los triggers a un canal (como postgres, para verlos todos).
create or replace function pg_temp.avisos(p_topic text)
returns integer language sql as $$
  select count(*)::int from realtime.messages where topic = p_topic
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000a2', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000b2', 'Beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000c2', 'Caro');

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
create temp table g on commit drop as select * from public.create_group('Realtime', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select public.join_group((select invite_code from g));

-- Quién puede escuchar qué --------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select ok(public.realtime_topic_allowed(format('grupo:%s:tareas', (select id from g))),
  'un integrante escucha los canales de su grupo');
select ok(public.realtime_topic_allowed('usuario:00000000-0000-0000-0000-0000000000b2:grupos'),
  'y los suyos');
select ok(not public.realtime_topic_allowed('usuario:00000000-0000-0000-0000-0000000000a2:pedidos'),
  'no los de otro usuario');
select ok(not public.realtime_topic_allowed(format('grupo:%s:secreto', (select id from g))),
  'ni canales que no existen');

select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select ok(not public.realtime_topic_allowed(format('grupo:%s:archivos', (select id from g))),
  'alguien de afuera no escucha los canales del grupo');
select ok(not public.realtime_topic_allowed('grupo:no-es-un-uuid:archivos'),
  'un canal mal armado no da error ni acceso');
select ok(not public.realtime_topic_allowed('grupo:' || repeat('-', 36) || ':archivos'),
  'ni uno con 36 guiones en lugar del uuid');

-- Los triggers avisan sin datos --------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
insert into public.tasks (group_id, titulo, created_by) values ((select id from g), 'T', auth.uid());
delete from public.tasks where titulo = 'T' and group_id = (select id from g);
set local role postgres;
select is(pg_temp.avisos(format('grupo:%s:tareas', (select id from g))), 2,
  'crear y borrar una tarea avisa al canal de tareas del grupo');
select ok((select bool_and(payload - 'id' = '{}'::jsonb and private)
           from realtime.messages where topic = format('grupo:%s:tareas', (select id from g))),
  'los avisos son privados y no llevan datos de la fila');

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
select public.leave_group((select id from g));
set local role postgres;
select ok(pg_temp.avisos('usuario:00000000-0000-0000-0000-0000000000b2:grupos') > 0,
  'quien sale del grupo recibe el aviso en su canal');
select ok(pg_temp.avisos('usuario:00000000-0000-0000-0000-0000000000a2:grupos') > 0,
  'y los que quedan, en el suyo');

-- Sin eventos de filas -----------------------------------------------------------
select is((select count(*)::int from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public'), 0,
  'ninguna tabla publica sus filas por postgres_changes');

select pg_temp.como('00000000-0000-0000-0000-0000000000c2');
select throws_ok($$ insert into realtime.messages (topic, extension, event, payload, private)
                    values ('usuario:00000000-0000-0000-0000-0000000000a2:pedidos', 'broadcast', 'pedido', '{}', true) $$,
  '42501', null, 'un cliente no puede mandar avisos a los canales');

select * from finish();
rollback;
