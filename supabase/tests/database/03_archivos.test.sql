begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

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

-- Simula al cliente: begin_upload → objeto en Storage → finish_upload.
-- El objeto se inserta como lo haría Storage (con el rol del servicio).
create or replace function pg_temp.subir(
  p_user uuid, p_group uuid, p_folder uuid, p_nombre text, p_size bigint,
  p_file uuid default null, p_nota text default null)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, p_folder, p_nombre, p_size, p_file);
  perform set_config('role', 'postgres', true);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', b.storage_path, p_user,
          jsonb_build_object('size', p_size, 'mimetype', 'application/pdf'));
  perform pg_temp.como(p_user);
  select * into fv from public.finish_upload(p_group, p_folder, p_nombre, b.file_id, b.version_number, p_nota);
  return fv;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'Beto');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000c', 'Caro');

-- Grupo de Ana con Beto; Caro queda afuera.
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g on commit drop as select * from public.create_group('TP', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.join_group((select invite_code from g));

-- Carpetas ------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
insert into public.folders (group_id, nombre, created_by)
values ((select id from g), 'Informe', auth.uid());
create temp table c on commit drop as select * from public.folders where nombre = 'Informe';
grant select on c to authenticated;

select pass('un integrante crea una carpeta');
select throws_ok(
  format($$ insert into public.folders (group_id, nombre, created_by) values (%L, 'informe', auth.uid()) $$, (select id from g)),
  '23505', null, 'no puede haber dos carpetas con el mismo nombre (sin importar mayúsculas)');

select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.folders), 0, 'un no-miembro no ve carpetas');
select throws_ok(
  format($$ insert into public.folders (group_id, nombre, created_by) values (%L, 'Hack', auth.uid()) $$, (select id from g)),
  '42501', null, 'un no-miembro no crea carpetas');
select throws_ok(
  format($$ select * from public.begin_upload(%L, null, 'x.pdf', 10) $$, (select id from g)),
  '42501', null, 'un no-miembro no puede subir');

-- Subidas y versiones ---------------------------------------------------------
create temp table v1 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g), (select id from c), 'Informe.docx', 1000);
grant select on v1 to authenticated;

select is((select version_number from v1), 1, 'la primera subida es la v1');
select matches((select storage_path from v1), '^groups/[0-9a-f-]{36}/files/[0-9a-f-]{36}/v1$',
  'la ruta en Storage sigue groups/{grupo}/files/{archivo}/v{n}');
select is((select storage_used from public.groups where id = (select id from g)), 1000::bigint,
  'storage_used suma el tamaño real de Storage');

create temp table v2 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-00000000000b', (select id from g), (select id from c), 'informe.DOCX', 2000, null, 'corregí la conclusión');
grant select on v2 to authenticated;

select is((select file_id from v2), (select file_id from v1), 'el mismo nombre crea una versión nueva, no un duplicado');
select is((select version_number from v2), 2, 'es la v2');
select is((select nota from v2), 'corregí la conclusión', 'guarda la nota');
select is((select current_version_id from public.files where id = (select file_id from v1)), (select id from v2),
  'la versión actual pasa a ser la v2');
select is((select count(*)::int from public.files), 1, 'sigue habiendo un solo archivo');

select throws_ok(
  format($$ select public.finish_upload(%L, null, 'falso.pdf', gen_random_uuid(), 1) $$, (select id from g)),
  'P0001', 'Esta subida no está preparada. Probá de nuevo', 'no se registra una versión sin reservarla con begin_upload');

select throws_ok(
  format($$ insert into public.file_versions (file_id, group_id, version_number, storage_path, size_bytes) values (%L, %L, 9, 'x', 1) $$,
         (select file_id from v1), (select id from g)),
  '42501', null, 'no se insertan versiones directo, solo con finish_upload');

-- Bloqueos (la UI llega en la fase 4) ----------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
set local role postgres;
update public.files set locked_by = '00000000-0000-0000-0000-00000000000a', locked_at = now()
where id = (select file_id from v1);
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select throws_ok(
  format($$ select * from public.begin_upload(%L, %L, 'Informe.docx', 10) $$, (select id from g), (select id from c)),
  'P0001', 'Otra persona está editando este archivo', 'si otro lo bloqueó, no se puede subir');
select throws_ok(format($$ select public.rename_file(%L, 'Otro.docx') $$, (select file_id from v1)),
  'P0001', null, 'si otro lo bloqueó, no se puede renombrar');

set local role postgres;
update public.files set locked_at = now() - interval '25 hours' where id = (select file_id from v1);
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select lives_ok(
  format($$ select * from public.begin_upload(%L, %L, 'Informe.docx', 10) $$, (select id from g), (select id from c)),
  'un bloqueo de más de 24 h ya no impide subir');

create temp table v3 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g), (select id from c), 'Informe.docx', 3000);
select is((select locked_by from public.files where id = (select file_id from v1)), null,
  'subir una versión nueva libera el bloqueo');

-- Plan free: últimas 3 versiones visibles --------------------------------------
select pg_temp.subir('00000000-0000-0000-0000-00000000000a', (select id from g), (select id from c), 'Informe.docx', 4000);
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select is(
  (select array_agg(version_number order by version_number) from public.file_versions),
  array[2, 3, 4], 'en el plan free se ven solo las últimas 3 versiones');
select throws_ok(format($$ select public.restore_version(%L) $$, (select id from v1)),
  'P0002', null, 'no se puede restaurar una versión que no se ve');

-- Restaurar --------------------------------------------------------------------
create temp table r on commit drop as select * from public.restore_version((select id from v2));
select is((select version_number from r), 5, 'restaurar crea una versión nueva (v5)');
select is((select storage_path from r), (select storage_path from v2), 'reutiliza el objeto de Storage');
select is((select nota from r), 'Restaurada desde la v2', 'con una nota automática');
select is((select storage_used from public.groups where id = (select id from g)), 10000::bigint,
  'restaurar no suma espacio (1000+2000+3000+4000)');

-- Cuota --------------------------------------------------------------------------
select throws_ok(
  format($$ select * from public.begin_upload(%L, null, 'enorme.zip', 600 * 1024 * 1024) $$, (select id from g)),
  'P0001', null, 'no se puede pasar del límite del plan free (500 MB)');

-- Storage ------------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from storage.objects where bucket_id = 'archivos'), 0,
  'un no-miembro no ve los objetos de Storage del grupo');

-- Eliminar -----------------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select throws_ok(format($$ select public.delete_file(%L) $$, (select file_id from v1)),
  '42501', null, 'un miembro no elimina un archivo que no subió');
select throws_ok(format($$ select public.delete_folder(%L) $$, (select id from c)),
  'P0001', 'La carpeta no está vacía', 'no se elimina una carpeta con contenido');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select is((select count(*)::int from public.delete_file((select file_id from v1))), 4,
  'eliminar devuelve los 4 objetos distintos para borrar de Storage');
select is((select storage_used from public.groups where id = (select id from g)), 0::bigint,
  'storage_used vuelve a 0 (cada objeto se descuenta una vez)');

select * from finish();
rollback;
