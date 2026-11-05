begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

create or replace function pg_temp.crear_usuario(p_id uuid, p_nombre text)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, 't11.' || lower(p_nombre) || '@test.com', jsonb_build_object('nombre', p_nombre), 'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text, p_file uuid default null)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, null, p_nombre, 20, p_file);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user, jsonb_build_object('size', 20, 'mimetype', 'application/json'));
  select * into fv from public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number);
  return fv;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000a4', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000b4', 'Beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000c4', 'Caro');

select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
create temp table g on commit drop as select * from public.create_group('Docs', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000b4');
select public.join_group((select invite_code from g));

create temp table d on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a4', (select id from g), 'Informe.svdoc');
create temp table txt on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a4', (select id from g), 'notas.txt');
grant select on d, txt to authenticated;

-- Autoguardado -------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok(format($$ select public.guardar_documento(%L, '[{"insert":"hola\n"}]') $$, (select file_id from d)),
  'P0001', null, 'sin «Editar» (bloqueo) no se guarda');

select public.lock_file((select file_id from d), 60);
select lives_ok(format($$ select public.guardar_documento(%L, '[{"insert":"hola\n"}]') $$, (select file_id from d)),
  'con el archivo bloqueado se autoguarda');
select lives_ok(format($$ select public.guardar_documento(%L, '[{"insert":"hola mundo\n"}]') $$, (select file_id from d)),
  'y se vuelve a guardar sobre el mismo borrador');
select is((select contenido->0->>'insert' from public.documentos where file_id = (select file_id from d)), E'hola mundo\n',
  'queda lo último que se escribió');
select is((select base_version from public.documentos where file_id = (select file_id from d)), 1,
  'recuerda de qué versión salió el borrador');

select throws_ok(format($$ select public.guardar_documento(%L, '{"no":"es una lista"}') $$, (select file_id from d)),
  'P0001', null, 'el contenido tiene que ser una lista de operaciones');
select public.lock_file((select file_id from txt), 60);
select throws_ok(format($$ select public.guardar_documento(%L, '[]') $$, (select file_id from txt)),
  'P0001', null, 'solo se autoguardan documentos de StudyVerse');
select throws_ok(format($$ insert into public.documentos (file_id, group_id, contenido) values (%L, %L, '[]') $$,
                        (select file_id from d), (select id from g)),
  '42501', null, 'no se escribe directo en la tabla');

-- Quién lo ve ---------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b4');
select is((select count(*)::int from public.documentos where file_id = (select file_id from d)), 1,
  'un compañero ve el borrador en vivo');
select throws_ok(format($$ select public.guardar_documento(%L, '[{"insert":"pisado\n"}]') $$, (select file_id from d)),
  'P0001', null, 'pero no lo puede pisar mientras otro lo edita');
select ok(public.realtime_topic_allowed(format('grupo:%s:documentos', (select id from g))),
  'y puede escuchar el canal de documentos del grupo');

select pg_temp.como('00000000-0000-0000-0000-0000000000c4');
select is((select count(*)::int from public.documentos where file_id = (select file_id from d)), 0,
  'alguien de afuera no lo ve');
select ok(not public.realtime_topic_allowed(format('grupo:%s:documentos', (select id from g))),
  'ni escucha el canal de documentos del grupo');

set local role anon;
select throws_ok($$ select public.guardar_documento(gen_random_uuid(), '[]') $$,
  '42501', null, 'sin sesión no se guarda');
select throws_ok($$ select public.es_documento('x.svdoc') $$, '42501', null, 'es_documento no se llama desde la API');

-- Bloqueo vencido y ex integrante ---------------------------------------------------
set local role postgres;
update public.files set lock_until = now() - interval '1 minute' where id = (select file_id from d);
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok(format($$ select public.guardar_documento(%L, '[{"insert":"tarde"}]') $$, (select file_id from d)),
  'P0001', null, 'con el bloqueo vencido ya no se guarda');

select pg_temp.como('00000000-0000-0000-0000-0000000000b4');
create temp table d2 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000b4', (select id from g), 'De Beto.svdoc');
grant select on d2 to authenticated;
select public.lock_file((select file_id from d2), 60);
select public.leave_group((select id from g));
select throws_ok(format($$ select public.guardar_documento(%L, '[]') $$, (select file_id from d2)),
  'P0002', null, 'quien se fue del grupo no guarda más');

set local role postgres;
update public.files set lock_until = now() + interval '1 hour' where id = (select file_id from d);
select pg_temp.como('00000000-0000-0000-0000-0000000000a4');
select throws_ok(format($$ select public.guardar_documento(%L, %L::jsonb) $$, (select file_id from d),
                        jsonb_build_array(jsonb_build_object('insert', repeat('x', 1100000)))),
  'P0001', null, 'un borrador de más de 1 MB no se guarda');

-- Al terminar --------------------------------------------------------------------------
set local role postgres;
select ok(exists (select 1 from realtime.messages
                  where topic = format('grupo:%s:documentos', (select id from g))
                    and payload->>'documento' = (select file_id from d)::text),
  'cada guardado avisa al canal, con el id del documento');

select pg_temp.subir('00000000-0000-0000-0000-0000000000a4', (select id from g), 'Informe.svdoc', (select file_id from d));
set local role postgres;
select is((select count(*)::int from public.documentos where file_id = (select file_id from d)), 0,
  'al subir la versión nueva el borrador se descarta');

select * from finish();
rollback;
