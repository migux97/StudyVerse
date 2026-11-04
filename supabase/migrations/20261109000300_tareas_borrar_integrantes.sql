-- Borrar una tarea exige seguir siendo del grupo: quien se fue no puede
-- borrar las que había creado.
drop policy "tasks: elimina quien la creó o un admin" on public.tasks;

create policy "tasks: elimina quien la creó o un admin"
  on public.tasks for delete to authenticated
  using (
    public.is_group_member(group_id)
    and (created_by = (select auth.uid()) or public.is_group_admin(group_id))
  );
