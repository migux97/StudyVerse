-- Funciones auxiliares que no tiene que poder llamar nadie desde la API.
--
-- nombre_de devolvía el nombre de cualquier usuario (sin pasar por la RLS de
-- profiles) e is_member_of servía para averiguar quién es de qué grupo, y las
-- dos se podían llamar incluso sin iniciar sesión.

-- tasks_before_write llama a is_member_of; pasa a security definer para que
-- authenticated no necesite permiso sobre la función.
alter function public.tasks_before_write() security definer;

revoke execute on function public.nombre_de(uuid) from public, anon, authenticated;
revoke execute on function public.is_member_of(uuid, uuid) from public, anon, authenticated;

-- Estas las usan las políticas RLS (se evalúan como authenticated), así que
-- solo se les saca anon.
revoke execute on function public.version_visible(uuid, integer) from public, anon;
revoke execute on function public.storage_path_in_use(text) from public, anon;
grant execute on function public.version_visible(uuid, integer) to authenticated;
grant execute on function public.storage_path_in_use(text) to authenticated;
