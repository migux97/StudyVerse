begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Sube un archivo completo (begin → objeto → finish) y devuelve la ruta.
create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text)
returns text language plpgsql as $$
declare b record;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, null, p_nombre, 10);
  perform set_config('role', 'postgres', true);
  insert into storage.objects (bucket_id, name, owner, metadata, created_at)
  values ('archivos', b.storage_path, p_user, '{"size": 10}', now() - interval '2 days');
  perform pg_temp.como(p_user);
  perform public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number);
  return b.storage_path;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

insert into auth.users (id, email, raw_user_meta_data, aud, role) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@test.com', '{"nombre":"Ana"}', 'authenticated', 'authenticated');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g1 on commit drop as select * from public.create_group('Se queda', null);
create temp table g2 on commit drop as select * from public.create_group('Se borra', null);
grant select on g1, g2 to authenticated;

select pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g1), 'vivo.pdf');
create temp table r on commit drop as
  select pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g2), 'del-grupo-borrado.pdf') as ruta;

set local role postgres;
-- Subida cortada: el objeto llegó a Storage pero nunca se llamó a finish_upload.
insert into storage.objects (bucket_id, name, owner, metadata, created_at) values
  ('archivos', format('groups/%s/files/%s/v1', (select id from g1), gen_random_uuid()),
   '00000000-0000-0000-0000-00000000000a', '{"size": 10}', now() - interval '3 days'),
  -- Subida en curso (hace un minuto): no se toca.
  ('archivos', format('groups/%s/files/%s/v1', (select id from g1), gen_random_uuid()),
   '00000000-0000-0000-0000-00000000000a', '{"size": 10}', now() - interval '1 minute');

-- Solo los huérfanos de estos grupos: la base local puede tener otros datos.
create or replace function pg_temp.huerfanos(p_edad interval default interval '24 hours')
returns setof text language sql as $$
  select o from public.orphan_storage_objects(p_edad) o
  where o like 'groups/' || (select id from g1) || '/%' or o like 'groups/' || (select id from g2) || '/%'
$$;

select is((select count(*)::int from pg_temp.huerfanos()), 1,
  'antes de borrar el grupo, solo la subida cortada es huérfana');

delete from public.groups where id = (select id from g2);
select is((select count(*)::int from pg_temp.huerfanos()), 2,
  'al borrar un grupo, sus archivos quedan como huérfanos');
select ok((select ruta from r) in (select pg_temp.huerfanos()),
  'incluye el archivo del grupo borrado');
select ok(not exists (select 1 from public.orphan_storage_objects() o
                      join public.file_versions v on v.storage_path = o),
  'nunca incluye objetos que usa alguna versión');
select is((select count(*)::int from pg_temp.huerfanos(interval '0 seconds')), 3,
  'con edad mínima 0 incluye también la subida en curso (solo para pruebas)');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select throws_ok($$ select public.orphan_storage_objects() $$, '42501', null,
  'los usuarios no pueden listar huérfanos');

select * from finish();
rollback;
