-- Datos de ejemplo para desarrollo local. Se cargan con `supabase db reset`.
-- Usuarios de prueba (contraseña: Prueba123!). Solo para el entorno local.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new
) values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111',
   'authenticated', 'authenticated', 'ana@studyverse.test', crypt('Prueba123!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"nombre":"Ana"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222',
   'authenticated', 'authenticated', 'juan@studyverse.test', crypt('Prueba123!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"nombre":"Juan"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333',
   'authenticated', 'authenticated', 'profe@studyverse.test', crypt('Prueba123!', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"nombre":"Laura Gómez","tipo":"docente"}', now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), id, id::text,
       json_build_object('sub', id::text, 'email', email)::jsonb,
       'email', now(), now(), now()
from auth.users
where email in ('ana@studyverse.test', 'juan@studyverse.test', 'profe@studyverse.test');
