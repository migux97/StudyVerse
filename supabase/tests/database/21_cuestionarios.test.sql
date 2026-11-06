begin;
create extension if not exists pgtap with schema extensions;

select plan(168);

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

create or replace function pg_temp.como_anon()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Cuenta las notificaciones de un tipo sobre un cuestionario.
create or replace function pg_temp.notifs_c(p_user uuid, p_tipo text, p_cuest uuid)
returns integer language sql security definer as $$
  select count(*)::int from public.notificaciones
  where user_id = p_user and tipo = p_tipo and ruta like '%/cuestionarios/' || p_cuest::text
$$;

create or replace function pg_temp.n_resp(p_intento uuid)
returns integer language sql security definer as $$
  select count(*)::int from public.respuestas where intento_id = p_intento
$$;

-- Cuestionario de una pregunta con opciones, armado por Profe21.
create or replace function pg_temp.nuevo(
  p_titulo text, p_abre interval, p_cierra interval, p_dur integer, p_intentos integer, p_res text,
  p_tope integer, p_publicar boolean default true
)
returns uuid language plpgsql as $$
declare
  v uuid;
begin
  perform pg_temp.como('00000000-0000-0000-0000-0000000021e5');
  select id into v from public.guardar_cuestionario(null, (select id from curso), p_titulo, null,
    now() + p_abre, now() + p_cierra, p_dur, p_intentos, p_res, false, p_tope, 10);
  perform public.guardar_preguntas(v,
    '[{"tipo":"opcion","enunciado":"Cual?","opciones":["a","b"],"correctas":[0]}]'::jsonb);
  if p_publicar then
    perform public.publicar_cuestionario(v);
  end if;
  return v;
end;
$$;

-- Responde la pregunta número [p_orden] del cuestionario principal.
create or replace function pg_temp.resp(p_intento uuid, p_sesion uuid, p_orden integer, p_valor jsonb)
returns void language plpgsql as $$
begin
  perform public.responder(p_intento, p_sesion, (select id from pq where orden = p_orden), p_valor);
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

-- Ana21 y Beto21 (grupo del curso 1), Caro21 (alumna sin grupo), Dani21 (grupo del curso 2),
-- Profe21 (titular), Ayu21 (ayudante) y Otro21 (docente de otro curso).
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021a1', 'Ana21');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021b2', 'Beto21');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021c3', 'Caro21');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021d4', 'Dani21');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021e5', 'Profe21', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021f6', 'Ayu21', 'docente');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000021a7', 'Otro21', 'docente');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table curso on commit drop as select * from public.crear_curso('Curso 21');
grant select on curso to authenticated;
select public.sumar_ayudante((select id from curso), 'ayu21');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
create temp table curso2 on commit drop as select * from public.crear_curso('Curso 21 B');
grant select on curso2 to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
create temp table g on commit drop as select * from public.create_group('Grupo 21', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
select public.join_group((select invite_code from g));
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select public.sumar_grupo_a_curso((select id from g), (select codigo from curso));

select pg_temp.como('00000000-0000-0000-0000-0000000021d4');
create temp table g2 on commit drop as select * from public.create_group('Grupo 21 B', null);
grant select on g2 to authenticated;
select public.sumar_grupo_a_curso((select id from g2), (select codigo from curso2));

-- Armar el cuestionario: permisos y validaciones -----------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, 'Parcial', null, now(), now() + interval '1 day', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'una alumna no crea cuestionarios');

select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, 'Parcial', null, now(), now() + interval '1 day', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'un docente de otro curso no crea cuestionarios en este');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, 'Parcial', null, now(), now() - interval '1 hour', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'el cierre tiene que ser después de la apertura');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, 'Parcial', null, now(), now() + interval '1 day', null, 0, 'al_entregar', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'los intentos van de 1 a 20');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, 'Parcial', null, now(), now() + interval '1 day', null, 1, 'nunca', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'cuándo se ve el resultado tiene que ser una opción válida');
select throws_ok(
  format($$ select public.guardar_cuestionario(null, %L, '   ', null, now(), now() + interval '1 day', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from curso)),
  'P0001', null, 'el título no puede estar vacío');

create temp table cq on commit drop as
  select id from public.guardar_cuestionario(null, (select id from curso), 'Parcial 21', null,
    now() - interval '1 hour', now() + interval '1 day', null, 2, 'al_entregar', false, null, 10);
grant select on cq to authenticated, anon;
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 1, 'el titular crea el cuestionario');

select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select lives_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21 (ayu)', 'Con ayudante', now() - interval '1 hour', now() + interval '1 day', null, 2, 'al_entregar', false, null, 10) $$,
         (select id from cq)),
  'el ayudante edita el cuestionario');
select is((select titulo from public.cuestionarios where id = (select id from cq)), 'Parcial 21 (ayu)', 'y el cambio queda');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Hackeado', null, now(), now() + interval '1 day', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from cq)),
  'P0001', null, 'una alumna no edita el cuestionario');

-- Preguntas ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select throws_ok(
  format($$ select public.publicar_cuestionario(%L) $$, (select id from cq)),
  'P0001', null, 'no se publica sin preguntas');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"desarrollo","enunciado":"x"}]') $$, (select id from cq)),
  'P0002', null, 'una alumna no guarda preguntas');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"desarrollo","enunciado":"x"}]') $$, (select id from cq)),
  'P0002', null, 'un docente de otro curso tampoco');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"opcion","enunciado":"x","opciones":["a","b"],"correctas":[]}]') $$, (select id from cq)),
  'P0001', null, 'una opción única sin correcta se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"opcion","enunciado":"x","opciones":["a","b"],"correctas":[0,1]}]') $$, (select id from cq)),
  'P0001', null, 'una opción única con dos correctas se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"varias","enunciado":"x","opciones":["a","b"],"correctas":[]}]') $$, (select id from cq)),
  'P0001', null, 'varias sin ninguna correcta se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"opcion","enunciado":"x","opciones":["a"],"correctas":[0]}]') $$, (select id from cq)),
  'P0001', null, 'una pregunta con una sola opción se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"opcion","enunciado":"x","opciones":["a","b"],"correctas":[5]}]') $$, (select id from cq)),
  'P0001', null, 'una correcta fuera de las opciones se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"corta","enunciado":"x","correctas":[]}]') $$, (select id from cq)),
  'P0001', null, 'una corta sin respuestas aceptadas se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"corta","enunciado":"x"}]') $$, (select id from cq)),
  'P0001', null, 'una corta sin el campo de respuestas aceptadas se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, null) $$, (select id from cq)),
  'P0001', null, 'guardar_preguntas con null no borra las preguntas');
select is(public.normalizar_respuesta('1.000'), public.normalizar_respuesta('1000'), '"1.000" es mil');
select is(public.normalizar_respuesta('Más rápido.'), public.normalizar_respuesta('mas rapido'), 'el punto final no importa');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"adivinanza","enunciado":"x"}]') $$, (select id from cq)),
  'P0001', null, 'un tipo desconocido se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"desarrollo","enunciado":"   "}]') $$, (select id from cq)),
  'P0001', null, 'un enunciado vacío se rechaza');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"desarrollo","enunciado":"x","puntos":0}]') $$, (select id from cq)),
  'P0001', null, 'los puntos tienen que ser mayores a cero');

select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select lives_ok(
  format($$ select * from public.guardar_preguntas(%L, %L::jsonb) $$, (select id from cq),
    '[{"tipo":"opcion","enunciado":"P1","opciones":["a","b","c"],"correctas":[1]},
      {"tipo":"varias","enunciado":"P2","opciones":["a","b","c","d"],"correctas":[0,2]},
      {"tipo":"corta","enunciado":"P3","correctas":["Más rápido"]},
      {"tipo":"corta","enunciado":"P4","correctas":["2.5"]},
      {"tipo":"desarrollo","enunciado":"P5"}]'),
  'el ayudante guarda las preguntas');
select is((select count(*)::int from public.preguntas_con_clave((select id from cq))), 5, 'el ayudante lee las 5 preguntas con clave');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table pq on commit drop as select orden, id from public.preguntas_con_clave((select id from cq));
grant select on pq to authenticated;
select is((select correctas from public.preguntas_con_clave((select id from cq)) where orden = 2), '[0, 2]'::jsonb, 'el docente ve las correctas');

-- Publicar y visibilidad --------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 0, 'la alumna no ve un cuestionario sin publicar');
select throws_ok(
  format($$ select public.publicar_cuestionario(%L) $$, (select id from cq)),
  'P0002', null, 'una alumna no publica');
select throws_ok(
  format($$ select public.empezar_intento(%L) $$, (select id from cq)),
  'P0002', null, 'no se empieza un cuestionario sin publicar');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(
  format($$ select public.publicar_cuestionario(%L) $$, (select id from cq)),
  'P0002', null, 'un docente de otro curso no publica');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select lives_ok(format($$ select public.publicar_cuestionario(%L) $$, (select id from cq)), 'el titular publica');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021a1', 'curso', (select id from cq)), 1, 'Ana recibe el aviso de curso');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021b2', 'curso', (select id from cq)), 1, 'Beto también');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021d4', 'curso', (select id from cq)), 0, 'Dani, de otro curso, no');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021c3', 'curso', (select id from cq)), 0, 'Caro, sin grupo, no');
select lives_ok(format($$ select public.publicar_cuestionario(%L) $$, (select id from cq)), 'publicar de nuevo no falla');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021a1', 'curso', (select id from cq)), 1, 'y no repite el aviso');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 1, 'Ana ve el cuestionario publicado');
select pg_temp.como('00000000-0000-0000-0000-0000000021d4');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 0, 'alguien de otro curso no lo ve');
select pg_temp.como('00000000-0000-0000-0000-0000000021c3');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 0, 'una alumna sin grupo del curso no lo ve');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 0, 'un docente de otro curso no lo ve');
select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select is((select count(*)::int from public.cuestionarios where id = (select id from cq)), 1, 'el ayudante lo ve');

select pg_temp.como_anon();
select throws_ok($$ select count(*) from public.cuestionarios $$, '42501', null, 'anon no lee cuestionarios');
select throws_ok(
  format($$ select public.empezar_intento(%L) $$, (select id from cq)),
  '42501', null, 'anon no empieza intentos');

-- Lo que el alumno no puede leer ----------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select is((select count(*)::int from public.preguntas where cuestionario_id = (select id from cq)), 0, 'Ana no ve las preguntas antes de empezar');
select throws_ok($$ select correctas from public.preguntas $$, '42501', null, 'el alumno no lee preguntas.correctas');
select throws_ok($$ select count(*) from public.intentos $$, '42501', null, 'el alumno no lee intentos directo');
select throws_ok($$ select count(*) from public.respuestas $$, '42501', null, 'ni respuestas');
select throws_ok($$ select count(*) from public.intento_eventos $$, '42501', null, 'ni intento_eventos');
select throws_ok(
  format($$ insert into public.intentos (cuestionario_id, user_id, numero, vence_at) values (%L, auth.uid(), 1, now()) $$, (select id from cq)),
  '42501', null, 'el alumno no inserta intentos directo');
select is((select count(*)::int from public.preguntas_con_clave((select id from cq))), 0, 'preguntas_con_clave no devuelve nada a un alumno');

-- empezar_intento: ventanas y permisos ------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table cf on commit drop as select pg_temp.nuevo('Futuro 21', interval '1 day', interval '2 days', null, 1, 'al_entregar', null) as id;
grant select on cf to authenticated;
create temp table cc on commit drop as select pg_temp.nuevo('Cerrado 21', interval '-2 days', interval '1 day', null, 1, 'al_entregar', null) as id;
grant select on cc to authenticated;
select set_config('role', 'postgres', true);
update public.cuestionarios set cierra_at = now() - interval '1 hour' where id = (select id from cc);

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cf)), 'P0001', 'Todavía no abrió', 'antes de abrir no se empieza');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cc)), 'P0001', 'Ya cerró', 'después de cerrar no se empieza');
select pg_temp.como('00000000-0000-0000-0000-0000000021c3');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cq)), 'P0002', null, 'una alumna sin grupo del curso no empieza');
select pg_temp.como('00000000-0000-0000-0000-0000000021d4');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cq)), 'P0002', null, 'alguien de otro curso no empieza');
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cq)), null, null, 'el docente del curso no rinde');
select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cq)), null, null, 'el ayudante tampoco');

-- Rendir: Ana ---------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
create temp table ia on commit drop as select public.empezar_intento((select id from cq)) as id;
grant select on ia to authenticated;
select is(public.empezar_intento((select id from cq)), (select id from ia), 'con un intento en curso devuelve el mismo');
select is((select count(*)::int from public.preguntas where cuestionario_id = (select id from cq)), 5, 'Ana ve las preguntas después de empezar');
select throws_ok($$ select correctas from public.preguntas $$, '42501', null, 'pero sigue sin leer las correctas');
select is((select count(*)::int from public.preguntas_con_clave((select id from cq))), 0, 'y preguntas_con_clave sigue vacío para ella');

select is(jsonb_array_length(public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000001')->'preguntas'), 5, 'abrir_intento devuelve las 5 preguntas');
select is((public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000001')->'preguntas'->0) ? 'correctas', false, 'sin las correctas');
select is((public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000001')->'intento'->>'salidas')::int, 0, 'la primera sesión no suma salidas');

select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000002', 1, '[1]') $$, (select id from ia)),
  'SV001', null, 'responder con otra sesión falla');
select throws_ok(
  format($$ select public.abrir_intento(%L, null) $$, (select id from ia)),
  'P0001', 'Falta la sesión', 'abrir sin sesión falla');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 1, '[7]') $$, (select id from ia)),
  'P0001', null, 'una opción fuera de rango falla');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 1, '[0, 1]') $$, (select id from ia)),
  'P0001', null, 'dos opciones en una pregunta de opción única fallan');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 2, '"a"') $$, (select id from ia)),
  'P0001', null, 'un texto en una pregunta de varias falla');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 3, '5') $$, (select id from ia)),
  'P0001', null, 'un número en una pregunta corta falla');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 5, '{"a":1}') $$, (select id from ia)),
  'P0001', null, 'un objeto en una de desarrollo falla');
select throws_ok(
  format($$ select public.responder(%L, '00000000-0000-0000-0000-000000000001', gen_random_uuid(), '"x"') $$, (select id from ia)),
  'P0001', null, 'una pregunta que no es del cuestionario falla');
select is(pg_temp.n_resp((select id from ia)), 0, 'nada de eso guardó respuestas');

select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 1, '[1]');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 2, '[2, 0]');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 3, '"  MÁS   Rápido "');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 4, '"2,50"');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 5, '"Mi desarrollo"');
select is(pg_temp.n_resp((select id from ia)), 5, 'se guardaron las 5 respuestas');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 5, null);
select is(pg_temp.n_resp((select id from ia)), 4, 'responder null borra la respuesta');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 5, '"Mi desarrollo"');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 5, '"   "');
select is(pg_temp.n_resp((select id from ia)), 4, 'un texto vacío también borra');
select pg_temp.resp((select id from ia), '00000000-0000-0000-0000-000000000001', 5, '"Mi desarrollo"');
select is(pg_temp.n_resp((select id from ia)), 5, 'se puede volver a responder');
select is((public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000001')->'respuestas') ? (select id::text from pq where orden = 1), true, 'abrir_intento devuelve lo ya respondido');

-- Salidas ------------------------------------------------------------------------------------
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', false, null)->>'salidas')::int, 1, 'avisar que salió suma una salida');
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', false, null)->>'salidas')::int, 1, 'avisar de nuevo mientras está afuera no suma');
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', true, 5)->>'salidas')::int, 1, 'volver no suma otra salida');
select is((public.mis_intentos((select id from cq))->0->>'segundos_afuera')::int, 0, 'los segundos afuera salen del reloj del servidor (casi cero)');
-- Los segundos que manda la app no pueden pasar lo que lleva rindiendo.
select set_config('role', 'postgres', true);
update public.intentos set empezado_at = empezado_at - interval '10 minutes' where id = (select id from ia);
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', true, 30)->>'salidas')::int, 2, 'un volvió sin salió previo cuenta una salida');
select is((public.mis_intentos((select id from cq))->0->>'segundos_afuera')::int, 30, 'y suma los segundos que dice la app');
select public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', false, null);
select public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000001', true, 2000000000);
select cmp_ok((public.mis_intentos((select id from cq))->0->>'segundos_afuera')::int, '<=', 30 + 610,
  'unos segundos enormes se recortan a lo que lleva rindiendo');
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000009', false, null)->>'salidas')::int, 3, 'avisar con una sesión vieja no cambia nada');

select is((public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000002')->'intento'->>'salidas')::int, 4, 'abrir en otra sesión cuenta una salida');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000001', 1, '[0]') $$, (select id from ia)),
  'SV001', null, 'la pestaña anterior ya no puede responder');
select is((public.avisar_salida((select id from ia), '00000000-0000-0000-0000-000000000002', false, null)->>'salidas')::int, 5, 'la sesión nueva avisa que salió');
select is((public.abrir_intento((select id from ia), '00000000-0000-0000-0000-000000000003')->'intento'->>'salidas')::int, 5, 'abrir en otra sesión estando afuera no suma otra vez');
select is((public.mis_intentos((select id from cq))->0->>'afuera')::boolean, false, 'y vuelve a quedar adentro');

-- Entregar y corrección automática ----------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
select throws_ok(format($$ select public.detalle_intento(%L) $$, (select id from ia)), 'P0002', null, 'otro alumno no ve el detalle del intento de Ana');
select throws_ok(format($$ select public.entregar_intento(%L) $$, (select id from ia)), 'P0002', null, 'ni lo entrega');
select throws_ok(format($$ select public.abrir_intento(%L, gen_random_uuid()) $$, (select id from ia)), 'P0002', null, 'ni lo abre');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(format($$ select public.detalle_intento(%L) $$, (select id from ia)), 'P0001', null, 'Ana no ve el detalle mientras no lo entrega');
select lives_ok(format($$ select public.entregar_intento(%L) $$, (select id from ia)), 'Ana entrega el intento');
select is((public.mis_intentos((select id from cq))->0->>'puntaje')::numeric, 4::numeric, 'opción única, varias, y dos cortas normalizadas suman 4');
select is((public.mis_intentos((select id from cq))->0->>'puntaje_max')::numeric, 5::numeric, 'el máximo es 5');
select is((public.mis_intentos((select id from cq))->0->>'pendiente')::boolean, true, 'queda pendiente por la de desarrollo');
select is((public.mis_intentos((select id from cq))->0->>'nota')::numeric, 8::numeric, 'la nota parcial es 8');
select is(public.mis_intentos((select id from cq))->0->>'entrega_auto', null, 'la entrega fue del alumno');
select throws_ok(
  format($$ select pg_temp.resp(%L, '00000000-0000-0000-0000-000000000003', 1, '[0]') $$, (select id from ia)),
  'P0001', null, 'entregado, no se puede responder');

select is(jsonb_array_length(public.detalle_intento((select id from ia))->'preguntas'), 5, 'Ana ve el detalle de su intento');
select is((public.detalle_intento((select id from ia))->'preguntas'->0) ? 'correctas', false, 'con intentos disponibles, todavía no ve las correctas');
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'preguntas') p where p ? 'puntaje'), 0, 'ni el puntaje de cada pregunta');

-- Segundo intento y tope de intentos
create temp table ia2 on commit drop as select public.empezar_intento((select id from cq)) as id;
grant select on ia2 to authenticated;
select isnt((select id from ia2), (select id from ia), 'con intentos disponibles empieza otro');
select is((public.mis_intentos((select id from cq))->1->>'numero')::int, 2, 'es el número 2');
select lives_ok(format($$ select public.entregar_intento(%L) $$, (select id from ia2)), 'lo entrega en blanco');
select is((public.mis_intentos((select id from cq))->1->>'puntaje')::numeric, 0::numeric, 'sin respuestas saca 0');
select is((public.mis_intentos((select id from cq))->1->>'pendiente')::boolean, false, 'y no queda pendiente');
select throws_ok(format($$ select public.empezar_intento(%L) $$, (select id from cq)), 'P0001', 'Ya usaste todos tus intentos', 'no hay un tercer intento');
select is((public.detalle_intento((select id from ia))->'preguntas'->0) ? 'correctas', true, 'sin más intentos, ve las correctas');
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'preguntas') p where p->>'tipo' = 'desarrollo' and p->'puntaje' = 'null'::jsonb), 1, 'la de desarrollo está sin puntaje');

-- No se cambian las preguntas ni las reglas con intentos
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select throws_ok(
  format($$ select * from public.guardar_preguntas(%L, '[{"tipo":"desarrollo","enunciado":"x"}]') $$, (select id from cq)),
  'P0001', null, 'con intentos hechos, las preguntas no se cambian');
select throws_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21', null, now(), now() + interval '1 day', null, 2, 'al_entregar', false, null, 10) $$, (select id from cq)),
  'P0001', null, 'ni la apertura');
select throws_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21', null, %L, now() + interval '1 day', null, 1, 'al_entregar', false, null, 10) $$,
         (select id from cq), (select abre_at from public.cuestionarios where id = (select id from cq))),
  'P0001', null, 'ni bajar los intentos');
select lives_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21 final', null, %L, now() + interval '2 days', null, 2, 'al_cerrar', false, null, 10) $$,
         (select id from cq), (select abre_at from public.cuestionarios where id = (select id from cq))),
  'sí se cambian el nombre, el cierre y cuándo ven el resultado');
select lives_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21 final', null, %L, now() + interval '2 days', null, 2, 'al_entregar', false, null, 10) $$,
         (select id from cq), (select abre_at from public.cuestionarios where id = (select id from cq))),
  'y se puede volver atrás');
select throws_ok(
  format($$ select public.guardar_cuestionario(%L, null, 'Parcial 21 final', null, %L, now() + interval '2 days', null, 3, 'al_entregar', false, null, 10) $$,
         (select id from cq), (select abre_at from public.cuestionarios where id = (select id from cq))),
  'P0001', null, 'no se suman intentos si alguien ya vio las correctas');

-- Detalle y corrección del docente ----------------------------------------------------------------
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'eventos') e where e->>'tipo' = 'empezo'), 1, 'el docente ve el evento de empezar');
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'eventos') e where e->>'tipo' = 'reabrio'), 2, 've las dos reaperturas');
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'eventos') e where e->>'tipo' = 'salio'), 3, 've las salidas avisadas');
select is((select count(*)::int from jsonb_array_elements(public.detalle_intento((select id from ia))->'eventos') e where e->>'tipo' = 'entrego'), 1, 've la entrega');
select is((public.detalle_intento((select id from ia))->>'alumno'), 'Ana21', 'y el nombre del alumno');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(
  format($$ select public.corregir_respuesta(%L, %L, 1, 'bien') $$, (select id from ia), (select id from pq where orden = 5)),
  'P0002', null, 'una alumna no corrige su propia respuesta');

select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(
  format($$ select public.corregir_respuesta(%L, %L, 1, 'bien') $$, (select id from ia), (select id from pq where orden = 5)),
  'P0002', null, 'un docente de otro curso no corrige');
select throws_ok(format($$ select public.detalle_intento(%L) $$, (select id from ia)), 'P0002', null, 'ni ve el detalle');

select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select throws_ok(
  format($$ select public.corregir_respuesta(%L, %L, 99, 'bien') $$, (select id from ia), (select id from pq where orden = 5)),
  'P0001', null, 'el puntaje no puede pasar los puntos de la pregunta');
select throws_ok(
  format($$ select public.corregir_respuesta(%L, %L, -1, 'bien') $$, (select id from ia), (select id from pq where orden = 5)),
  'P0001', null, 'ni ser negativo');
select lives_ok(
  format($$ select public.corregir_respuesta(%L, %L, 0.5, 'Bien') $$, (select id from ia), (select id from pq where orden = 5)),
  'el ayudante corrige la de desarrollo');
select is(pg_temp.notifs_c('00000000-0000-0000-0000-0000000021a1', 'nota', (select id from cq)), 1, 'Ana recibe el aviso de la corrección');

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select is((public.mis_intentos((select id from cq))->0->>'puntaje')::numeric, 4.5::numeric, 'el total se recalcula');
select is((public.mis_intentos((select id from cq))->0->>'pendiente')::boolean, false, 'ya no queda pendiente');
select is((public.mis_intentos((select id from cq))->0->>'nota')::numeric, 9::numeric, 'la nota final es 9');

select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select is(jsonb_array_length(public.resultados_del_cuestionario((select id from cq))), 2, 'resultados: los dos alumnos del curso');
select is((select jsonb_array_length(r->'intentos') from jsonb_array_elements(public.resultados_del_cuestionario((select id from cq))) r where r->>'nombre' = 'Ana21'), 2, 'Ana con sus 2 intentos');
select is((select jsonb_array_length(r->'intentos') from jsonb_array_elements(public.resultados_del_cuestionario((select id from cq))) r where r->>'nombre' = 'Beto21'), 0, 'Beto sin intentos');
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(format($$ select public.resultados_del_cuestionario(%L) $$, (select id from cq)), 'P0002', null, 'una alumna no ve los resultados del curso');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(format($$ select public.resultados_del_cuestionario(%L) $$, (select id from cq)), 'P0002', null, 'un docente de otro curso tampoco');

-- Resultados al cerrar ---------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table cb on commit drop as select pg_temp.nuevo('Al cerrar 21', interval '-1 hour', interval '1 day', null, 1, 'al_cerrar', null) as id;
grant select on cb to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
create temp table ib on commit drop as select public.empezar_intento((select id from cb)) as id;
grant select on ib to authenticated;
select public.abrir_intento((select id from ib), '00000000-0000-0000-0000-0000000000b1');
select public.responder((select id from ib), '00000000-0000-0000-0000-0000000000b1',
  (select id from public.preguntas where cuestionario_id = (select id from cb)), '[0]');
select public.entregar_intento((select id from ib));
select is((public.mis_intentos((select id from cb))->0->>'visible')::boolean, false, 'al_cerrar: antes del cierre no hay nota visible');
select is((public.mis_intentos((select id from cb))->0) ? 'puntaje', false, 'y no se manda el puntaje');
select is((public.mis_intentos((select id from cb))->0) ? 'nota', false, 'ni la nota');
select is((public.detalle_intento((select id from ib))->'preguntas'->0) ? 'correctas', false, 'ni las correctas en el detalle');
select is((public.detalle_intento((select id from ib))->'intento') ? 'puntaje', false, 'ni el puntaje en el detalle');

select set_config('role', 'postgres', true);
update public.cuestionarios set cierra_at = now() - interval '1 minute' where id = (select id from cb);
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
select is((public.mis_intentos((select id from cb))->0->>'nota')::numeric, 10::numeric, 'al_cerrar: después del cierre se ve la nota');
select is((public.detalle_intento((select id from ib))->'preguntas'->0) ? 'correctas', true, 'y las correctas');

-- Tope de salidas -------------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table cs on commit drop as select pg_temp.nuevo('Salidas 21', interval '-1 hour', interval '1 day', null, 1, 'al_entregar', 1) as id;
grant select on cs to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
create temp table is_a on commit drop as select public.empezar_intento((select id from cs)) as id;
grant select on is_a to authenticated;
select public.abrir_intento((select id from is_a), '00000000-0000-0000-0000-0000000000a1');
select is((public.avisar_salida((select id from is_a), '00000000-0000-0000-0000-0000000000a1', false, null)->>'entregado')::boolean, false, 'tope 1: la primera salida no entrega');
select public.avisar_salida((select id from is_a), '00000000-0000-0000-0000-0000000000a1', true, 0);
select is((public.avisar_salida((select id from is_a), '00000000-0000-0000-0000-0000000000a1', false, null)->>'entregado')::boolean, true, 'tope 1: la segunda salida entrega sola');
select is(public.mis_intentos((select id from cs))->0->>'entrega_auto', 'salidas', 'entrega_auto es salidas');
select throws_ok(
  format($$ select public.responder(%L, '00000000-0000-0000-0000-0000000000a1', (select id from public.preguntas where cuestionario_id = %L), '[0]') $$,
         (select id from is_a), (select id from cs)),
  'P0001', null, 'entregado por salidas, no se responde');

select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
create temp table is_b on commit drop as select public.empezar_intento((select id from cs)) as id;
grant select on is_b to authenticated;
select public.abrir_intento((select id from is_b), '00000000-0000-0000-0000-0000000000c1');
select is((public.abrir_intento((select id from is_b), '00000000-0000-0000-0000-0000000000c2')->'intento'->>'salidas')::int, 1, 'reabrir en otra pestaña cuenta una salida');
select is(public.abrir_intento((select id from is_b), '00000000-0000-0000-0000-0000000000c2')->'intento'->>'entrega_auto', null, 'y sigue abierto con el tope');
select is(public.abrir_intento((select id from is_b), '00000000-0000-0000-0000-0000000000c3')->'intento'->>'entrega_auto', 'salidas', 'la segunda reapertura pasa el tope y entrega');

-- Tiempo ---------------------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
create temp table ct on commit drop as select pg_temp.nuevo('Tiempo 21', interval '-1 hour', interval '1 day', 10, 1, 'al_entregar', null) as id;
grant select on ct to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
create temp table it_a on commit drop as select public.empezar_intento((select id from ct)) as id;
grant select on it_a to authenticated;
select public.abrir_intento((select id from it_a), '00000000-0000-0000-0000-0000000000d1');
select public.responder((select id from it_a), '00000000-0000-0000-0000-0000000000d1',
  (select id from public.preguntas where cuestionario_id = (select id from ct)), '[0]');
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
create temp table it_b on commit drop as select public.empezar_intento((select id from ct)) as id;
grant select on it_b to authenticated;
select public.abrir_intento((select id from it_b), '00000000-0000-0000-0000-0000000000d2');

select set_config('role', 'postgres', true);
select ok((select vence_at from public.intentos where id = (select id from it_a)) <= now() + interval '11 minutes', 'el intento vence a los 10 minutos');
update public.intentos set vence_at = clock_timestamp() - interval '1 minute' where id = (select id from it_a);
select public.cerrar_intentos_vencidos((select id from ct));
select is((select entrega_auto from public.intentos where id = (select id from it_a)), 'tiempo', 'cerrar_intentos_vencidos entrega por tiempo');
select is((select puntaje from public.intentos where id = (select id from it_a)), 1::numeric, 'y corrige lo que alcanzó a responder');
select is((select entregado_at from public.intentos where id = (select id from it_b)), null, 'el que todavía tiene tiempo sigue abierto');

update public.intentos set vence_at = clock_timestamp() - interval '1 minute' where id = (select id from it_b);
select pg_temp.como('00000000-0000-0000-0000-0000000021b2');
select is(public.mis_intentos((select id from ct))->0->>'entrega_auto', 'tiempo', 'mis_intentos entrega por tiempo al consultar');
select throws_ok(
  format($$ select public.responder(%L, '00000000-0000-0000-0000-0000000000d2', (select id from public.preguntas where cuestionario_id = %L), '[0]') $$,
         (select id from it_b), (select id from ct)),
  'P0001', null, 'vencido, responder falla');

-- Borrar -----------------------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000021a1');
select throws_ok(format($$ select public.borrar_cuestionario(%L) $$, (select id from cf)), 'P0002', null, 'una alumna no borra cuestionarios');
select pg_temp.como('00000000-0000-0000-0000-0000000021a7');
select throws_ok(format($$ select public.borrar_cuestionario(%L) $$, (select id from cf)), 'P0002', null, 'un docente de otro curso tampoco');
select pg_temp.como('00000000-0000-0000-0000-0000000021f6');
select lives_ok(format($$ select public.borrar_cuestionario(%L) $$, (select id from cf)), 'el ayudante borra un cuestionario');
select pg_temp.como('00000000-0000-0000-0000-0000000021e5');
select lives_ok(format($$ select public.borrar_cuestionario(%L) $$, (select id from cq)), 'el titular borra uno con intentos');
select is((select count(*)::int from public.cuestionarios where id in (select id from cq union select id from cf)), 0, 'ya no están');
select set_config('role', 'postgres', true);
select is((select count(*)::int from public.intentos where id in (select id from ia union select id from ia2)), 0, 'los intentos se borran en cascada');

select * from finish();
rollback;
