-- Limpieza de objetos huérfanos en Storage y llamada genérica a funciones internas.
--
-- Quedan objetos sin versión cuando se borra un grupo (la base borra en
-- cascada pero no puede borrar archivos de Storage) o cuando una subida se
-- corta antes de finish_upload. La Edge Function `storage-cleanup` los borra
-- con la API de Storage; un job de pg_cron la llama todos los días.
--
-- Configuración en Vault (reemplaza a la de la fase 6):
--   functions_base_url        p. ej. https://<proyecto>.supabase.co/functions/v1
--   internal_functions_secret mismo valor que INTERNAL_FUNCTIONS_SECRET en las funciones

-- Llama a una Edge Function interna (fire-and-forget). Si falta la
-- configuración, no hace nada.
create or replace function public.call_internal_function(p_nombre text, p_body jsonb default '{}')
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  base text;
  secreto text;
begin
  select decrypted_secret into base from vault.decrypted_secrets where name = 'functions_base_url';
  select decrypted_secret into secreto from vault.decrypted_secrets where name = 'internal_functions_secret';
  if base is null or secreto is null then
    return;
  end if;
  perform net.http_post(
    url := rtrim(base, '/') || '/' || p_nombre,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', secreto),
    body := coalesce(p_body, '{}')
  );
end;
$$;

revoke execute on function public.call_internal_function(text, jsonb) from public, anon, authenticated;

create or replace function public.telegram_kick()
returns void
language sql security definer set search_path = ''
as $$ select public.call_internal_function('telegram-send') $$;

revoke execute on function public.telegram_kick() from public, anon, authenticated;

-- Objetos del bucket que ya no usa ninguna versión y tienen más de
-- p_edad_minima (para no tocar una subida en curso).
create or replace function public.orphan_storage_objects(
  p_edad_minima interval default interval '24 hours',
  p_limite integer default 500
)
returns setof text
language sql stable security definer set search_path = ''
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'archivos'
    and o.created_at < now() - p_edad_minima
    and not exists (select 1 from public.file_versions v where v.storage_path = o.name)
  order by o.created_at
  limit p_limite
$$;

revoke execute on function public.orphan_storage_objects(interval, integer) from public, anon, authenticated;

select cron.schedule('limpiar-storage', '30 4 * * *',
  $$ select public.call_internal_function('storage-cleanup') $$);
