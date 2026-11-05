begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

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
  select * into b from public.begin_upload(p_group, null, p_nombre, 10);
  perform set_config('role', 'postgres', true);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user, jsonb_build_object('size', 10, 'mimetype', 'text/plain'));
  perform pg_temp.como(p_user);
  select * into fv from public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number, null);
  return fv;
end;
$$;

-- Número de versión → id (como postgres, para ver también las ocultas).
create or replace function pg_temp.vid(p_nombre text, p_n integer)
returns uuid language plpgsql security definer as $$
begin
  return (select v.id from public.file_versions v join public.files f on f.id = v.file_id
          where f.nombre = p_nombre and v.version_number = p_n
            and f.group_id = (select id from g));
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000013a1', 'Ana13');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000013b2', 'Beto13');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000013c3', 'Caro13');

-- Grupo gratis de Ana (admin) con Beto: se ven las últimas 3 versiones.
select pg_temp.como('00000000-0000-0000-0000-0000000013a1');
create temp table g on commit drop as select * from public.create_group('TP versiones', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000013b2');
select public.join_group((select invite_code from g));

select pg_temp.subir('00000000-0000-0000-0000-0000000013a1', (select id from g), 'Informe.txt')
from generate_series(1, 5);

-- Guardar ---------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000013a1');
select is(
  (select guardada_nombre from public.guardar_version(pg_temp.vid('Informe.txt', 5), '  Entrega 1 ')),
  'Entrega 1', 'un integrante guarda una versión con nombre');

select throws_ok(
  format($$ select public.guardar_version(%L, 'Vieja') $$, pg_temp.vid('Informe.txt', 1)),
  'P0002', null, 'no se puede guardar una versión que el plan oculta');

select throws_ok(
  format($$ select public.guardar_version(%L, %L) $$, pg_temp.vid('Informe.txt', 4), repeat('x', 61)),
  'P0001', null, 'el nombre tiene hasta 60 caracteres');

select throws_ok(
  format($$ update public.file_versions set guardada_nombre = 'x' where id = %L $$, pg_temp.vid('Informe.txt', 4)),
  '42501', null, 'el cliente no la marca a mano');

select pg_temp.como('00000000-0000-0000-0000-0000000013c3');
select throws_ok(
  format($$ select public.guardar_version(%L, 'Hack') $$, pg_temp.vid('Informe.txt', 5)),
  'P0002', null, 'alguien de afuera no puede guardar');

-- Con versiones nuevas, la guardada se sigue viendo ------------------------------
select pg_temp.subir('00000000-0000-0000-0000-0000000013a1', (select id from g), 'Informe.txt')
from generate_series(1, 3);

select pg_temp.como('00000000-0000-0000-0000-0000000013b2');
select is(
  (select array_agg(v.version_number order by v.version_number)
   from public.file_versions v join public.files f on f.id = v.file_id
   where f.group_id = (select id from g)),
  array[5, 6, 7, 8], 'la guardada (v5) se ve aunque ya no esté entre las últimas 3');

select throws_ok(
  format($$ select public.guardar_version(%L, 'Entrega final') $$, pg_temp.vid('Informe.txt', 5)),
  '42501', null, 'otro integrante no le cambia el nombre');

select pg_temp.como('00000000-0000-0000-0000-0000000013a1');
select is(
  (select guardada_nombre from public.guardar_version(pg_temp.vid('Informe.txt', 5), 'Entrega final')),
  'Entrega final', 'quien la guardó le cambia el nombre');
select pg_temp.como('00000000-0000-0000-0000-0000000013b2');

select throws_ok(
  format($$ select public.guardar_version(%L, null) $$, pg_temp.vid('Informe.txt', 5)),
  '42501', null, 'quitarla: solo quien la guardó o un admin');

select pg_temp.como('00000000-0000-0000-0000-0000000013a1');
select is(
  (select guardada_nombre from public.guardar_version(pg_temp.vid('Informe.txt', 5), '')),
  null, 'quien la guardó la quita');

select is(
  (select count(*)::int from public.file_versions where id = pg_temp.vid('Informe.txt', 5)),
  0, 'al quitarla, el plan la vuelve a ocultar');

-- Tope de 10 por archivo -----------------------------------------------------------
create or replace function pg_temp.subir_y_guardar(p_i integer)
returns void language plpgsql as $$
declare
  fv public.file_versions;
begin
  fv := pg_temp.subir('00000000-0000-0000-0000-0000000013a1', (select id from g), 'Tope.txt');
  perform public.guardar_version(fv.id, 'Guardada ' || p_i);
end;
$$;
grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.subir_y_guardar(i) from generate_series(1, 10) as i;
select throws_ok(
  $$ select pg_temp.subir_y_guardar(11) $$,
  'P0001', null, 'no se guardan más de 10 versiones de un archivo');
select pg_temp.como('00000000-0000-0000-0000-0000000013a1');
select is(
  (select count(*)::int from public.file_versions v join public.files f on f.id = v.file_id
   where f.nombre = 'Tope.txt' and f.group_id = (select id from g) and v.guardada_nombre is not null),
  10, 'quedan las 10');

-- En la papelera no se toca --------------------------------------------------------
select public.delete_file((select id from public.files where nombre = 'Informe.txt' and group_id = (select id from g)));
select throws_ok(
  format($$ select public.guardar_version(%L, 'Tarde') $$, pg_temp.vid('Informe.txt', 8)),
  'P0001', null, 'un archivo en la papelera no se guarda');

select * from finish();
rollback;
