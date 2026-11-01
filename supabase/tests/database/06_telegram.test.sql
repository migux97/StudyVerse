begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

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

select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000a', 'Ana');
select pg_temp.crear_usuario('00000000-0000-0000-0000-00000000000b', 'Juan');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table g on commit drop as select * from public.create_group('TP', null);
grant select on g to authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select public.join_group((select invite_code from g));

-- Código de vinculación ---------------------------------------------------------
select throws_ok(format($$ select * from public.create_telegram_link_code(%L) $$, (select id from g)),
  '42501', null, 'un miembro no puede generar el código');

select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table c on commit drop as select * from public.create_telegram_link_code((select id from g));
grant select on c to authenticated;
select matches((select code from c), '^[A-HJKMNP-Z2-9]{8}$', 'el admin genera un código de 8 caracteres');
select ok((select expires_at between now() + interval '29 minutes' and now() + interval '31 minutes' from c),
  'vence en 30 minutos');
select is((select count(*)::int from public.telegram_link_codes), 0, 'los clientes no pueden leer los códigos');
select throws_ok(format($$ select public.redeem_telegram_link_code(%L, 1, 'x') $$, (select code from c)),
  '42501', null, 'los clientes no pueden canjear códigos (solo el bot)');

-- El bot canjea (service_role)
set local role postgres;
select is((select nombre from public.redeem_telegram_link_code(lower((select code from c)), -1001, 'Grupo TP')),
  'TP', '"/vincular codigo" (sin importar mayúsculas) vincula el chat al grupo');
select throws_ok(format($$ select public.redeem_telegram_link_code(%L, -1002, 'Otro') $$, (select code from c)),
  'P0002', 'Código inválido o vencido', 'el código es de un solo uso');
select is((select tipo from public.activity order by created_at desc limit 1), 'telegram_vinculado',
  'vincular queda en la actividad');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select is((select chat_title from public.telegram_links), 'Grupo TP', 'los miembros ven el chat vinculado');
delete from public.telegram_links;
set local role postgres;
select is((select count(*)::int from public.telegram_links), 1, 'un miembro no puede desvincular');

-- Código vencido
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
create temp table c2 on commit drop as select * from public.create_telegram_link_code((select id from g));
set local role postgres;
update public.telegram_link_codes set expires_at = now() - interval '1 minute';
select throws_ok(format($$ select public.redeem_telegram_link_code(%L, -1003, 'x') $$, (select code from c2)),
  'P0002', null, 'un código vencido no sirve');

-- Cola de avisos -------------------------------------------------------------------
delete from public.telegram_outbox;
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
insert into public.tasks (group_id, titulo, assigned_to, created_by)
values ((select id from g), 'Conclusión', '00000000-0000-0000-0000-00000000000b', auth.uid());
set local role postgres;
select is((select count(*)::int from public.telegram_outbox), 0, 'crear una tarea no se avisa por Telegram');

select pg_temp.como('00000000-0000-0000-0000-00000000000b');
update public.tasks set estado = 'hecha';
set local role postgres;
select is((select count(*)::int from public.telegram_outbox where kind = 'actividad'), 1,
  'completar una tarea se encola para el chat vinculado');

create temp table claim on commit drop as select * from public.claim_telegram_outbox();
select is((select tipo || ' por ' || actor || ' en ' || grupo from claim), 'tarea_completada por Juan en TP',
  'la función del bot recibe todo lo necesario para el mensaje');
select is((select count(*)::int from public.claim_telegram_outbox()), 0,
  'lo que ya tomó un envío no lo toma otro (hasta que venza el lock)');

-- Recordatorios ----------------------------------------------------------------------
delete from public.telegram_outbox;
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
insert into public.tasks (group_id, titulo, due_date, created_by) values
  ((select id from g), 'Vence mañana', date '2026-11-02', auth.uid()),
  ((select id from g), 'Vence pasado', date '2026-11-03', auth.uid());
set local role postgres;

select is(public.enqueue_due_reminders(timestamptz '2026-11-01 09:30-03'), 0, 'antes de las 10 no avisa');
select is(public.enqueue_due_reminders(timestamptz '2026-11-01 10:15-03'), 1, 'a las 10 avisa solo las que vencen mañana');
select is(public.enqueue_due_reminders(timestamptz '2026-11-01 11:00-03'), 0, 'no repite el recordatorio');
select is((select tarea from public.claim_telegram_outbox() where kind = 'recordatorio'), 'Vence mañana',
  'el recordatorio lleva la tarea');

update public.tasks set due_date = date '2026-11-02' where titulo = 'Vence pasado';
select is(public.enqueue_due_reminders(timestamptz '2026-11-01 11:00-03'), 1,
  'si cambia la fecha límite, vuelve a corresponder el recordatorio');

select * from finish();
rollback;
