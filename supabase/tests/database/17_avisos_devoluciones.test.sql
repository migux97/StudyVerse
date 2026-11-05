begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

create or replace function pg_temp.crear_usuario(p_id uuid, p_nombre text, p_tipo text default null)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, lower(p_nombre) || '@test.com',
          jsonb_build_object('nombre', p_nombre) || coalesce(jsonb_build_object('tipo', p_tipo), '{}'),
          'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000017d1', 'Profe17', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000017e2', 'Otra17', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000017a1', 'Ana17');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000017b2', 'Beto17');

-- Curso con dos grupos: el de Ana y el de Beto -------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000017d1');
create temp table curso on commit drop as select * from public.crear_curso('Química');
grant select on curso to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000017a1');
create temp table ga on commit drop as select * from public.create_group('Grupo A', null);
grant select on ga to authenticated;
select public.sumar_grupo_a_curso((select id from ga), (select codigo from curso));
insert into public.tasks (group_id, titulo, assigned_to, created_by)
values ((select id from ga), 'Informe', auth.uid(), auth.uid());
create temp table t on commit drop as select id from public.tasks where group_id = (select id from ga);
grant select on t to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000017b2');
create temp table gb on commit drop as select * from public.create_group('Grupo B', null);
grant select on gb to authenticated;
select public.sumar_grupo_a_curso((select id from gb), (select codigo from curso));
create temp table gc on commit drop as select * from public.create_group('Grupo C', null);
grant select on gc to authenticated;

-- Avisos ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000017a1');
select throws_ok(
  format($$ select public.mandar_aviso(%L, null, 'Hack') $$, (select id from curso)),
  'P0001', null, 'un estudiante no manda avisos');
select throws_ok(
  format($$ insert into public.avisos (curso_id, texto) values (%L, 'x') $$, (select id from curso)),
  '42501', null, 'ni los inserta a mano');

select pg_temp.como('00000000-0000-0000-0000-0000000017d1');
select is((select texto from public.mandar_aviso((select id from curso), null, '  El parcial pasa al jueves ')),
  'El parcial pasa al jueves', 'el docente avisa a todo el curso');
select lives_ok(
  format($$ select public.mandar_aviso(%L, %L, 'Grupo A: revisen la consigna') $$, (select id from curso), (select id from ga)),
  'y a un grupo solo');
select throws_ok(
  format($$ select public.mandar_aviso(%L, %L, 'x') $$, (select id from curso), (select id from gc)),
  'P0001', 'Ese grupo no está en el curso', 'no avisa a un grupo que no está en el curso');

select pg_temp.como('00000000-0000-0000-0000-0000000017e2');
select throws_ok(
  format($$ select public.mandar_aviso(%L, null, 'Hack') $$, (select id from curso)),
  'P0001', null, 'otro docente no avisa en un curso ajeno');
select is((select count(*)::int from public.avisos where curso_id = (select id from curso)), 0,
  'ni lee sus avisos');

select pg_temp.como('00000000-0000-0000-0000-0000000017a1');
select is((select count(*)::int from public.avisos where curso_id = (select id from curso)), 2,
  'Ana ve el aviso del curso y el de su grupo');
select is((select count(*)::int from public.activity where group_id = (select id from ga) and tipo = 'aviso_docente'), 2,
  'y quedan en la actividad de su grupo');

select pg_temp.como('00000000-0000-0000-0000-0000000017b2');
select is((select count(*)::int from public.avisos where curso_id = (select id from curso)), 1,
  'Beto solo ve el del curso');
select public.quitar_grupo_de_curso((select id from gb));
select is((select count(*)::int from public.avisos where curso_id = (select id from curso)), 0,
  'si su grupo sale del curso, deja de verlos');

select ok(public.realtime_topic_allowed(format('usuario:%s:avisos', auth.uid())), 'escucha sus avisos en vivo');

-- Devoluciones ------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000017a1');
select throws_ok(
  format($$ insert into public.devoluciones (task_id, group_id, texto, autor) values (%L, %L, 'Me apruebo', auth.uid()) $$,
         (select id from t), (select id from ga)),
  '42501', null, 'un estudiante no escribe devoluciones');

select pg_temp.como('00000000-0000-0000-0000-0000000017d1');
select lives_ok(
  format($$ insert into public.devoluciones (task_id, group_id, texto, autor) values (%L, %L, 'Falta citar la bibliografía', auth.uid()) $$,
         (select id from t), (select id from ga)),
  'el docente deja una devolución en la tarea');
select throws_ok(
  format($$ insert into public.devoluciones (task_id, group_id, texto, autor) values (%L, %L, 'x', auth.uid()) $$,
         (select id from t), (select id from gb)),
  '42501', null, 'no en un grupo que no es de su curso');

select pg_temp.como('00000000-0000-0000-0000-0000000017a1');
select is((select texto from public.devoluciones where task_id = (select id from t)), 'Falta citar la bibliografía',
  'el grupo ve la devolución');
select is((select count(*)::int from public.activity where group_id = (select id from ga) and tipo = 'devolucion'), 1,
  'y queda en la actividad');

select pg_temp.como('00000000-0000-0000-0000-0000000017b2');
select is((select count(*)::int from public.devoluciones where task_id = (select id from t)), 0,
  'otro grupo no la ve');

select * from finish();
rollback;
