-- Códigos de invitación y de Telegram: generador criptográfico y 10
-- caracteres (31^10 ≈ 8·10^14 combinaciones), para que no se puedan adivinar
-- probando. Los códigos que ya existen siguen valiendo.
create or replace function public.generate_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alfabeto constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  codigo text;
  b integer;
begin
  loop
    codigo := '';
    while length(codigo) < 10 loop
      b := get_byte(extensions.gen_random_bytes(1), 0);
      -- Se descartan 248..255 para que todas las letras salgan con la misma
      -- probabilidad (248 = 8 × 31).
      if b < 248 then
        codigo := codigo || substr(alfabeto, 1 + b % 31, 1);
      end if;
    end loop;
    exit when not exists (select 1 from public.groups where invite_code = codigo);
  end loop;
  return codigo;
end;
$$;

revoke execute on function public.generate_invite_code() from public, anon, authenticated;
