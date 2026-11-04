begin;
create extension if not exists pgtap with schema extensions;

select plan(25);

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

-- Sube el objeto como lo haría el cliente: con su rol, así se aplican las
-- políticas de Storage.
create or replace function pg_temp.objeto(p_user uuid, p_path text, p_size bigint)
returns void language plpgsql as $$
begin
  perform pg_temp.como(p_user);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('archivos', p_path, p_user, jsonb_build_object('size', p_size, 'mimetype', 'application/pdf'));
end;
$$;

create or replace function pg_temp.subir(p_user uuid, p_group uuid, p_nombre text, p_size bigint)
returns public.file_versions language plpgsql as $$
declare
  b record;
  fv public.file_versions;
begin
  perform pg_temp.como(p_user);
  select * into b from public.begin_upload(p_group, null, p_nombre, p_size);
  perform pg_temp.objeto(p_user, b.storage_path, p_size);
  select * into fv from public.finish_upload(p_group, null, p_nombre, b.file_id, b.version_number);
  return fv;
end;
$$;

grant execute on all functions in schema pg_temp to authenticated;

select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000a1', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-0000000000b1', 'Beto');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
create temp table g on commit drop as select * from public.create_group('Seguridad', null);
create temp table g2 on commit drop as select * from public.create_group('Otro grupo', null);
grant select on g, g2 to authenticated;
insert into public.folders (group_id, nombre, created_by)
values ((select id from g2), 'Ajena', auth.uid());
create temp table ajena on commit drop as select id from public.folders where nombre = 'Ajena';
grant select on ajena to authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select public.join_group((select invite_code from g));

-- Subidas reservadas -----------------------------------------------------------
create temp table v1 on commit drop as
  select * from pg_temp.subir('00000000-0000-0000-0000-0000000000a1', (select id from g), 'Informe.pdf', 100);
grant select on v1 to authenticated;

select throws_ok(
  format($$ select pg_temp.objeto('00000000-0000-0000-0000-0000000000b1', %L, 10) $$,
         public.storage_path_for((select id from g), (select file_id from v1), 2)),
  '42501', null, 'no se puede subir a Storage sin reservar la ruta con begin_upload');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
create temp table ra on commit drop as
  select * from public.begin_upload((select id from g), null, 'Informe.pdf', 10);
grant select on ra to authenticated;
select throws_ok(
  format($$ select pg_temp.objeto('00000000-0000-0000-0000-0000000000b1', %L, 10) $$, (select storage_path from ra)),
  '42501', null, 'nadie ocupa la ruta que reservó otro');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
create temp table rb on commit drop as
  select * from public.begin_upload((select id from g), null, 'Informe.pdf', 10);
grant select on rb to authenticated;
select isnt((select storage_path from rb), (select storage_path from ra),
  'si dos suben a la vez, cada uno recibe su propia ruta');

select lives_ok(
  format($$ select pg_temp.objeto('00000000-0000-0000-0000-0000000000a1', %L, 10) $$, (select storage_path from ra)),
  'con la reserva se puede subir el objeto');
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok(
  format($$ select public.finish_upload(%L, null, 'x', %L, %s) $$,
         (select id from g), (select file_id from ra), (select version_number from ra)),
  'P0001', 'Esta subida no está preparada. Probá de nuevo', 'no se registra la subida reservada por otro');

-- Beto abandona su subida; la de Ana es la v2, sin huecos.
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
create temp table v2 on commit drop as
  select * from public.finish_upload((select id from g), null, 'x', (select file_id from ra), (select version_number from ra));
grant select on v2 to authenticated;
select is((select version_number from v2), 2, 'una reserva abandonada no deja huecos en las versiones');
select is((select storage_path from v2), (select storage_path from ra), 'la versión usa el objeto reservado');

-- Si Beto termina ahora, la suya se basaba en la v1: no pisa la v2 de Ana.
select pg_temp.objeto('00000000-0000-0000-0000-0000000000b1', (select storage_path from rb), 10);
select throws_ok(
  format($$ select public.finish_upload(%L, null, 'x', %L, %s) $$,
         (select id from g), (select file_id from rb), (select version_number from rb)),
  'P0001', 'Alguien subió otra versión al mismo tiempo. Probá de nuevo',
  'una subida que empezó antes de otra versión no la pisa');

-- La carpeta sale de la reserva, no de lo que manda el cliente.
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
create temp table rc on commit drop as
  select * from public.begin_upload((select id from g), null, 'Nuevo.pdf', 10);
grant select on rc to authenticated;
select pg_temp.objeto('00000000-0000-0000-0000-0000000000b1', (select storage_path from rc), 10);
select public.finish_upload((select id from g), (select id from ajena), 'Otro nombre.pdf',
                            (select file_id from rc), (select version_number from rc));
select is((select folder_id from public.files where id = (select file_id from rc)), null,
  'finish_upload no acepta una carpeta distinta de la reservada');
select is((select nombre from public.files where id = (select file_id from rc)), 'Nuevo.pdf',
  'ni un nombre distinto');

-- Cuota con el tamaño real ---------------------------------------------------------
set local role postgres;
update public.groups
set storage_used = (select storage_bytes from public.plan_limits where plan = 'free') - 50
where id = (select id from g);
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
create temp table rq on commit drop as
  select * from public.begin_upload((select id from g), null, 'Grande.pdf', 0);
grant select on rq to authenticated;
select pg_temp.objeto('00000000-0000-0000-0000-0000000000b1', (select storage_path from rq), 1000);
select throws_ok(
  format($$ select public.finish_upload(%L, null, 'x', %L, %s) $$,
         (select id from g), (select file_id from rq), (select version_number from rq)),
  'P0001', null, 'el límite de espacio se controla con el tamaño real, aunque se declare 0');
set local role postgres;
update public.groups set storage_used = 0 where id = (select id from g);

-- Storage solo sirve lo que el plan deja ver -------------------------------------
select pg_temp.subir('00000000-0000-0000-0000-0000000000a1', (select id from g), 'Informe.pdf', 10);
select pg_temp.subir('00000000-0000-0000-0000-0000000000a1', (select id from g), 'Informe.pdf', 10);
-- Informe.pdf tiene v1..v4; el plan free muestra v2..v4.
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from storage.objects where name = (select storage_path from v1)), 0,
  'el objeto de una versión oculta por el plan no se puede leer');
select is((select count(*)::int from storage.objects where name = (select storage_path from v2)), 1,
  'el de una versión visible sí');
-- Ana no tiene la reserva de ese objeto: lo ve por huérfano, no por suyo.
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from storage.objects where name = (select storage_path from rb)), 1,
  'un objeto huérfano se puede leer (para poder borrarlo)');

set local role postgres;
update public.groups set plan = 'premium' where id = (select id from g);
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select is((select count(*)::int from storage.objects where name = (select storage_path from v1)), 1,
  'con premium se lee el historial completo');
set local role postgres;
update public.groups set plan = 'free' where id = (select id from g);

-- Funciones privadas -----------------------------------------------------------------
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select throws_ok($$ select public.nombre_de('00000000-0000-0000-0000-0000000000a1') $$,
  '42501', null, 'nombre_de no se puede llamar desde la API');
select throws_ok(format($$ select public.is_member_of(%L, '00000000-0000-0000-0000-0000000000a1') $$, (select id from g)),
  '42501', null, 'is_member_of tampoco');
set local role anon;
select throws_ok($$ select public.version_visible(gen_random_uuid(), 1) $$,
  '42501', null, 'anon no llama a version_visible');
select throws_ok($$ select public.storage_path_in_use('x') $$,
  '42501', null, 'ni a storage_path_in_use');
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
select lives_ok(
  format($$ insert into public.tasks (group_id, titulo, assigned_to, created_by)
            values (%L, 'Con responsable', '00000000-0000-0000-0000-0000000000a1', auth.uid()) $$, (select id from g)),
  'las tareas siguen validando el responsable');

-- Tareas de un ex integrante ---------------------------------------------------------
select public.leave_group((select id from g));
delete from public.tasks where titulo = 'Con responsable';
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
select is((select count(*)::int from public.tasks where group_id = (select id from g) and titulo = 'Con responsable'), 1,
  'quien se fue del grupo no borra las tareas que había creado');

-- Avatar ---------------------------------------------------------------------------------
select throws_ok($$ update public.profiles set avatar_url = 'https://atacante/pixel.png' where id = auth.uid() $$,
  '42501', null, 'el avatar no se cambia desde la app');
select lives_ok($$ update public.profiles set nombre = 'Ana María' where id = auth.uid() $$,
  'el nombre sí');

-- Códigos de invitación ----------------------------------------------------------------
set local role postgres;
select is((select count(distinct c)::int from (select public.generate_invite_code() as c from generate_series(1, 200)) x), 200,
  'los códigos no se repiten');
select ok((select bool_and(c ~ '^[A-HJKMNP-Z2-9]{10}$') from (select public.generate_invite_code() as c from generate_series(1, 200)) x),
  'todos tienen 10 caracteres del alfabeto sin ambiguos');

select * from finish();
rollback;
