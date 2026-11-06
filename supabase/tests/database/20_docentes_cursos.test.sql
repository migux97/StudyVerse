begin;
create extension if not exists pgtap with schema extensions;

select plan(106);

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

create or replace function pg_temp.notifs(p_user uuid, p_tipo text)
returns integer language sql security definer as $$
  select count(*)::int from public.notificaciones where user_id = p_user and tipo = p_tipo
$$;

grant execute on all functions in schema pg_temp to authenticated;

-- Ana20 y Beto20 (grupo del curso 1), Caro20 (alumna sin grupo), Dani20 (grupo del curso 2),
-- Profe20 (titular), Ayu20 (ayudante) y Otro20 (docente de otro curso).
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020a1', 'Ana20');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020b2', 'Beto20');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020c3', 'Caro20');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020d4', 'Dani20');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020e5', 'Profe20', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020f6', 'Ayu20', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000020a7', 'Otro20', 'docente');

select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
create temp table curso on commit drop as select * from public.crear_curso('Curso 20');
grant select on curso to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
create temp table curso2 on commit drop as select * from public.crear_curso('Curso 20 B');
grant select on curso2 to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
create temp table g on commit drop as select * from public.create_group('Grupo 20', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select public.join_group((select invite_code from g));
select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select public.sumar_grupo_a_curso((select id from g), (select codigo from curso));
select pg_temp.subir('00000000-0000-0000-0000-0000000020a1', (select id from g), 'TP.txt');
create temp table f on commit drop as select id from public.files where group_id = (select id from g);
grant select on f to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000020d4');
create temp table g2 on commit drop as select * from public.create_group('Grupo 20 B', null);
grant select on g2 to authenticated;
select public.sumar_grupo_a_curso((select id from g2), (select codigo from curso2));

-- Ayudantes ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
select throws_ok(
  format($$ select public.sumar_ayudante(%L, 'caro20') $$, (select id from curso)),
  'P0001', null, 'no se suma como ayudante a una cuenta de alumno');
select throws_ok(
  format($$ select public.sumar_ayudante(%L, 'nadie20') $$, (select id from curso)),
  'P0001', null, 'ni a un usuario que no existe');
select lives_ok(
  format($$ select public.sumar_ayudante(%L, '  @AYU20 ') $$, (select id from curso)),
  'el titular suma a Ayu por su usuario (con @ y mayúsculas)');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020f6', 'curso'), 1, 'a Ayu le llega el aviso de que la sumaron');
select is(jsonb_array_length(public.docentes_del_curso((select id from curso))), 2, 'el curso tiene titular y ayudante');
select is((select soy_titular from public.mis_cursos() where id = (select id from curso)), true, 'el titular se ve como titular');

select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select is((select soy_titular from public.mis_cursos() where id = (select id from curso)), false, 'Ayu ve el curso y no es titular');
select is((select count(*)::int from public.files where group_id = (select id from g)), 1, 'Ayu ve los archivos de los grupos del curso');
select is(jsonb_array_length((public.grupos_del_curso((select id from curso)))->0->'integrantes'), 2, 'Ayu ve el tablero del curso');
select is(jsonb_array_length(public.aportes_del_curso((select id from curso))), 2, 'y los aportes de cada alumno');

select throws_ok(
  format($$ select public.sumar_ayudante(%L, 'otro20') $$, (select id from curso)),
  'P0001', null, 'Ayu no suma más docentes');
update public.cursos set nombre = 'Hackeado' where id = (select id from curso);
select is((select nombre from public.cursos where id = (select id from curso)), 'Curso 20', 'Ayu no renombra el curso');
delete from public.cursos where id = (select id from curso);
select is((select count(*)::int from public.cursos where id = (select id from curso)), 1, 'ni lo borra');
select throws_ok(
  format($$ select public.quitar_ayudante(%L, '00000000-0000-0000-0000-0000000020e5') $$, (select id from curso)),
  'P0001', null, 'ni saca al titular');

select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select throws_ok(
  format($$ select public.quitar_ayudante(%L, '00000000-0000-0000-0000-0000000020f6') $$, (select id from curso)),
  'P0001', null, 'una alumna no saca ayudantes');
select is((select count(*)::int from public.curso_docentes where curso_id = (select id from curso)), 0, 'una alumna no ve la tabla de ayudantes');
select is(public.grupos_del_curso((select id from curso)), '[]'::jsonb, 'ni el tablero del curso');
select is(public.docentes_del_curso((select id from curso)), '[]'::jsonb, 'ni los docentes del curso');
select throws_ok(
  format($$ insert into public.curso_docentes (curso_id, user_id) values (%L, auth.uid()) $$, (select id from curso)),
  '42501', null, 'curso_docentes no se escribe directo');

-- Trabajos ------------------------------------------------------------------------------
select throws_ok(
  format($$ select public.crear_trabajo(%L, 'TP falso', null, now() + interval '1 day') $$, (select id from curso)),
  'P0001', null, 'una alumna no crea trabajos');

select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select throws_ok(
  format($$ select public.crear_trabajo(%L, 'TP falso', null, now() + interval '1 day') $$, (select id from curso)),
  'P0001', null, 'un docente de otro curso tampoco');

select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
create temp table tr on commit drop as
  select * from public.crear_trabajo((select id from curso), '  TP 2  ', 'Consigna', now() + interval '7 days', 10);
grant select on tr to authenticated;
select is((select titulo from tr), 'TP 2', 'Ayu crea un trabajo (sin espacios de más)');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020a1', 'entrega'), 1, 'Ana recibe el aviso del trabajo nuevo');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020b2', 'entrega'), 1, 'Beto también');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020c3', 'entrega'), 0, 'Caro (sin grupo en el curso) no');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020d4', 'entrega'), 0, 'Dani (otro curso) no');
select throws_ok(
  format($$ insert into public.trabajos (curso_id, titulo, vence_at) values (%L, 'Directo', now()) $$, (select id from curso)),
  '42501', null, 'trabajos no se escribe directo');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select is((select count(*)::int from public.trabajos where id = (select id from tr)), 1, 'Beto ve el trabajo de su curso');
select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select is((select count(*)::int from public.trabajos where id = (select id from tr)), 0, 'una alumna de afuera no lo ve');
select pg_temp.como('00000000-0000-0000-0000-0000000020d4');
select is((select count(*)::int from public.trabajos where id = (select id from tr)), 0, 'ni un alumno de otro curso');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select is((select count(*)::int from public.trabajos where id = (select id from tr)), 0, 'ni un docente de otro curso');
select is(public.grupos_del_curso((select id from curso)), '[]'::jsonb, 'ni su tablero');

-- Entregar --------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select throws_ok(
  format($$ select public.entregar_trabajo(%L, %L, %L) $$, (select id from tr), (select id from g), (select id from f)),
  '42501', null, 'una alumna de afuera no entrega por el grupo');
select pg_temp.como('00000000-0000-0000-0000-0000000020d4');
select throws_ok(
  format($$ select public.entregar_trabajo(%L, %L, %L) $$, (select id from tr), (select id from g2), (select id from f)),
  'P0001', null, 'un grupo de otro curso no entrega este trabajo');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select lives_ok(
  format($$ select public.entregar_trabajo(%L, %L, %L) $$, (select id from tr), (select id from g), (select id from f)),
  'Beto entrega el archivo del grupo');
select is((select row(estado, version_number)::text from public.entregas where trabajo_id = (select id from tr)),
  row('entregada', 1)::text, 'queda entregada con la versión 1');
select ok(public.version_visible((select id from f), 1), 'la versión entregada se ve');
select throws_ok(
  format($$ insert into public.entregas (trabajo_id, group_id, file_id, version_number) values (%L, %L, %L, 1) $$,
         (select id from tr), (select id from g), (select id from f)),
  '42501', null, 'entregas no se escribe directo');

select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select throws_ok(format($$ select public.delete_file(%L) $$, (select id from f)),
  'P0001', null, 'un archivo entregado no va a la papelera');
select is((select deleted_at is null from public.files where id = (select id from f)), true, 'y sigue vivo');
select is((select count(*)::int from public.entregas where trabajo_id = (select id from tr)), 1, 'Ana ve la entrega de su grupo');

select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020e5', 'entrega'), 1, 'el titular recibe el aviso de la entrega');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020f6', 'entrega'), 1, 'y Ayu también');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020a7', 'entrega'), 0, 'un docente de otro curso no');

select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select is((select count(*)::int from public.entregas where trabajo_id = (select id from tr)), 0, 'una alumna de afuera no ve entregas');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select is((select count(*)::int from public.entregas where trabajo_id = (select id from tr)), 0, 'ni un docente de otro curso');

-- Corregir ----------------------------------------------------------------------------------
create or replace function pg_temp.ent_id() returns uuid language sql security definer as
  $$ select id from public.entregas where trabajo_id = (select id from tr) $$;
grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select throws_ok(
  format($$ select public.corregir_entrega(%L, 'aprobada', 10, null) $$, pg_temp.ent_id()),
  'P0002', null, 'un alumno no corrige');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select throws_ok(
  format($$ select public.corregir_entrega(%L, 'aprobada', 10, null) $$, pg_temp.ent_id()),
  'P0002', null, 'un docente de otro curso no corrige');

select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select throws_ok(
  format($$ select public.corregir_entrega(%L, 'aprobada', 11, null) $$, pg_temp.ent_id()),
  'P0001', null, 'una nota arriba de la máxima se rechaza');
select throws_ok(
  format($$ select public.corregir_entrega(%L, 'aprobada', -1, null) $$, pg_temp.ent_id()),
  'P0001', null, 'y una negativa también');
select throws_ok(
  format($$ select public.corregir_entrega(%L, 'cualquiera', 5, null) $$, pg_temp.ent_id()),
  'P0001', null, 'y un estado inválido');
select lives_ok(
  format($$ select public.corregir_entrega(%L, 'a_rehacer', 4, 'Falta la conclusión') $$, pg_temp.ent_id()),
  'Ayu corrige: a rehacer');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020a1', 'nota'), 1, 'Ana recibe la nota');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020b2', 'nota'), 1, 'Beto también');
select throws_ok(
  format($$ select public.editar_trabajo(%L, 'TP 2', null, now() + interval '7 days', 3) $$, (select id from tr)),
  'P0001', null, 'no se baja la nota máxima por debajo de una nota puesta');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select lives_ok(
  format($$ select public.entregar_trabajo(%L, %L, %L) $$, (select id from tr), (select id from g), (select id from f)),
  'tras "a rehacer" se puede volver a entregar');
select is((select estado from public.entregas where trabajo_id = (select id from tr)), 'entregada', 'y vuelve a quedar entregada');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020e5', 'entrega'), 2, 'el titular recibe el aviso de que volvió a entregar');

select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
select lives_ok(
  format($$ select public.corregir_entrega(%L, 'aprobada', 10, 'Muy bien') $$, pg_temp.ent_id()),
  'el titular aprueba con la nota máxima');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020a1', 'nota'), 2, 'Ana recibe la segunda nota');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select throws_ok(
  format($$ select public.entregar_trabajo(%L, %L, %L) $$, (select id from tr), (select id from g), (select id from f)),
  'P0001', null, 'aprobada, ya no se entrega de nuevo');

-- Material ------------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select throws_ok(
  format($$ select public.reservar_material(%L, 'Apunte.pdf', 10) $$, (select id from curso)),
  'P0001', null, 'un alumno no reserva material');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select throws_ok(
  format($$ select public.reservar_material(%L, 'Apunte.pdf', 10) $$, (select id from curso)),
  'P0001', null, 'un docente de otro curso tampoco');

select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select throws_ok(
  format($$ select public.reservar_material(%L, 'a/b.pdf', 10) $$, (select id from curso)),
  'P0001', null, 'el nombre del material no lleva barras');
create temp table mat on commit drop as select * from public.reservar_material((select id from curso), 'Apunte.pdf', 10);
grant select on mat to authenticated;
select ok(public.upload_reserved((select storage_path from mat)), 'Storage acepta la ruta reservada por Ayu');
select throws_ok(format($$ select public.terminar_material(%L) $$, (select id from mat)),
  'P0001', null, 'no se termina sin el objeto subido');

select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select ok(not public.upload_reserved((select storage_path from mat)), 'pero no la acepta para otra persona');
select is((select count(*)::int from public.material_curso where id = (select id from mat)), 0, 'el material sin terminar no se muestra');

select set_config('role', 'postgres', true);
insert into storage.objects (bucket_id, name, owner, metadata)
values ('archivos', (select storage_path from mat), '00000000-0000-0000-0000-0000000020f6',
        jsonb_build_object('size', 10, 'mimetype', 'application/pdf'));
select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select throws_ok(format($$ select public.terminar_material(%L) $$, (select id from mat)),
  'P0002', null, 'un alumno no termina la subida de otro');
select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select lives_ok(format($$ select public.terminar_material(%L) $$, (select id from mat)), 'Ayu termina la subida');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020b2', 'curso'), 1, 'Beto recibe el aviso de material nuevo');
select is(pg_temp.notifs('00000000-0000-0000-0000-0000000020c3', 'curso'), 0, 'Caro no');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select ok(public.material_legible((select storage_path from mat)), 'un integrante del curso lee el material');
select is((select count(*)::int from storage.objects where bucket_id = 'archivos' and name = (select storage_path from mat)), 1,
  'y Storage se lo muestra');
select is((select count(*)::int from public.material_curso where id = (select id from mat)), 1, 'y lo ve en la lista');
select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select ok(not public.material_legible((select storage_path from mat)), 'una alumna de afuera no lo lee');
select is((select count(*)::int from storage.objects where bucket_id = 'archivos' and name = (select storage_path from mat)), 0,
  'ni Storage se lo muestra');
select pg_temp.como('00000000-0000-0000-0000-0000000020d4');
select ok(not public.material_legible((select storage_path from mat)), 'ni un alumno de otro curso');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select ok(not public.material_legible((select storage_path from mat)), 'ni un docente de otro curso');
select is((select count(*)::int from public.material_curso where id = (select id from mat)), 0, 'que tampoco lo ve en la lista');

select set_config('role', 'postgres', true);
insert into storage.objects (bucket_id, name, owner, metadata)
values ('archivos', 'cursos/00000000-0000-0000-0000-000000000020/suelto', null, '{}');
select ok(not exists (select 1 from public.orphan_storage_objects('-1 minute'::interval, 5000) o where o = (select storage_path from mat)),
  'la limpieza no lista el material');
select ok(exists (select 1 from public.orphan_storage_objects('-1 minute'::interval, 5000) o
                  where o = 'cursos/00000000-0000-0000-0000-000000000020/suelto'),
  'pero sí un objeto huérfano cualquiera');

select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select throws_ok(format($$ select public.borrar_material(%L) $$, (select id from mat)),
  'P0002', null, 'un alumno no borra material');
select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select lives_ok(format($$ select public.borrar_material(%L) $$, (select id from mat)), 'Ayu borra el material');
select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select ok(not public.material_legible((select storage_path from mat)), 'borrado, nadie lo lee');

-- Fechas del curso ------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
select lives_ok(
  format($$ insert into public.fechas_curso (curso_id, titulo, tipo, fecha, creado_por) values (%L, 'Parcial', 'parcial', current_date + 10, auth.uid()) $$,
         (select id from curso)),
  'el docente carga una fecha');
select pg_temp.como('00000000-0000-0000-0000-0000000020a1');
select throws_ok(
  format($$ insert into public.fechas_curso (curso_id, titulo, tipo, fecha, creado_por) values (%L, 'Falsa', 'parcial', current_date, auth.uid()) $$,
         (select id from curso)),
  '42501', null, 'un alumno no carga fechas');
select is((select count(*)::int from public.fechas_curso where curso_id = (select id from curso)), 1, 'el alumno del curso ve la fecha');
delete from public.fechas_curso where curso_id = (select id from curso);
select is((select count(*)::int from public.fechas_curso where curso_id = (select id from curso)), 1, 'y no la borra');
select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select is((select count(*)::int from public.fechas_curso where curso_id = (select id from curso)), 0, 'una alumna de afuera no la ve');
select pg_temp.como('00000000-0000-0000-0000-0000000020a7');
select is((select count(*)::int from public.fechas_curso where curso_id = (select id from curso)), 0, 'ni un docente de otro curso');
select throws_ok(
  format($$ insert into public.fechas_curso (curso_id, titulo, tipo, fecha, creado_por) values (%L, 'Falsa', 'parcial', current_date, auth.uid()) $$,
         (select id from curso)),
  '42501', null, 'y tampoco carga fechas en un curso ajeno');
select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
select lives_ok(
  format($$ insert into public.fechas_curso (curso_id, titulo, fecha, creado_por)
            select %L, 'Clase ' || i, current_date + i, auth.uid() from generate_series(1, 49) i $$, (select id from curso)),
  'se cargan hasta 50 fechas por día');
select throws_ok(
  format($$ insert into public.fechas_curso (curso_id, titulo, fecha, creado_por) values (%L, 'De más', current_date, auth.uid()) $$,
         (select id from curso)),
  'P0001', null, 'la 51 se rechaza');

-- Comentarios con cita ----------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020b2');
select lives_ok(
  format($$ insert into public.comentarios (file_id, group_id, texto, autor, cita) values (%L, %L, 'Revisar esto', auth.uid(), 'un fragmento') $$,
         (select id from f), (select id from g)),
  'un integrante comenta citando un fragmento');
select is((select cita from public.comentarios where file_id = (select id from f)), 'un fragmento', 'la cita queda guardada');
select throws_ok(
  format($$ insert into public.comentarios (file_id, group_id, texto, autor, cita) values (%L, %L, 'x', auth.uid(), %L) $$,
         (select id from f), (select id from g), repeat('a', 501)),
  '23514', null, 'la cita no pasa de 500 caracteres');
select pg_temp.como('00000000-0000-0000-0000-0000000020c3');
select throws_ok(
  format($$ insert into public.comentarios (file_id, group_id, texto, autor, cita) values (%L, %L, 'x', auth.uid(), 'y') $$,
         (select id from f), (select id from g)),
  '42501', null, 'alguien de afuera no comenta');

-- Irse del curso -----------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000020f6');
select lives_ok(
  format($$ select public.quitar_ayudante(%L, auth.uid()) $$, (select id from curso)),
  'Ayu se va del curso');
select is((select count(*)::int from public.mis_cursos() where id = (select id from curso)), 0, 'y ya no lo ve');
select is((select count(*)::int from public.trabajos where id = (select id from tr)), 0, 'ni sus trabajos');
select is((select count(*)::int from public.files where group_id = (select id from g)), 0, 'ni los archivos de los grupos');

-- Ajustes: un docente no suma su propio grupo al curso, y el tope no se saltea borrando.
select pg_temp.como('00000000-0000-0000-0000-0000000020e5');
create temp table gp on commit drop as select * from public.create_group('Grupo del profe 20', null);
select throws_ok(
  format($$ select public.sumar_grupo_a_curso(%L, %L) $$, (select id from gp), (select codigo from public.cursos where id = (select id from curso))),
  'P0001', 'Un docente del curso no puede ser integrante de un grupo del curso', 'un docente del curso no suma un grupo propio al curso');
create or replace function pg_temp.crear_y_borrar(p_n integer)
returns void language plpgsql as $$
declare t public.trabajos;
begin
  for i in 1..p_n loop
    t := public.crear_trabajo((select id from curso), 'Spam ' || i, null, now() + interval '1 day', 10);
    perform public.borrar_trabajo(t.id);
  end loop;
end;
$$;
grant execute on all functions in schema pg_temp to authenticated;
select throws_ok($$ select pg_temp.crear_y_borrar(25) $$, 'P0001', 'Creaste muchos trabajos hoy. Probá mañana',
  'crear y borrar trabajos no saltea el tope de 20 por día');

select is(public.nota_texto(8.50::numeric(5,2)), '8,5', 'la nota 8,5 no se redondea en los avisos');
select is(public.nota_texto(10.00::numeric(5,2)), '10', 'la nota entera va sin decimales');

select * from finish();
rollback;
