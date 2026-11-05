begin;
create extension if not exists pgtap with schema extensions;

select plan(33);

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

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000016d1', 'Profe16', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000016a1', 'Ana16');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000016b2', 'Beto16', 'cualquiera');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000016e3', 'Otra16', 'docente');

-- Tipo de cuenta ------------------------------------------------------------------
select is((select tipo_cuenta::text from public.profiles where id = '00000000-0000-0000-0000-0000000016d1'),
  'docente', 'al registrarse como docente queda docente');
select is((select tipo_cuenta::text from public.profiles where id = '00000000-0000-0000-0000-0000000016b2'),
  'estudiante', 'cualquier otro valor queda como estudiante');

-- Cursos ------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000016a1');
select throws_ok($$ select public.crear_curso('Hack') $$, 'P0001', 'Solo una cuenta de docente puede crear cursos',
  'un estudiante no crea cursos');

select pg_temp.como('00000000-0000-0000-0000-0000000016d1');
create temp table curso on commit drop as select * from public.crear_curso('  Física II · Comisión 3 ');
grant select on curso to authenticated;
select is((select nombre from curso), 'Física II · Comisión 3', 'un docente crea un curso');
select ok((select codigo ~ '^[A-Z0-9]{10}$' from curso), 'con un código de 10 caracteres');
select throws_ok($$ insert into public.cursos (nombre, codigo, docente_id) values ('x', 'ABC', auth.uid()) $$,
  '42501', null, 'los cursos no se insertan a mano');

-- Grupo de Ana con Beto, sumado al curso -------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000016a1');
create temp table g on commit drop as select * from public.create_group('TP del curso', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000016b2');
select public.join_group((select invite_code from g));
select pg_temp.subir('00000000-0000-0000-0000-0000000016a1', (select id from g), 'Informe.txt');
insert into public.tasks (group_id, titulo, created_by) values ((select id from g), 'Introducción', auth.uid());

-- Antes de sumarlo, el docente no ve nada.
select pg_temp.como('00000000-0000-0000-0000-0000000016d1');
select is(public.grupo_para_docente((select id from g)), null, 'el docente no ve grupos ajenos');

select pg_temp.como('00000000-0000-0000-0000-0000000016b2');
select throws_ok(
  format($$ select public.sumar_grupo_a_curso(%L, %L) $$, (select id from g), (select codigo from curso)),
  'P0001', null, 'un integrante que no es admin no suma el grupo');

select pg_temp.como('00000000-0000-0000-0000-0000000016a1');
select throws_ok(
  format($$ select public.sumar_grupo_a_curso(%L, 'NOEXISTE00') $$, (select id from g)),
  'P0001', 'No encontramos un curso con ese código', 'un código equivocado avisa');
select is(
  (select nombre from public.sumar_grupo_a_curso((select id from g), lower((select codigo from curso)))),
  'Física II · Comisión 3', 'el admin lo suma con el código (sin importar mayúsculas)');
select throws_ok(
  format($$ update public.groups set curso_id = null where id = %L $$, (select id from g)),
  '42501', null, 'el curso no se cambia a mano');
select is((select nombre from public.cursos where id = (select id from curso)), 'Física II · Comisión 3',
  'los integrantes ven el curso de su grupo');
select is((select nombre from public.profiles where id = '00000000-0000-0000-0000-0000000016d1'), 'Profe16',
  'y el nombre del docente');

-- Lo que ve el docente ------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000016d1');
select is((public.grupo_para_docente((select id from g)) ->> 'nombre'), 'TP del curso', 'el docente ve el grupo');
select is((select count(*)::int from public.groups where id = (select id from g)), 0,
  'pero no la fila de groups (con el código de invitación)');
select is((public.grupo_para_docente((select id from g)) ? 'invite_code'), false, 'la función no lo devuelve');
select is(jsonb_array_length(public.grupos_del_curso((select id from curso))), 1, 've los grupos de su curso');
create temp table codigo on commit drop as select invite_code from g;
grant select on codigo to authenticated;
select throws_ok(
  format($$ select public.join_group(%L) $$, (select invite_code from codigo)),
  'P0001', null, 'aunque consiga el código, no entra como integrante');
select is((select count(*)::int from public.group_members where group_id = (select id from g)), 2, 'y sus integrantes');
select is((select count(*)::int from public.profiles where id in ('00000000-0000-0000-0000-0000000016a1',
                                                                  '00000000-0000-0000-0000-0000000016b2')), 2,
  'y sus perfiles');
select is((select count(*)::int from public.files where group_id = (select id from g)), 1, 've los archivos');
select is((select count(*)::int from public.file_versions where group_id = (select id from g)), 1, 'y sus versiones');
select is((select count(*)::int from storage.objects o
           where o.bucket_id = 'archivos' and o.name like format('groups/%s/%%', (select id from g))), 1,
  'y puede descargarlos');
select is((select count(*)::int from public.tasks where group_id = (select id from g)), 1, 've las tareas');
select is((select count(*)::int from public.group_contributions((select id from g))), 2, 've los aportes');
select ok(public.realtime_topic_allowed(format('grupo:%s:tareas', (select id from g))), 'escucha las tareas en vivo');
select ok(not public.realtime_topic_allowed(format('grupo:%s:documentos', (select id from g))),
  'pero no los documentos mientras se escriben');

select lives_ok(
  format($$ insert into public.comentarios (file_id, group_id, texto, autor) values (%L, %L, 'Buen avance', auth.uid()) $$,
         (select id from public.files where group_id = (select id from g)), (select id from g)),
  'el docente comenta');

-- Solo lectura -------------------------------------------------------------------------
select throws_ok(
  format($$ select * from public.begin_upload(%L, null, 'x.txt', 10) $$, (select id from g)),
  '42501', null, 'el docente no sube archivos');
update public.tasks set titulo = 'Cambiada' where group_id = (select id from g);
select is((select titulo from public.tasks where group_id = (select id from g)), 'Introducción',
  'ni edita tareas');

-- Otro docente no ve nada; quitar del curso corta el acceso ---------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000016e3');
select is((select count(*)::int from public.files where group_id = (select id from g)), 0,
  'otro docente no ve los grupos de un curso ajeno');

select pg_temp.como('00000000-0000-0000-0000-0000000016d1');
update public.profiles set tipo_cuenta = 'estudiante' where id = auth.uid();
select is((select count(*)::int from public.files where group_id = (select id from g)), 0,
  'si deja de ser docente, deja de ver los grupos');
update public.profiles set tipo_cuenta = 'docente' where id = auth.uid();
select public.quitar_grupo_de_curso((select id from g));
select is((select count(*)::int from public.files where group_id = (select id from g)), 0,
  'si el grupo sale del curso, el docente deja de verlo');

select * from finish();
rollback;
