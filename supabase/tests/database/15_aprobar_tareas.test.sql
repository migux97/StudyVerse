begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

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

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000015a1', 'Ana15');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000015b2', 'Beto15');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000015c3', 'Caro15');

-- Ana (admin) con Beto -------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000015a1');
create temp table g on commit drop as select * from public.create_group('TP aprobación', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000015b2');
select public.join_group((select invite_code from g));

insert into public.tasks (group_id, titulo, assigned_to, created_by)
values ((select id from g), 'Introducción', auth.uid(), auth.uid()),
       ((select id from g), 'Gráficos', auth.uid(), auth.uid());
create temp table t on commit drop as
  select id, titulo from public.tasks where group_id = (select id from g);
grant select on t to authenticated;

-- Sin aprobación: como siempre -------------------------------------------------------
select lives_ok(
  format($$ update public.tasks set estado = 'hecha' where id = %L $$, (select id from t where titulo = 'Gráficos')),
  'sin aprobación, cualquier integrante la marca hecha');
update public.tasks set estado = 'pendiente' where id = (select id from t where titulo = 'Gráficos');

-- Solo el admin activa la aprobación ------------------------------------------------
update public.groups set aprobar_tareas = true where id = (select id from g);
select is((select aprobar_tareas from public.groups where id = (select id from g)), false,
  'un integrante no activa la aprobación');

select pg_temp.como('00000000-0000-0000-0000-0000000015a1');
update public.groups set aprobar_tareas = true where id = (select id from g);
select is((select aprobar_tareas from public.groups where id = (select id from g)), true, 'el admin la activa');

-- Con aprobación ---------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000015b2');
select throws_ok(
  format($$ update public.tasks set estado = 'hecha' where id = %L $$, (select id from t where titulo = 'Introducción')),
  'P0001', null, 'con aprobación, un integrante ya no la marca hecha');

select throws_ok(
  format($$ insert into public.tasks (group_id, titulo, estado, created_by) values (%L, 'Atajo', 'hecha', auth.uid()) $$,
         (select id from g)),
  'P0001', null, 'ni la crea ya hecha');

insert into public.tasks (group_id, titulo, created_by, revisada_por, revision_nota, entregada_por)
values ((select id from g), 'Falsa', auth.uid(), '00000000-0000-0000-0000-0000000015a1', 'Inventada', auth.uid());
select is(
  (select row(revisada_por, revision_nota, entregada_por)::text from public.tasks
   where group_id = (select id from g) and titulo = 'Falsa'),
  row(null::uuid, null::text, null::uuid)::text, 'al crear una tarea no se inventan entrega ni revisión');

select throws_ok(
  format($$ update public.tasks set entregada_por = auth.uid() where id = %L $$, (select id from t where titulo = 'Introducción')),
  '42501', null, 'el cliente no escribe los datos de la entrega');

select is(
  (select estado::text from public.entregar_tarea((select id from t where titulo = 'Introducción'), ' Está en la carpeta TP 2 ')),
  'entregada', 'el responsable la entrega');

select is(
  (select row(entregada_por, entrega_nota)::text from public.tasks where id = (select id from t where titulo = 'Introducción')),
  row('00000000-0000-0000-0000-0000000015b2'::uuid, 'Está en la carpeta TP 2')::text,
  'queda quién la entregó y su nota');

select throws_ok(
  format($$ select public.revisar_tarea(%L, true) $$, (select id from t where titulo = 'Introducción')),
  'P0001', 'Solo un admin puede revisar tareas', 'un integrante no se aprueba a sí mismo');

select throws_ok(
  format($$ update public.tasks set estado = 'en_progreso' where id = %L $$, (select id from t where titulo = 'Introducción')),
  'P0001', null, 'ni saca la tarea de entregada para deshacer la revisión');

-- Revisión del admin ---------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000015a1');
select throws_ok(
  format($$ select public.revisar_tarea(%L, false, '  ') $$, (select id from t where titulo = 'Introducción')),
  'P0001', 'Contale qué hay que cambiar', 'pedir cambios pide una nota');

select is(
  (select estado::text from public.revisar_tarea((select id from t where titulo = 'Introducción'), false, 'Falta la bibliografía')),
  'en_progreso', 'pedir cambios la devuelve a en progreso');

select is(
  (select row(revision_nota, entregada_por is null)::text from public.tasks where id = (select id from t where titulo = 'Introducción')),
  row('Falta la bibliografía', true)::text, 'queda la nota del admin y se borra la entrega');

select is(
  (select count(*)::int from public.activity
   where group_id = (select id from g) and tipo = 'tarea_cambios_pedidos' and payload->>'a' = 'Beto15'),
  1, 'la actividad lo registra (sin copiar la nota)');

select throws_ok(
  format($$ select public.revisar_tarea(%L, true) $$, (select id from t where titulo = 'Introducción')),
  'P0001', 'Esta tarea no está entregada', 'no se aprueba algo que no está entregado');

select pg_temp.como('00000000-0000-0000-0000-0000000015b2');
select public.entregar_tarea((select id from t where titulo = 'Introducción'));
select is(
  (select revision_nota from public.tasks where id = (select id from t where titulo = 'Introducción')),
  null, 'al volver a entregar se limpia la nota de cambios');

select pg_temp.como('00000000-0000-0000-0000-0000000015a1');
select is(
  (select estado::text from public.revisar_tarea((select id from t where titulo = 'Introducción'), true)),
  'hecha', 'el admin la aprueba');

select is(
  (select row(revisada_por, completed_at is not null)::text from public.tasks where id = (select id from t where titulo = 'Introducción')),
  row('00000000-0000-0000-0000-0000000015a1'::uuid, true)::text, 'queda quién la aprobó y cuándo se completó');

select is(
  (select count(*)::int from public.activity where group_id = (select id from g) and tipo = 'tarea_aprobada'),
  1, 'la actividad registra la aprobación');

select lives_ok(
  format($$ update public.tasks set estado = 'hecha' where id = %L $$, (select id from t where titulo = 'Gráficos')),
  'el admin puede marcarla hecha directo');

select pg_temp.como('00000000-0000-0000-0000-0000000015b2');
select throws_ok(
  format($$ update public.tasks set estado = 'pendiente' where id = %L $$, (select id from t where titulo = 'Gráficos')),
  'P0001', null, 'un integrante no reabre una tarea aprobada');
select pg_temp.como('00000000-0000-0000-0000-0000000015a1');

select throws_ok(
  format($$ select public.entregar_tarea(%L) $$, (select id from t where titulo = 'Gráficos')),
  'P0001', 'Esta tarea ya está hecha', 'no se entrega lo que ya está hecho');

-- Alguien de afuera ---------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000015c3');
select throws_ok(
  format($$ select public.entregar_tarea(%L) $$, (select id from t where titulo = 'Introducción')),
  'P0002', null, 'alguien de afuera no entrega tareas del grupo');

select * from finish();
rollback;
