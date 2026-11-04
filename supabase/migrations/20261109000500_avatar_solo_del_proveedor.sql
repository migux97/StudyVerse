-- El avatar lo pone el registro (Google) y nadie lo cambia desde la app: una
-- URL elegida por el usuario hacía que cada compañero que la mostraba le
-- avisara su IP a ese servidor.
revoke update on public.profiles from authenticated;
grant update (nombre) on public.profiles to authenticated;
