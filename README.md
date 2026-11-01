# TP Drive

App para que estudiantes universitarios trabajen en grupo en sus TPs: carpetas por grupo, archivos con versiones, bloqueos, tareas y avisos por Telegram. Un solo código Flutter para **Android** y **Web**.

## Estructura

```
app/        Flutter (Riverpod + go_router + Material 3)
  lib/core/       config, router, tema, widgets comunes
  lib/features/   auth, groups, files, tasks, activity (data / domain / presentation)
supabase/   migraciones, seed, tests de base de datos (pgTAP), edge functions
```

## Requisitos

- Flutter (stable) — `flutter --version`
- Docker Desktop (para Supabase local)
- Node.js (se usa `npx supabase`, no hace falta instalar la CLI)
- Android SDK (para compilar la app de Android)
- Deno (solo para los tests de las Edge Functions)

## Cómo correrlo

### 1. Backend (Supabase local)

```bash
cp supabase/.env.example supabase/.env   # credenciales de Google (opcional)
npx supabase start                       # levanta Postgres, Auth, Storage, Realtime
npx supabase db reset                    # aplica migraciones + seed
```

`npx supabase status` muestra la URL de la API, la **Publishable key** y el Studio (http://127.0.0.1:54323).

Usuarios de prueba del seed: `ana@tpdrive.test` y `juan@tpdrive.test` (contraseña en `supabase/seed.sql`, solo para local).

### 2. App

```bash
cd app
cp .env.example .env                     # completar SUPABASE_PUBLISHABLE_KEY
flutter run -d chrome --web-port 3000 --dart-define-from-file=.env
flutter run -d emulator-5554 --dart-define-from-file=.env
```

En el emulador de Android, `127.0.0.1` se traduce solo a `10.0.2.2`.

### Login con Google

1. En Google Cloud Console crear un ID de cliente OAuth **Web** con la URI de redirección `http://127.0.0.1:54321/auth/v1/callback`.
2. Completar `supabase/.env` con el client id y el secret, y reiniciar (`npx supabase stop && npx supabase start`).
3. Android vuelve a la app por el deep link `io.tpdrive.app://login-callback`.

## Tests

```bash
cd app && flutter test                   # unit y widget tests
npx supabase test db                     # políticas RLS y triggers (pgTAP)
deno test supabase/functions/_shared     # textos y comandos del bot
```

## Variables de entorno

Nunca se suben claves al repo: `.env` está en `.gitignore`; solo se versionan los `.env.example`.

| Archivo | Variable | Uso |
|---|---|---|
| `app/.env` | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Cliente Flutter |
| `supabase/.env` | `SUPABASE_AUTH_EXTERNAL_GOOGLE_*` | Login con Google |
| `supabase/functions/.env` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, `TELEGRAM_INTERNAL_SECRET` | Bot de Telegram |

## Archivos y versiones

Los archivos van a Supabase Storage (bucket privado `archivos`), nunca a la base. Cada versión es un objeto en `groups/{group_id}/files/{file_id}/v{n}`.

Subir un archivo son tres pasos:

1. `begin_upload` valida que seas del grupo, que el archivo no lo esté editando otra persona y que haya espacio; devuelve la ruta.
2. La app sube los bytes a Storage en esa ruta.
3. `finish_upload` verifica que el objeto exista, toma el tamaño real desde Storage y registra la versión.

Subir un archivo con el mismo nombre (sin importar mayúsculas) en la misma carpeta crea una versión nueva. Restaurar una versión crea otra nueva que reutiliza el objeto viejo, así que no ocupa espacio extra. `groups.storage_used` se mantiene con triggers.

Límite por archivo: 50 MB.

### Bloqueos ("Estoy editando este archivo")

El bloqueo avisa y protege, pero nadie tiene que quedarse esperando:

- `lock_file(file, minutos)` bloquea el archivo por el tiempo elegido: 2 h (por defecto), hasta la noche o 24 h, como máximo. Se puede renovar. Los demás ven "🔒 Ana está editando" en vivo.
- Mientras está bloqueado, solo quien lo bloqueó puede subir versiones, renombrar, restaurar o eliminar el original. Lo controla la base.
- Los demás tienen dos opciones:
  - **Subir sus cambios como copia** (`Informe (copia de Juan).docx`), al lado del original y sin pisarlo.
  - **Pedirle que lo libere** (`request_unlock`): a quien lo tiene le llega un aviso en cualquier pantalla, con un botón "Liberar".
- Subir una versión nueva lo desbloquea solo. `unlock_file` lo libera a mano, o lo fuerza si sos admin del grupo. Al liberarlo se borran los pedidos.
- Al vencer (`lock_until`) se ignora al instante, y un job de `pg_cron` (`liberar-bloqueos-vencidos`, cada 15 min) lo limpia para que todos vean el cambio.

## Tareas, actividad y aportes

- **Tareas** (`tasks`): título, responsable (tiene que ser del grupo), fecha límite, estado (pendiente / en progreso / hecha) y TP opcional (una carpeta de primer nivel). `completed_at` lo maneja un trigger.
- **Actividad** (`activity`): la escriben solo los triggers. Registran versiones subidas o restauradas, bloqueos, renombres, bajas, carpetas, altas y bajas de integrantes, tareas y pedidos de liberación. El payload guarda los nombres, así el feed se sigue leyendo bien aunque después se renombre o borre algo. Es la fuente que va a usar el bot de Telegram.
- **Aportes** (`group_contributions`): tareas completadas y versiones subidas por integrante. Cuenta también las versiones que el plan free no muestra.

## Bot de Telegram

Avisa en un grupo de Telegram cuando alguien sube una versión, empieza o termina de editar un archivo, pide uno que está bloqueado o completa una tarea. También recuerda las fechas límite el día anterior, a las 10 (hora de Argentina). Comandos: `/vincular CODIGO`, `/pendientes`, `/desvincular`, `/ayuda`.

**Cómo funciona**

- **Vincular.** En la app, el admin abre *Avisos por Telegram* y genera un código de un solo uso que vence a los 30 minutos. En el grupo de Telegram se manda `/vincular CODIGO`. No se usa el código de invitación: quien lo tuviera podría escuchar los avisos.
- **Avisos.** Cada evento de `activity` que interesa se encola en `telegram_outbox` (uno por chat). La Edge Function `telegram-send` arma el mensaje y lo envía. La base la despierta al instante con `pg_net`, y `pg_cron` reintenta cada minuto lo pendiente (hasta 5 intentos). Si echan al bot de un chat, ese chat se desvincula solo.
- **Edge Functions** (`supabase/functions`):
  - `telegram-webhook`: recibe los mensajes y valida el `secret_token` de Telegram.
  - `telegram-send`: envía lo encolado y valida un secreto interno.
  - `_shared/mensajes.ts`: los textos.

**Crear el bot** (una vez)

1. En Telegram, hablale a [@BotFather](https://t.me/BotFather) → `/newbot`. Te da el **token** y el **usuario** del bot.
2. Poné el usuario (sin @) en `app/.env` → `TELEGRAM_BOT_USERNAME`.

**Local**

```bash
./supabase/scripts/configurar-telegram-local.ps1 -BotToken "TOKEN_DE_BOTFATHER"
npx supabase functions serve --env-file supabase/functions/.env
```

El script crea `supabase/functions/.env` con secretos aleatorios y los registra en Vault. Telegram necesita una URL pública para el webhook: localmente se puede usar un túnel (por ejemplo `cloudflared tunnel --url http://localhost:54321`). Para probar sin Telegram, pasá `-ApiBase` con la URL de un servidor simulado.

**Producción** (proyecto en supabase.com)

```bash
npx supabase secrets set --env-file supabase/functions/.env
npx supabase functions deploy telegram-webhook --no-verify-jwt
npx supabase functions deploy telegram-send --no-verify-jwt
```

En el SQL Editor del proyecto, guardá en Vault la URL de `telegram-send` y el mismo `TELEGRAM_INTERNAL_SECRET`:

```sql
select vault.create_secret('https://<proyecto>.supabase.co/functions/v1/telegram-send', 'telegram_send_url');
select vault.create_secret('<TELEGRAM_INTERNAL_SECRET>', 'telegram_internal_secret');
```

Y registrá el webhook (con el `TELEGRAM_WEBHOOK_SECRET`):

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<proyecto>.supabase.co/functions/v1/telegram-webhook&secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```

## Planes

Los límites de cada plan están en la tabla `plan_limits` (free: 500 MB por grupo y últimas 3 versiones visibles). Se aplican en la base: la cuota en `begin_upload` y las versiones visibles en la política RLS de `file_versions`.
