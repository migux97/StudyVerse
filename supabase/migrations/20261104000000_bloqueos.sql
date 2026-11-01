-- Fase 4: bloqueo de archivos ("Estoy editando este archivo").
--
-- Reglas:
--   * Un integrante bloquea un archivo; mientras tanto solo él puede subir
--     versiones, renombrarlo, restaurarlo o eliminarlo (ver locked_by_other).
--   * Subir una versión nueva lo desbloquea solo (finish_upload).
--   * Los bloqueos vencen a las 24 h (lock_ttl): se ignoran al instante y un
--     job de pg_cron los limpia para que todos vean el cambio en vivo.
--   * El admin del grupo puede forzar el desbloqueo.

create or replace function public.lock_file(p_file_id uuid)
returns public.files
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
  quien text;
begin
  select * into f from public.files where id = p_file_id for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;

  if public.locked_by_other(f) then
    select nombre into quien from public.profiles where id = f.locked_by;
    raise exception '% ya está editando este archivo', coalesce(quien, 'Otra persona')
      using errcode = 'P0001';
  end if;

  -- Si ya era mío, renueva las 24 h.
  update public.files set locked_by = auth.uid(), locked_at = now()
  where id = p_file_id
  returning * into f;
  return f;
end;
$$;

-- Desbloquea si el bloqueo es mío, si ya venció o si soy admin del grupo.
create or replace function public.unlock_file(p_file_id uuid)
returns public.files
language plpgsql security definer set search_path = ''
as $$
declare
  f public.files;
begin
  select * into f from public.files where id = p_file_id for update;
  if f.id is null or not public.is_group_member(f.group_id) then
    raise exception 'El archivo no existe' using errcode = 'P0002';
  end if;

  if public.locked_by_other(f) and not public.is_group_admin(f.group_id) then
    raise exception 'Solo quien lo está editando o un admin pueden desbloquearlo'
      using errcode = '42501';
  end if;

  update public.files set locked_by = null, locked_at = null
  where id = p_file_id
  returning * into f;
  return f;
end;
$$;

-- Limpia los bloqueos vencidos. Devuelve cuántos liberó.
create or replace function public.release_expired_locks()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  update public.files set locked_by = null, locked_at = null
  where locked_by is not null and locked_at <= now() - public.lock_ttl();
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.lock_file(uuid) from public, anon;
revoke execute on function public.unlock_file(uuid) from public, anon;
revoke execute on function public.release_expired_locks() from public, anon, authenticated;
grant execute on function public.lock_file(uuid) to authenticated;
grant execute on function public.unlock_file(uuid) to authenticated;

-- Cada 15 minutos, liberar los vencidos.
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'liberar-bloqueos-vencidos',
  '*/15 * * * *',
  $$ select public.release_expired_locks() $$
);
