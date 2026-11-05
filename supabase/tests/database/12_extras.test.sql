begin;
create extension if not exists pgtap with schema extensions;

select plan(35);

create or replace function pg_temp.crear_usuario(p_id uuid, p_nombre text, p_usuario text)
returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values (p_id, 't12.' || lower(p_nombre) || '@test.com',
          jsonb_build_object('nombre', p_nombre, 'username', p_usuario), 'authenticated', 'authenticated');
$$;

create or replace function pg_temp.como(p_id uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text, p_folder uuid default null)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, p_folder, p_nombre, 10);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user, jsonb_build_object('size', 10, 'mimetype', 'text/plain'));
  select * into fv from public.finish_upload(p_group, p_folder, p_nombre, b.file_id, b.version_number);
  return fv;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000a5', 'Ana', 't12.ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000b5', 'Beto', 't12.beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000c5', 'Caro', 't12.caro');

select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
create temp table g on commit drop as select * from public.create_group('Extras', null);
create temp table g2 on commit drop as select * from public.create_group('Otro', null);
grant select on g, g2 to authenticated;
insert into public.folders (group_id, nombre, created_by) values ((select id from g), 'Parciales', auth.uid());
create temp table c on commit drop as select id from public.folders where group_id = (select id from g);
grant select on c to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000b5');
select public.join_group((select invite_code from g));

create temp table f on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a5', (select id from g), 'Trabajo Práctico.docx', (select id from c));
create temp table f2 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a5', (select id from g2), 'Práctico secreto.docx');
grant select on f, f2 to authenticated;

-- Papelera -------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select public.delete_file((select file_id from f));
select ok((select deleted_at is not null from public.files where id = (select file_id from f)),
  'eliminar lo manda a la papelera');
select is((select count(*)::int from public.file_versions where file_id = (select file_id from f)), 1,
  'en la papelera conserva sus versiones');
select throws_ok(format($$ select public.rename_file(%L, 'Otro.docx') $$, (select file_id from f)),
  'P0001', null, 'lo que está en la papelera no se renombra');
select throws_ok(format($$ select public.lock_file(%L, 60) $$, (select file_id from f)),
  'P0001', null, 'ni se bloquea');

create temp table f3 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a5', (select id from g), 'Trabajo Práctico.docx', (select id from c));
grant select on f3 to authenticated;
select isnt((select file_id from f3), (select file_id from f),
  'subir uno con el mismo nombre crea un archivo nuevo (no versiona el de la papelera)');

select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select is((public.restaurar_archivo((select file_id from f))).nombre, 'Trabajo Práctico (2).docx',
  'al restaurar, si el nombre está ocupado queda con (2)');
select ok((select deleted_at is null from public.files where id = (select file_id from f)), 'y sale de la papelera');

select public.delete_file((select file_id from f));
select pg_temp.como('00000000-0000-0000-0000-0000000000b5');
select throws_ok(format($$ select public.eliminar_definitivo(%L) $$, (select file_id from f)),
  '42501', null, 'un integrante que no lo subió ni lo eliminó no lo borra para siempre');
select lives_ok(format($$ select public.restaurar_archivo(%L) $$, (select file_id from f)),
  'pero cualquier integrante puede restaurarlo');

select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select public.delete_file((select file_id from f));
select public.delete_file((select file_id from f3));
select lives_ok(format($$ select public.delete_folder(%L) $$, (select id from c)),
  'una carpeta con cosas solo en la papelera se puede borrar');
select is((select folder_id from public.files where id = (select file_id from f)), null,
  'lo de la papelera pasa a la raíz');
select public.eliminar_definitivo((select file_id from f3));
select is((select count(*)::int from public.files where id = (select file_id from f3)), 0,
  'quien lo subió lo borra para siempre');
select is((select count(*)::int from storage.objects where name = (select storage_path from f3)), 0,
  'después de eliminarlo para siempre, sus objetos no se pueden leer');
set local role postgres;
select ok(exists (select 1 from cron.job where jobname = 'vaciar-papelera'), 'la papelera se vacía sola');
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select public.restaurar_archivo((select file_id from f));

-- Destacados y recientes ------------------------------------------------------------
select lives_ok(format($$ insert into public.destacados (user_id, file_id) values (auth.uid(), %L) $$, (select file_id from f)),
  'se marca un archivo de mis grupos como destacado');
select pg_temp.como('00000000-0000-0000-0000-0000000000b5');
select throws_ok(format($$ insert into public.destacados (user_id, file_id) values (auth.uid(), %L) $$, (select file_id from f2)),
  '42501', null, 'no se puede destacar un archivo de un grupo ajeno');
select is((select count(*)::int from public.destacados), 0, 'cada uno ve solo sus destacados');

select public.marcar_visto((select file_id from f));
select is((select count(*)::int from public.vistos where user_id = auth.uid()), 1, 'abrir un archivo lo deja en recientes');
select throws_ok(format($$ select public.marcar_visto(%L) $$, (select file_id from f2)),
  'P0002', null, 'no se marca como visto uno de un grupo ajeno');
select throws_ok(format($$ insert into public.vistos (user_id, file_id) values (auth.uid(), %L) $$, (select file_id from f)),
  '42501', null, 'recientes no se escribe directo');

-- Búsqueda ----------------------------------------------------------------------------
select ok((select bool_and(nombre like 'Trabajo Práctico%') and count(*) = 1 from public.buscar_archivos('PRACTICO')),
  'busca sin importar tildes ni mayúsculas');
select is((select count(*)::int from public.buscar_archivos('secreto')), 0, 'no encuentra archivos de grupos ajenos');
select is((select count(*)::int from public.buscar_archivos('t')), 0, 'con menos de 2 letras no busca');

-- Calendario ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select lives_ok(format($$ insert into public.eventos (group_id, titulo, tipo, fecha, created_by)
                          values (%L, 'Primer parcial', 'parcial', current_date + 3, auth.uid()) $$, (select id from g)),
  'un integrante agrega un parcial al calendario');
select pg_temp.como('00000000-0000-0000-0000-0000000000c5');
select is((select count(*)::int from public.eventos where group_id = (select id from g)), 0,
  'alguien de afuera no ve los eventos del grupo');
select throws_ok(format($$ insert into public.eventos (group_id, titulo, fecha, created_by) values (%L, 'x', current_date, auth.uid()) $$,
                        (select id from g)),
  '42501', null, 'ni los crea');
select pg_temp.como('00000000-0000-0000-0000-0000000000b5');
update public.eventos set fecha = fecha + 30 where titulo = 'Primer parcial' and group_id = (select id from g);
delete from public.eventos where titulo = 'Primer parcial' and group_id = (select id from g);
set local role postgres;
select is((select count(*)::int from public.eventos where titulo = 'Primer parcial' and group_id = (select id from g)), 1,
  'un integrante que no lo creó ni es admin no lo borra');
select is((select fecha from public.eventos where titulo = 'Primer parcial' and group_id = (select id from g)), current_date + 3,
  'ni le cambia la fecha');
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
select throws_ok(format($$ insert into public.comentarios (file_id, group_id, texto, autor, created_at)
                          values (%L, %L, 'viejo', auth.uid(), now() - interval '7 days') $$,
                        (select file_id from f), (select id from g)),
  '42501', null, 'no se puede elegir la fecha de un comentario');
set local role postgres;

-- Comentarios y menciones ---------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000a5');
insert into public.comentarios (file_id, group_id, texto, autor)
values ((select file_id from f), (select id from g), 'Revisen la intro @t12.beto y @t12.caro', auth.uid());
select is((select menciones from public.comentarios where file_id = (select file_id from f)),
  array['00000000-0000-0000-0000-0000000000b5'::uuid],
  'las menciones guardan solo a integrantes del grupo (Caro no es)');
set local role postgres;
select ok(exists (select 1 from realtime.messages
                  where topic = 'usuario:00000000-0000-0000-0000-0000000000b5:menciones' and event = 'mencion'),
  'al mencionado le llega un aviso en su canal');
select ok(exists (select 1 from public.activity where group_id = (select id from g) and tipo = 'comentario'
                  and not payload ? 'texto'),
  'el comentario queda en la actividad, sin copiar el texto');

select pg_temp.como('00000000-0000-0000-0000-0000000000c5');
select is((select count(*)::int from public.comentarios where file_id = (select file_id from f)), 0,
  'alguien de afuera no ve los comentarios');
select ok(not public.realtime_topic_allowed(format('grupo:%s:comentarios', (select id from g))),
  'ni escucha su canal');
select pg_temp.como('00000000-0000-0000-0000-0000000000b5');
delete from public.comentarios where file_id = (select file_id from f);
select is((select count(*)::int from public.comentarios where file_id = (select file_id from f)), 1,
  'no se borra el comentario de otro');

select * from finish();
rollback;
