begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

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

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000014a1', 'Ana14');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000014b2', 'Beto14');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000014c3', 'Caro14');

-- Grupo con tres materias (una repetida y una vacía, que se ignoran) ---------------
select pg_temp.como('00000000-0000-0000-0000-0000000014a1');
create temp table g on commit drop as
  select * from public.create_group('Segundo año', null, array['Física II', 'Análisis II', 'física ii', '  ', 'Química']);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000014b2');
select public.join_group((select invite_code from g));

create temp table quimica on commit drop as
  select id from public.folders where group_id = (select id from g) and nombre = 'Química';
grant select on quimica to authenticated;

select is(
  (select array_agg(nombre order by color) from public.folders where group_id = (select id from g) and es_materia),
  array['Física II', 'Análisis II', 'Química'], 'crear el grupo arma una carpeta por materia, cada una con su color');

select is(
  (select count(*)::int from public.folders where group_id = (select id from g) and es_materia and parent_id is null),
  3, 'las materias están en la raíz del grupo');

-- Agregar, cambiar color, convertir --------------------------------------------------
select is(
  (select nombre from public.crear_materia((select id from g), '  Inglés ', 4::smallint)),
  'Inglés', 'un integrante agrega una materia');

select throws_ok(
  format($$ select public.crear_materia(%L, 'química') $$, (select id from g)),
  'P0001', 'Ya hay una carpeta o materia con ese nombre', 'no se repite el nombre');

select throws_ok(
  format($$ select public.crear_materia(%L, 'Arte', 9::smallint) $$, (select id from g)),
  'P0001', null, 'el color tiene que ser uno de los 8');

select throws_ok(
  format($$ insert into public.folders (group_id, nombre, created_by, es_materia) values (%L, 'Truco', auth.uid(), true) $$,
         (select id from g)),
  '42501', null, 'el cliente no marca materias a mano');

insert into public.folders (group_id, nombre, created_by)
values ((select id from g), 'Apuntes', auth.uid());
select is(
  (select es_materia from public.editar_materia(
     (select id from public.folders where group_id = (select id from g) and nombre = 'Apuntes'), true)),
  true, 'una carpeta de la raíz se convierte en materia');

select is(
  (select color::int from public.editar_materia(
     (select id from public.folders where group_id = (select id from g) and nombre = 'Química'), true, 6::smallint)),
  6, 'se le cambia el color');

select is(
  (select color from public.editar_materia(
     (select id from public.folders where group_id = (select id from g) and nombre = 'Apuntes'), false)),
  null, 'y vuelve a ser una carpeta común, sin color');

select lives_ok(
  format($$ insert into public.folders (group_id, parent_id, nombre, created_by) values (%L, %L, 'TP 1', auth.uid()) $$,
         (select id from g), (select id from public.folders where group_id = (select id from g) and nombre = 'Química')),
  'un integrante crea una subcarpeta (adentro de una materia)');
select pg_temp.como('00000000-0000-0000-0000-0000000014c3');
create temp table g3 on commit drop as select * from public.create_group('Ajeno', null);
grant select on g3 to authenticated;
select throws_ok(
  format($$ insert into public.folders (group_id, parent_id, nombre, created_by) values (%L, %L, 'Colada', auth.uid()) $$,
         (select id from g3), (select id from quimica)),
  '42501', null, 'no se cuelga una carpeta de la carpeta de otro grupo');
select pg_temp.como('00000000-0000-0000-0000-0000000014b2');
select throws_ok(
  format($$ select public.editar_materia(%L, true) $$,
         (select id from public.folders where group_id = (select id from g) and nombre = 'TP 1')),
  'P0001', null, 'una subcarpeta no puede ser materia');

-- Alguien de afuera no toca nada ----------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000014c3');
select throws_ok(
  format($$ select public.crear_materia(%L, 'Hack') $$, (select id from g)),
  '42501', null, 'alguien de afuera no agrega materias');
select throws_ok(
  format($$ select public.editar_materia(%L, false) $$, (select id from quimica)),
  'P0002', null, 'ni las edita');

-- Tope ------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000014a1');
select public.crear_materia((select id from g), 'Materia ' || i) from generate_series(1, 16) as i;
select is(
  (select count(*)::int from public.folders where group_id = (select id from g) and es_materia), 20,
  'llega a 20 materias');
select throws_ok(
  format($$ select public.crear_materia(%L, 'Una más') $$, (select id from g)),
  'P0001', null, 'y no pasa de 20');

-- Eventos con materia ---------------------------------------------------------------
select lives_ok(
  format($$ insert into public.eventos (group_id, titulo, tipo, fecha, created_by, folder_id)
            values (%L, 'Parcial de Química', 'parcial', current_date + 7, auth.uid(), %L) $$,
         (select id from g), (select id from public.folders where group_id = (select id from g) and nombre = 'Química')),
  'un evento se asocia a una materia del grupo');

select throws_ok(
  format($$ insert into public.eventos (group_id, titulo, fecha, created_by, folder_id)
            values (%L, 'En subcarpeta', current_date, auth.uid(), %L) $$,
         (select id from g), (select id from public.folders where group_id = (select id from g) and nombre = 'TP 1')),
  'P0001', null, 'un evento va con una materia, no con cualquier carpeta');
select throws_ok(
  format($$ select public.create_group('Muchas', null, array_fill('x'::text, array[51])) $$),
  'P0001', 'Son demasiadas materias', 'create_group no acepta listas enormes');
select isnt(
  (select id from public.create_group('Con nulos', null, array[null, 'Física']::text[])), null,
  'una materia nula en la lista se ignora');
select pg_temp.como('00000000-0000-0000-0000-0000000014c3');
create temp table g2 on commit drop as select * from public.create_group('Otro grupo', 'Historia');
grant select on g2 to authenticated;
select throws_ok(
  format($$ insert into public.eventos (group_id, titulo, fecha, created_by, folder_id)
            values (%L, 'Trampa', current_date, auth.uid(), %L) $$,
         (select id from g2), (select id from quimica)),
  'P0001', null, 'no se usa una materia de otro grupo');

select is(
  (select array_agg(nombre) from public.folders where group_id = (select id from g2) and es_materia),
  array['Historia'], 'la materia de siempre (create_group con una sola) sigue funcionando');

select * from finish();
rollback;
