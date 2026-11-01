begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

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

create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, null, p_nombre, 100);
  perform set_config('role', 'postgres', true);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user, jsonb_build_object('size', 100));
  perform pg_temp.como(p_user);
  select * into fv from public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number);
  return fv;
end;
$$;

-- Último evento visible para el usuario actual.
create or replace function pg_temp.ultimo()
returns public.activity language sql as $$
  select * from public.activity order by created_at desc, id desc limit 1
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'Juan');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000c', 'Caro');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g on commit drop as select * from public.create_group('TP', null);
grant select on g to authenticated;
select is((select count(*)::int from public.activity), 0, 'crear el grupo no cuenta como "se unió"');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.join_group((select invite_code from g));
select is((select tipo from pg_temp.ultimo()), 'miembro_unido', 'unirse queda en la actividad');

-- Tareas -----------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
insert into public.tasks (group_id, titulo, assigned_to, due_date, created_by)
values ((select id from g), 'Escribir la introducción', '00000000-0000-0000-0000-00000000000b', current_date + 3, auth.uid());
create temp table t on commit drop as select * from public.tasks;
grant select on t to authenticated;

select is((select tipo from pg_temp.ultimo()), 'tarea_creada', 'crear una tarea queda en la actividad');
select is((select payload ->> 'a' from pg_temp.ultimo()), 'Juan', 'con el nombre del responsable');

select throws_ok(
  format($$ insert into public.tasks (group_id, titulo, assigned_to, created_by) values (%L, 'x', %L, auth.uid()) $$,
         (select id from g), '00000000-0000-0000-0000-00000000000c'),
  'P0001', 'El responsable tiene que ser del grupo', 'no se puede asignar a alguien de afuera');
select throws_ok(
  format($$ insert into public.tasks (group_id, titulo, created_by) values (%L, 'x', %L) $$,
         (select id from g), '00000000-0000-0000-0000-00000000000b'),
  '42501', null, 'no se puede crear una tarea a nombre de otro');

select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.tasks), 0, 'un no-miembro no ve las tareas');
select is((select count(*)::int from public.activity), 0, 'ni la actividad');
select throws_ok(
  format($$ insert into public.tasks (group_id, titulo, created_by) values (%L, 'x', auth.uid()) $$, (select id from g)),
  '42501', null, 'ni puede crear tareas');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
update public.tasks set estado = 'en_progreso' where id = (select id from t);
select is((select completed_at from public.tasks where id = (select id from t)), null, 'en progreso no tiene fecha de completada');
update public.tasks set estado = 'hecha' where id = (select id from t);
select isnt((select completed_at from public.tasks where id = (select id from t)), null, 'al marcarla hecha se guarda completed_at');
select is((select tipo from pg_temp.ultimo()), 'tarea_completada', 'completar una tarea queda en la actividad');
select is((select user_id from pg_temp.ultimo()), '00000000-0000-0000-0000-00000000000b'::uuid, 'a nombre de quien la completó');
update public.tasks set estado = 'pendiente' where id = (select id from t);
select is((select completed_at from public.tasks where id = (select id from t)), null, 'reabrirla borra completed_at');
update public.tasks set estado = 'hecha' where id = (select id from t);

select throws_ok(format($$ update public.tasks set created_by = auth.uid() where id = %L $$, (select id from t)),
  '42501', null, 'no se puede cambiar quién creó la tarea');
delete from public.tasks where id = (select id from t);
select is((select count(*)::int from public.tasks), 1, 'un miembro no elimina tareas que no creó');

-- Archivos ----------------------------------------------------------------------
select pg_temp.subir('00000000-0000-0000-0000-00000000000b', (select id from g), 'Informe.docx');
select pg_temp.subir('00000000-0000-0000-0000-00000000000b', (select id from g), 'Informe.docx');
select is((select tipo || ' v' || (payload ->> 'version') from pg_temp.ultimo()), 'version_subida v2',
  'subir una versión queda en la actividad');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.lock_file((select id from public.files limit 1));
select is((select tipo from pg_temp.ultimo()), 'archivo_bloqueado', 'bloquear queda en la actividad');
select public.lock_file((select id from public.files limit 1));
select is((select count(*)::int from public.activity where tipo = 'archivo_bloqueado'), 1, 'renovar no repite el aviso');

select pg_temp.subir('00000000-0000-0000-0000-00000000000b', (select id from g), 'Informe.docx');
select is((select count(*)::int from public.activity where tipo = 'archivo_desbloqueado'), 0,
  'el desbloqueo automático al subir no se anuncia aparte');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.lock_file((select id from public.files limit 1));
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select public.unlock_file((select id from public.files limit 1));
select is((select tipo || ' de ' || (payload ->> 'de') from pg_temp.ultimo()), 'desbloqueo_forzado de Juan',
  'el desbloqueo forzado dice a quién');

select public.restore_version((select id from public.file_versions where version_number = 1));
select is((select tipo || ' desde v' || (payload ->> 'desde') from pg_temp.ultimo()), 'version_restaurada desde v1',
  'restaurar se distingue de subir');

-- Aportes ---------------------------------------------------------------------------
select is(
  (select tareas_completadas || '/' || versiones_subidas from public.group_contributions((select id from g))
   where nombre = 'Juan'),
  '1/3', 'aportes de Juan: 1 tarea completada y 3 versiones');
select is(
  (select tareas_completadas || '/' || versiones_subidas from public.group_contributions((select id from g))
   where nombre = 'Ana'),
  '0/1', 'aportes de Ana: la restauración cuenta como versión');

select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select throws_ok(format($$ select * from public.group_contributions(%L) $$, (select id from g)),
  '42501', null, 'un no-miembro no ve los aportes');

-- Salir y borrar el grupo ------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select public.remove_member((select id from g), '00000000-0000-0000-0000-00000000000b');
select is((select tipo || ' por ' || (payload ->> 'por') from pg_temp.ultimo()), 'miembro_salio por Ana',
  'si lo quitan, dice quién');
select lives_ok(format($$ select public.leave_group(%L) $$, (select id from g)),
  'el último en salir borra el grupo sin que fallen los triggers de actividad');

select * from finish();
rollback;
