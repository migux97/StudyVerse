-- Fase 6: bot de Telegram.
--
--   * Vincular: el admin genera en la app un código de un solo uso (30 min) y
--     en el grupo de Telegram se manda "/vincular CODIGO". No se usa el código
--     de invitación: quien lo tuviera podría escuchar los avisos del grupo.
--   * Avisos: cada evento de `activity` que interesa se encola en
--     `telegram_outbox` (uno por chat vinculado). La Edge Function
--     `telegram-send` los envía; pg_net la despierta al instante y pg_cron
--     reintenta cada minuto lo que haya quedado pendiente.
--   * Recordatorios: el día anterior a cada fecha límite, a las 10 (hora de
--     Argentina), se encola un aviso por cada tarea sin terminar.
--
-- La URL de la función y el secreto interno van en Supabase Vault
-- (`telegram_send_url`, `telegram_internal_secret`); ver README.

create extension if not exists pg_net with schema extensions;

-- Vínculos -------------------------------------------------------------------

create table public.telegram_links (
  group_id    uuid not null references public.groups (id) on delete cascade,
  chat_id     bigint not null,
  chat_title  text,
  linked_by   uuid references public.profiles (id) on delete set null,
  linked_at   timestamptz not null default now(),
  primary key (group_id, chat_id)
);

alter table public.telegram_links enable row level security;

create policy "telegram_links: ver los de mis grupos"
  on public.telegram_links for select to authenticated
  using (public.is_group_member(group_id));

create policy "telegram_links: el admin desvincula"
  on public.telegram_links for delete to authenticated
  using (public.is_group_admin(group_id));

-- Solo el bot (service_role) crea vínculos.
revoke insert, update on public.telegram_links from authenticated;

create table public.telegram_link_codes (
  code        text primary key,
  group_id    uuid not null references public.groups (id) on delete cascade,
  created_by  uuid references public.profiles (id) on delete set null,
  expires_at  timestamptz not null default now() + interval '30 minutes'
);

alter table public.telegram_link_codes enable row level security;
-- Sin políticas: los clientes no los leen; se crean con la función de abajo.

create or replace function public.create_telegram_link_code(p_group_id uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  c text;
begin
  if not public.is_group_admin(p_group_id) then
    raise exception 'Solo el admin puede conectar Telegram' using errcode = '42501';
  end if;

  -- Un código vigente por grupo: el nuevo reemplaza al anterior.
  delete from public.telegram_link_codes l where l.group_id = p_group_id or l.expires_at < now();
  c := public.generate_invite_code();
  insert into public.telegram_link_codes (code, group_id, created_by)
  values (c, p_group_id, auth.uid());

  return query select l.code, l.expires_at from public.telegram_link_codes l where l.code = c;
end;
$$;

revoke execute on function public.create_telegram_link_code(uuid) from public, anon;
grant execute on function public.create_telegram_link_code(uuid) to authenticated;

-- Lo usa el webhook del bot (service_role) al recibir "/vincular CODIGO".
create or replace function public.redeem_telegram_link_code(p_code text, p_chat_id bigint, p_chat_title text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  l public.telegram_link_codes;
  g public.groups;
begin
  delete from public.telegram_link_codes
  where code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
    and expires_at > now()
  returning * into l;

  if l.code is null then
    raise exception 'Código inválido o vencido' using errcode = 'P0002';
  end if;

  insert into public.telegram_links (group_id, chat_id, chat_title, linked_by)
  values (l.group_id, p_chat_id, p_chat_title, l.created_by)
  on conflict (group_id, chat_id) do update set chat_title = excluded.chat_title;

  select * into g from public.groups where id = l.group_id;
  perform public.log_activity(g.id, l.created_by, 'telegram_vinculado',
    jsonb_build_object('chat', coalesce(p_chat_title, 'un chat')));
  return g;
end;
$$;

revoke execute on function public.redeem_telegram_link_code(text, bigint, text) from public, anon, authenticated;

-- Cola de envíos ---------------------------------------------------------------

create table public.telegram_outbox (
  id            bigint generated always as identity primary key,
  chat_id       bigint not null,
  group_id      uuid not null references public.groups (id) on delete cascade,
  kind          text not null check (kind in ('actividad', 'recordatorio')),
  activity_id   uuid references public.activity (id) on delete cascade,
  task_id       uuid references public.tasks (id) on delete cascade,
  created_at    timestamptz not null default now(),
  attempts      integer not null default 0,
  locked_until  timestamptz,
  sent_at       timestamptz,
  last_error    text
);

create index telegram_outbox_pendientes on public.telegram_outbox (id) where sent_at is null;

alter table public.telegram_outbox enable row level security;
-- Sin políticas: solo la usa el bot (service_role).

-- Qué eventos se avisan por Telegram.
create or replace function public.telegram_notifica(p_tipo text)
returns boolean language sql immutable as $$
  select p_tipo in (
    'version_subida', 'version_restaurada',
    'archivo_bloqueado', 'archivo_desbloqueado', 'desbloqueo_forzado', 'liberacion_pedida',
    'tarea_completada'
  )
$$;

-- Despierta a la Edge Function (si está configurada en Vault). Si no lo
-- está, o falla, el cron la llama igual cada minuto.
create or replace function public.telegram_kick()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  url text;
  secreto text;
begin
  select decrypted_secret into url from vault.decrypted_secrets where name = 'telegram_send_url';
  select decrypted_secret into secreto from vault.decrypted_secrets where name = 'telegram_internal_secret';
  if url is null or secreto is null then
    return;
  end if;
  perform net.http_post(
    url := url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', secreto),
    body := '{}'::jsonb
  );
end;
$$;

revoke execute on function public.telegram_kick() from public, anon, authenticated;

create or replace function public.telegram_enqueue_activity()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.telegram_notifica(new.tipo) then
    return new;
  end if;

  insert into public.telegram_outbox (chat_id, group_id, kind, activity_id)
  select l.chat_id, new.group_id, 'actividad', new.id
  from public.telegram_links l
  where l.group_id = new.group_id;

  if found then
    perform public.telegram_kick();
  end if;
  return new;
end;
$$;

create trigger activity_telegram
  after insert on public.activity
  for each row execute function public.telegram_enqueue_activity();

-- Recordatorios ----------------------------------------------------------------

alter table public.tasks add column reminder_sent_at timestamptz;

-- Si cambia la fecha límite, el recordatorio vuelve a corresponder.
create or replace function public.tasks_reset_reminder()
returns trigger language plpgsql as $$
begin
  if new.due_date is distinct from old.due_date then
    new.reminder_sent_at := null;
  end if;
  return new;
end;
$$;

create trigger tasks_reset_reminder
  before update of due_date on public.tasks
  for each row execute function public.tasks_reset_reminder();

-- Encola los recordatorios de las tareas que vencen mañana (hora de
-- Argentina), a partir de las 10. Devuelve cuántas tareas avisó.
create or replace function public.enqueue_due_reminders(p_ahora timestamptz default now())
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  local timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  n integer;
begin
  if local::time < time '10:00' then
    return 0;
  end if;

  with avisar as (
    update public.tasks t
    set reminder_sent_at = p_ahora
    where t.estado <> 'hecha'
      and t.due_date = local::date + 1
      and t.reminder_sent_at is null
    returning t.id, t.group_id
  ), encoladas as (
    insert into public.telegram_outbox (chat_id, group_id, kind, task_id)
    select l.chat_id, a.group_id, 'recordatorio', a.id
    from avisar a join public.telegram_links l on l.group_id = a.group_id
    returning 1
  )
  select (select count(*) from avisar) into n;

  if n > 0 then
    perform public.telegram_kick();
  end if;
  return n;
end;
$$;

revoke execute on function public.enqueue_due_reminders(timestamptz) from public, anon, authenticated;

-- Para la Edge Function: toma hasta p_limite envíos pendientes (sin pisarse
-- si corren dos a la vez) con todo lo necesario para armar el mensaje.
create or replace function public.claim_telegram_outbox(p_limite integer default 20)
returns table (
  id bigint,
  chat_id bigint,
  kind text,
  grupo text,
  tipo text,
  actor text,
  payload jsonb,
  tarea text,
  responsable text,
  due_date date
)
language plpgsql security definer set search_path = ''
as $$
begin
  return query
  with tomados as (
    update public.telegram_outbox o
    set attempts = o.attempts + 1, locked_until = now() + interval '2 minutes'
    where o.id in (
      select x.id from public.telegram_outbox x
      where x.sent_at is null
        and x.attempts < 5
        and (x.locked_until is null or x.locked_until < now())
      order by x.id
      limit p_limite
      for update skip locked
    )
    returning o.*
  )
  select t.id, t.chat_id, t.kind, g.nombre, a.tipo, p.nombre, a.payload,
         tk.titulo, pr.nombre, tk.due_date
  from tomados t
  join public.groups g on g.id = t.group_id
  left join public.activity a on a.id = t.activity_id
  left join public.profiles p on p.id = a.user_id
  left join public.tasks tk on tk.id = t.task_id
  left join public.profiles pr on pr.id = tk.assigned_to
  order by t.id;
end;
$$;

revoke execute on function public.claim_telegram_outbox(integer) from public, anon, authenticated;

-- Jobs ---------------------------------------------------------------------------

select cron.schedule('telegram-reintentos', '* * * * *',
  $$ select public.telegram_kick() where exists (
       select 1 from public.telegram_outbox where sent_at is null and attempts < 5) $$);

select cron.schedule('telegram-recordatorios', '*/30 * * * *',
  $$ select public.enqueue_due_reminders() $$);

alter table public.telegram_links replica identity full;
alter publication supabase_realtime add table public.telegram_links;
