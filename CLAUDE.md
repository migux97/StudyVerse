# CLAUDE.md

Guía para trabajar en este repo. El detalle funcional está en el README.

## Reglas de git (obligatorias)

- Autor de todo: `migux97` / `franbenastro@gmail.com`. Verificar con `git config user.name` y `git config user.email` antes de cada commit.
- Prohibido incluir `Co-Authored-By: Claude`, `Claude-Session`, "Generated with Claude Code" o cualquier atribución a Claude o Anthropic en commits, PRs, issues, docs o README.
- No agregar a Claude ni a ningún bot como colaborador.
- Trabajar directo en la rama `dev`. No crear ramas nuevas. El paso a `main` lo decide el dueño del repo.
- Antes de pushear, revisar `git log -1 --format=%B` (y la descripción del PR) para confirmar que no quedó ninguna atribución.
- Commits chicos y descriptivos, en español.
- Variables de entorno en `.env` (con `.env.example`). Nunca subir claves al repo. El token del bot va en variables de entorno, nunca en el código.
- El hook `.githooks/commit-msg` rechaza atribuciones y autores distintos. Activarlo una vez por clon: `git config core.hooksPath .githooks`.

## Agentes revisores

Están en `.claude/agents/`. Lanzarlos en paralelo sobre lo que cambió, antes de commitear:

| Si cambió… | Agentes |
|---|---|
| `supabase/migrations/`, `supabase/functions/` | `seguridad` y `base-de-datos` |
| `app/lib/` | `flutter` (y `seguridad` si maneja datos o permisos) |
| algo nuevo sin tests | `tests` |

Antes de pasar a `main`: revisión completa con `seguridad`, `base-de-datos` y `flutter`. Los revisores no editan; sus hallazgos se verifican antes de corregir.

## Stack

- `app/`: Flutter (Android + Web), Material 3, Riverpod 3, go_router, supabase_flutter. Todo en español rioplatense (voseo).
- `supabase/`: migraciones SQL, tests pgTAP, Edge Functions en Deno/TypeScript (bot de Telegram, limpieza de Storage).

## Comandos

```bash
npx supabase start                 # Supabase local (requiere Docker Desktop)
npx supabase db reset              # migraciones + seed
npx supabase test db               # tests pgTAP
deno test supabase/functions/_shared

cd app
flutter analyze
flutter test
flutter run -d chrome --web-port 3000 --dart-define-from-file=.env
flutter build web --dart-define-from-file=.env
flutter build apk --dart-define-from-file=.env
```

Funciones locales: `supabase/scripts/configurar-funciones-local.ps1` y después `npx supabase functions serve --env-file supabase/functions/.env`.

Usuarios de prueba del seed: `ana@tpdrive.test` y `juan@tpdrive.test` (contraseña en `supabase/seed.sql`).

## Convenciones

- Cada feature en `app/lib/features/<feature>/` con `data/`, `domain/` y `presentation/`.
- Probar cada cambio primero en la web; Android se usa como verificación de compilación.
- Toda tabla nueva lleva RLS y su test pgTAP. Las operaciones sensibles (subir versiones, bloquear, unirse a un grupo) van en funciones `security definer` que validan permisos; el cliente no escribe directo en esas tablas.
- Las migraciones son nuevas y en orden (`supabase/migrations/AAAAMMDDhhmmss_nombre.sql`); no editar las ya commiteadas.
- Rutas de Storage: `groups/{group_id}/files/{file_id}/v{n}`. Toda subida pasa por `begin_upload` (reserva la ruta) y `finish_upload`; Storage rechaza rutas no reservadas. El `n` de la ruta es la clave de la reserva y casi siempre coincide con el número de versión, que se asigna al terminar.
- Los tests pgTAP de conteos filtran por el grupo que crea el propio test, para no depender de datos locales.

## Trampas conocidas

- Riverpod 3 solo notifica si el valor cambia: los streams de avisos en vivo emiten un contador (`map((_) => ++n)`), no `null`.
- En vivo: canales privados de Broadcast (`core/realtime/canales.dart` y la migración `realtime_privado`). Una tabla nueva que se vea en vivo necesita un trigger `avisar_grupo('<canal>')`; si hace falta un canal nuevo, agregarlo también en `realtime_topic_allowed`. No usar `postgres_changes` ni volver a agregar tablas a la publicación `supabase_realtime`: los DELETE no pasan por la RLS.
- Los errores esperados son `AppFailure` y no se reintentan (`reintentoProviders` en el `ProviderScope`); si no, Riverpod reintenta y la pantalla queda cargando.
- Después de `npx supabase db reset`, Realtime local puede quedar roto (error `42P10 ... ON CONFLICT` al suscribirse). Se arregla con `npx supabase stop` y `npx supabase start`.
- La actividad se ordena con `clock_timestamp()`, no `now()` (que es constante dentro de la transacción).
- `storage_used` se ajusta con triggers a nivel sentencia en los borrados, para no restar dos veces en cascada.
- Android: `127.0.0.1` se traduce a `10.0.2.2` en el emulador; `kotlin.incremental=false` porque el proyecto y el pub cache están en discos distintos. Compilar con el emulador apagado si hay poca RAM.
- En la web, abrir archivos usa una ventana creada en el mismo clic (Safari bloquea pop-ups abiertos después de un `await`).
