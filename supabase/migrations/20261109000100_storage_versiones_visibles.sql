-- Storage sirve solo lo que el plan deja ver.
--
-- Antes alcanzaba con ser del grupo, y como las rutas son predecibles
-- (.../v1) se podían bajar versiones que el plan free oculta.
-- Ahora un objeto se puede leer si:
--   * lo usa alguna versión visible (restaurar reutiliza objetos viejos), o
--   * no lo usa ninguna versión (huérfano: hace falta para borrarlo después
--     de delete_file; la limpieza diaria se lleva el resto), o
--   * es una subida mía en curso.

create or replace function public.storage_object_readable(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
           select 1 from public.file_versions v
           where v.storage_path = p_path and public.version_visible(v.file_id, v.version_number))
      or not exists (select 1 from public.file_versions v where v.storage_path = p_path)
      or public.upload_reserved(p_path)
$$;

revoke execute on function public.storage_object_readable(text) from public, anon;
grant execute on function public.storage_object_readable(text) to authenticated;

drop policy "archivos: leer los de mis grupos" on storage.objects;

create policy "archivos: leer los visibles de mis grupos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'archivos'
    and public.is_group_member(((storage.foldername(name))[2])::uuid)
    and public.storage_object_readable(name)
  );
