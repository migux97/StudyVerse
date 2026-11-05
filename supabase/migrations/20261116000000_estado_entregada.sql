-- Estado "entregada": la tarea está lista y espera que un admin la apruebe.
-- Va sola en su migración: un valor nuevo de un enum no se puede usar en la
-- misma transacción en la que se agrega.
alter type public.estado_tarea add value if not exists 'entregada' before 'hecha';
