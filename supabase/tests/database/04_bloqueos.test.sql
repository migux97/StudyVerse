begin;
create extension if not exists pgtap with schema extensions;

select plan(16);

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

grant execute on all functions in schema pg_temp to authenticated;

-- Ana (admin), Beto y Caro (miembros)
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'Beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000c', 'Caro');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g on commit drop as select * from public.create_group('TP', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.join_group((select invite_code from g));
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select public.join_group((select invite_code from g));

create temp table v on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g), 'Informe.docx');
grant select on v to authenticated;

-- Beto bloquea
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select is((select locked_by from public.lock_file((select file_id from v))),
  '00000000-0000-0000-0000-00000000000b'::uuid, 'Beto bloquea el archivo');

select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select is((select locked_by from public.files where id = (select file_id from v)),
  '00000000-0000-0000-0000-00000000000b'::uuid, 'Caro ve quién lo está editando');
select throws_ok(format($$ select public.lock_file(%L) $$, (select file_id from v)),
  'P0001', 'Beto ya está editando este archivo', 'Caro no puede bloquearlo: el error dice quién lo tiene');
select throws_ok(format($$ select public.unlock_file(%L) $$, (select file_id from v)),
  '42501', null, 'Caro no puede desbloquear un bloqueo ajeno');
select throws_ok(format($$ select * from public.begin_upload(%L, null, 'Informe.docx', 10) $$, (select id from g)),
  'P0001', null, 'Caro no puede subir una versión mientras está bloqueado');
select throws_ok(format($$ select public.delete_file(%L) $$, (select file_id from v)),
  '42501', null, 'ni eliminarlo');
select throws_ok(
  $$ update public.files set locked_by = null $$,
  '42501', null, 'no se puede desbloquear con un UPDATE directo');

-- Beto renueva y después sube: se desbloquea solo
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select lives_ok(format($$ select public.lock_file(%L) $$, (select file_id from v)),
  'quien lo bloqueó puede renovarlo');
select pg_temp.subir('00000000-0000-0000-0000-00000000000b', (select id from g), 'Informe.docx');
select is((select locked_by from public.files where id = (select file_id from v)), null,
  'al subir la versión nueva se desbloquea solo');

-- Desbloqueo propio
select public.lock_file((select file_id from v));
select is((select locked_by from public.unlock_file((select file_id from v))), null,
  'Beto lo desbloquea a mano');

-- El admin fuerza el desbloqueo
select public.lock_file((select file_id from v));
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select is((select locked_by from public.unlock_file((select file_id from v))), null,
  'el admin puede forzar el desbloqueo');

-- Vencimiento a las 24 h
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.lock_file((select file_id from v));
set local role postgres;
update public.files set locked_at = now() - interval '25 hours' where id = (select file_id from v);
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select is((select locked_by from public.lock_file((select file_id from v))),
  '00000000-0000-0000-0000-00000000000c'::uuid, 'un bloqueo vencido se puede tomar');

set local role postgres;
update public.files set locked_at = now() - interval '25 hours' where id = (select file_id from v);
select is(public.release_expired_locks(), 1, 'release_expired_locks libera los vencidos');
select is((select locked_by from public.files where id = (select file_id from v)), null,
  'y el archivo queda libre');

select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select throws_ok($$ select public.release_expired_locks() $$, '42501', null,
  'los usuarios no pueden ejecutar la limpieza');

set local role postgres;
select is((select schedule from cron.job where jobname = 'liberar-bloqueos-vencidos'), '*/15 * * * *',
  'pg_cron limpia los bloqueos vencidos cada 15 minutos');

select * from finish();
rollback;
