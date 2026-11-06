# StudyVerse

App para que estudiantes universitarios trabajen en grupo en sus TPs, tan simple como Google Drive: entrás, ves las carpetas de tus grupos, subís archivos y listo. Un solo código Flutter para **Android** y **Web**, con Supabase como backend.

## Qué hace

- **Grupos.** Cada grupo es una carpeta. Se entra con un código o un link de invitación, sin email. Roles: admin (quien lo crea) y miembro.
- **Archivos con versiones.** Subir un archivo con el mismo nombre crea la versión siguiente, no un duplicado. Cada versión guarda quién la subió, cuándo, el tamaño y una nota opcional. Restaurar una versión vieja crea una nueva y no borra nada.
- **Bloqueos sin esperas.** "Estoy editando este archivo" avisa en vivo ("🔒 Ana está editando") y protege el original. Los demás pueden subir sus cambios como copia o pedirle que lo libere. El bloqueo vence solo y el admin puede forzar el desbloqueo.
- **Documentos de StudyVerse.** *Nuevo › Documento* crea un documento que se escribe en la app, como en Word: títulos, negrita, cursiva, subrayado, colores, listas (con viñetas, numeradas y de tareas), alineación, citas y links. Se edita de a uno (con el bloqueo de siempre): mientras escribís se guarda solo cada pocos segundos y tus compañeros lo ven en vivo; al tocar *Listo* (o salir) queda como versión. Se descarga como Word (.docx) o PDF, y un .docx se abre como documento editable con *Editar en StudyVerse*.
- **Visor de archivos.** *Abrir* muestra el archivo dentro de la app: PDF, imágenes (con zoom), Word, Excel y CSV (en solapas, como planilla), PowerPoint (el texto de cada diapositiva), video, audio, texto y código. Los archivos de texto y código se pueden editar ahí mismo; cada cambio guardado es una versión nueva.
- **Inicio como Drive.** Arriba de *Mis grupos*: *Buscar en StudyVerse* (por nombre, en todos tus grupos, sin importar tildes), lo que *Se viene en la semana*, tus *Destacados* (estrella en el menú de cada archivo) y tus *Recientes* (lo último que abriste).
- **Docentes y cursos.** Al registrarse se elige *Soy estudiante* o *Soy docente* (se puede cambiar en el perfil). El docente crea cursos ("Física II · Comisión 3") con un código; el admin de cada grupo lo suma en *Más opciones → Sumar a un curso*. El docente ve, en solo lectura, los grupos de su curso: archivos y versiones, tareas, actividad y aportes, y puede comentar. Nunca recibe el código de invitación del grupo ni puede entrar como integrante.
- **Notificaciones.** La campanita junta menciones, tareas asignadas, avisos y devoluciones del docente, revisiones de entregas y pedidos de archivo. Con Firebase configurado también llegan como push al celular y al navegador, aunque la app esté cerrada; tocarlas abre la pantalla.
- **Avisos y devoluciones del docente.** Desde el curso, el docente manda avisos a todo el curso o a un grupo (aparecen arriba en el grupo y llegan en vivo), y en cada tarea deja una *devolución* que ve todo el grupo; a quien tiene o entregó la tarea le llega un aviso. Hasta 20 avisos y 60 devoluciones por hora.
- **Aprobación de tareas (opcional).** El admin activa "Las tareas las aprueba un admin" en Tareas. Desde ahí, quien hace una tarea la *entrega* (con una nota) y un admin la *aprueba* o *pide cambios*; solo un admin puede dejar una tarea como hecha. A quien entregó le llega un aviso en vivo.
- **Varias materias por grupo.** Un mismo grupo de estudio puede cursar varias materias juntos: cada materia es una carpeta principal con color (como las carpetas de colores de Drive), con sus TPs y archivos adentro. Se cargan al crear el grupo o con *Nuevo → Nueva materia*, y una carpeta de la raíz se puede *usar como materia*. Las tareas y los eventos del calendario se asocian a una materia.
- **Historial y comparación de versiones.** Cada archivo tiene su historial ordenado por día (quién, a qué hora, qué cambió). Una versión se puede *guardar con nombre* ("Entrega 1"): queda arriba y no se oculta con el plan gratis (hasta 10 por archivo; 50 en premium). *Comparar* muestra lo agregado en verde y lo quitado en rojo, palabra por palabra, lado a lado o en una columna; funciona con texto, código, documentos de StudyVerse, Word (.docx), Excel (.xlsx/.csv), PowerPoint (.pptx), PDF con texto e imágenes (con deslizador).
- **Papelera.** Eliminar manda el archivo a la papelera del grupo (con *Deshacer*); ahí se restaura o se elimina para siempre. Se vacía sola a los 30 días.
- **Calendario.** Las fechas límite de las tareas de todos tus grupos y los eventos que agregue el grupo (parciales, entregas, clases), en un mes con la lista de cada día.
- **Comentarios.** Cada archivo y documento tiene su conversación (al costado en la PC, desde abajo en el celular). Mencionar a alguien con `@usuario` le avisa en vivo, esté donde esté en la app.
- **Tareas por TP.** Cada tarea tiene responsable, fecha límite y estado. La vista **Aportes** muestra cuántas tareas completó y cuántas versiones subió cada integrante.
- **Actividad.** Un feed por grupo: "Juan subió la v3 de Informe.docx", "Ana completó la tarea…".
- **Bot de Telegram.** Avisa las versiones nuevas, los bloqueos y las tareas completadas, y recuerda las fechas límite el día anterior.
- **Cuentas.** Registro con nombre, usuario (`@usuario`, único) y contraseña segura (8 caracteres, mayúscula, minúscula y número, con los requisitos en vivo). El email se confirma con un código de 6 números. También se entra con un código por mail (sin contraseña) o con Google, y se recupera la contraseña con un código.
- **Sesiones como en Drive.** Quedás conectado hasta que cierres sesión. En *Tu cuenta › Dispositivos conectados* ves dónde está abierta (navegador, sistema, último uso) y cerrás cualquiera, o todas menos la actual. Cambiar la contraseña cierra las demás.
- **Perfil.** Foto (se recorta y achica antes de subirla), nombre, usuario, carrera y universidad. Google se puede conectar a una cuenta creada con email, y viceversa.
- **Interfaz.** Material 3, blanco y celeste en modo claro y azul noche en modo oscuro (o el del sistema), todo en español. Los avisos son como los de Drive: cortos y al pie, sin cartelones rojos; los errores de un campo van debajo del campo.
  - En el celular: lista de archivos y barra de secciones abajo.
  - En la PC: columnas, riel lateral, panel de detalles y arrastrar y soltar archivos.

## Estructura

```
app/                      Flutter (Riverpod + go_router + Material 3)
  lib/core/               config, router, tema, errores, widgets comunes
  lib/features/
    auth/                 login, registro, perfil
    groups/               grupos, integrantes, invitaciones, navegación del grupo, Telegram
    files/                carpetas, archivos, versiones, bloqueos, subidas
    tasks/                tareas y aportes
    activity/             feed de actividad
                          (cada una con data / domain / presentation)
  test/                   unit y widget tests
supabase/
  migrations/             esquema, RLS, funciones y triggers (en orden)
  tests/database/         tests pgTAP (políticas RLS, triggers, funciones)
  functions/              Edge Functions (TypeScript / Deno)
  scripts/                configuración local de las funciones
  seed.sql                usuarios de prueba (solo local)
```

## Requisitos

- Flutter (stable)
- Docker Desktop (para Supabase local)
- Node.js (se usa `npx supabase`, no hace falta instalar la CLI)
- Android SDK (para compilar la app de Android)
- Deno (solo para los tests de las Edge Functions)

## Cómo correrlo

### 1. Backend (Supabase local)

```bash
cp supabase/.env.example supabase/.env   # credenciales de Google (opcional)
npx supabase start                       # Postgres, Auth, Storage, Realtime, Edge Runtime
npx supabase db reset                    # aplica migraciones + seed
```

`npx supabase status` muestra la URL de la API, la **Publishable key** y el Studio (http://127.0.0.1:54323).

Usuarios de prueba del seed: `ana@studyverse.test` y `juan@studyverse.test` (contraseña en `supabase/seed.sql`, solo para local).

Los correos (códigos de registro, de entrada y de recuperación) no salen a internet en local: se ven en Mailpit, http://127.0.0.1:54324.

Para que lleguen de verdad (por ejemplo, a tu Gmail), copiá `supabase/.env.example` a `supabase/.env` y completá:

```
SUPABASE_AUTH_EMAIL_SMTP_ENABLED=true
SMTP_HOST=smtp.gmail.com
SMTP_USER=tu.cuenta@gmail.com
SMTP_PASS=<contraseña de aplicación de 16 letras>
```

Con Gmail, la contraseña es una *contraseña de aplicación* (necesita la verificación en dos pasos): https://myaccount.google.com/apppasswords. Después, `npx supabase stop` y `npx supabase start`. Gmail permite unos 500 correos por día.

### 2. App

```bash
cd app
cp .env.example .env                     # completar SUPABASE_PUBLISHABLE_KEY
flutter run -d chrome --web-port 3000 --dart-define-from-file=.env
flutter run -d emulator-5554 --dart-define-from-file=.env
```

En el emulador de Android, `127.0.0.1` se traduce solo a `10.0.2.2`.

### 3. Edge Functions (bot de Telegram y limpieza de Storage)

```bash
./supabase/scripts/configurar-funciones-local.ps1 -BotToken "TOKEN_DE_BOTFATHER"
npx supabase functions serve --env-file supabase/functions/.env
```

El script crea `supabase/functions/.env` con secretos aleatorios y los registra en Vault, para que la base pueda llamar a las funciones. Para probar sin Telegram, pasá `-ApiBase` con la URL de un Telegram simulado.

### Notificaciones push (opcional)

Sin esto, las notificaciones quedan en la campanita de la app.

1. En [Firebase](https://console.firebase.google.com) creá un proyecto y agregale una app **Web** y una app **Android** (paquete `io.studyverse.app`).
2. En *Configuración del proyecto → Cloud Messaging → Certificados push web*, generá un par de claves (VAPID).
3. Completá en `app/.env` los `FIREBASE_*` (ver `app/.env.example`) y corré `./app/tool/configurar-firebase-web.ps1`, que arma la configuración del service worker.
4. En *Configuración del proyecto → Cuentas de servicio*, generá una clave privada (un JSON) y cargala en las funciones: `./supabase/scripts/configurar-funciones-local.ps1 -FcmCuentaServicio rutalrchivo.json -WebUrl http://localhost:3000`. Nunca lo subas al repo.
5. Compilá de nuevo la app y serví las funciones (`npx supabase functions serve --env-file supabase/functions/.env`).

En la web, cada persona activa los push desde la campanita (el navegador pide permiso). En Android se pide la primera vez que entra.

Al publicar la web, configurá el servidor para que no guarde en caché `assets/`, `main.dart.js` ni los service workers (`Cache-Control: no-cache`): Flutter no les cambia el nombre entre versiones y, si no, después de actualizar pueden faltar íconos o quedar código viejo.

### Login con Google

1. En Google Cloud Console, crear un ID de cliente OAuth **Web** con la URI de redirección `http://127.0.0.1:54321/auth/v1/callback` (y el origen `http://localhost:3000`).
2. Completar `supabase/.env` con `SUPABASE_AUTH_EXTERNAL_GOOGLE_ENABLED=true`, el client id y el secret, y reiniciar (`npx supabase stop && npx supabase start`). Mientras no esté activado, la app no muestra el botón de Google.
3. Android vuelve a la app por el deep link `io.studyverse.app://login-callback`.
4. Para conectar Google a una cuenta existente se usa la misma configuración (`enable_manual_linking = true`).

## Tests

```bash
cd app && flutter test                   # unit y widget tests
npx supabase test db                     # políticas RLS, triggers y funciones (pgTAP)
deno test supabase/functions/_shared     # textos y comandos del bot
```

## Variables de entorno

Nunca se suben claves al repo: los `.env` están en `.gitignore` y solo se versionan los `.env.example`.

| Archivo | Variable | Uso |
|---|---|---|
| `app/.env` | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Cliente Flutter |
| `app/.env` | `WEB_URL` | Links de invitación copiados desde Android |
| `app/.env` | `TELEGRAM_BOT_USERNAME` | Botón "Abrir en Telegram" |
| `supabase/.env` | `SUPABASE_AUTH_EXTERNAL_GOOGLE_*` | Login con Google |
| `supabase/functions/.env` | `INTERNAL_FUNCTIONS_SECRET` | Protege las funciones que llama la base |
| `supabase/functions/.env` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET` | Bot de Telegram |

## Seguridad

- **Row Level Security en todas las tablas:** cada usuario solo ve y modifica los datos de sus grupos.
- **Operaciones sensibles en funciones de la base:** crear o unirse a un grupo, subir versiones, bloquear, eliminar. Esas funciones validan permisos; el cliente no puede escribir directo en esas tablas.
- **Storage:** bucket privado y políticas por grupo según la ruta `groups/{group_id}/…`. Solo se sube a rutas reservadas con `begin_upload`, y solo se leen los objetos de versiones que el plan deja ver. Las descargas usan URLs firmadas de 60 segundos (15 minutos para reproducir video y audio en el visor).
- **Funciones auxiliares** (`nombre_de`, `is_member_of`, etc.) no se pueden llamar desde la API.
- **Fotos de perfil:** bucket `avatares` público (como las de Google), una carpeta por usuario; cada uno solo sube y borra en la suya, máximo 1 MB y solo JPG, PNG o WebP. La foto se fija con `set_avatar`, que verifica que sea de tu carpeta.
- **Dispositivos:** `mis_sesiones` y `cerrar_sesion` solo ven y cierran sesiones propias; la tabla `auth.sessions` no es accesible desde la app.
- **Códigos de invitación y de Telegram:** 10 caracteres con generador criptográfico. Los de 8 que ya existían siguen valiendo.
- **Avatar:** lo pone el registro con Google; no se cambia desde la app (una URL libre dejaba ver la IP de quien la mostraba).
- **En vivo:** los avisos van por canales privados de Realtime Broadcast (`grupo:{id}:tareas`, `usuario:{id}:grupos`, …) y la RLS de `realtime.messages` decide quién escucha cada uno. Los avisos no llevan datos: la app vuelve a leer con su RLS. No se usa `postgres_changes` porque Supabase no aplica la RLS a los borrados.
- **Edge Functions:** el webhook valida el `secret_token` de Telegram, y las funciones internas un secreto compartido guardado en Vault. Los secretos se comparan en tiempo constante y los nombres que se mandan al chat se escapan.

## Cómo funciona

### Archivos y versiones

Los archivos van a Supabase Storage (bucket privado `archivos`), nunca a la base. Cada versión es un objeto en `groups/{group_id}/files/{file_id}/v{n}`.

Subir un archivo son tres pasos:

1. `begin_upload` valida que seas del grupo, que el archivo no lo esté editando otra persona y que haya espacio, y te **reserva** la ruta (`pending_uploads`, 2 h).
2. La app sube los bytes a Storage en esa ruta. Storage solo acepta objetos en una ruta que reservaste vos.
3. `finish_upload` verifica la reserva y el objeto, toma el tamaño real desde Storage, controla el espacio del plan con ese tamaño y registra la versión. La carpeta y el nombre salen de la reserva.

El número de versión se asigna al terminar (última + 1), así una subida abandonada no deja huecos. Si otra persona terminó una versión mientras subías, la tuya se rechaza en vez de pisarla.

El mismo nombre (sin importar mayúsculas) en la misma carpeta crea una versión nueva. Restaurar reutiliza el objeto viejo, así que no ocupa espacio extra. `groups.storage_used` se mantiene con triggers. Límite por archivo: 50 MB.

**Limpieza.** La Edge Function `storage-cleanup` borra una vez por día (`pg_cron`, 4:30) los objetos que ya no usa ninguna versión: los de grupos eliminados y los de subidas que se cortaron antes de terminar.

### Bloqueos

- **Bloquear:** `lock_file(file, minutos)` bloquea por el tiempo elegido: 2 h (por defecto), hasta la noche o 24 h como máximo. Se puede renovar.
- **Qué protege:** mientras está bloqueado, solo quien lo bloqueó puede subir versiones, renombrar, restaurar o eliminar el original. Lo controla la base.
- **Qué pueden hacer los demás:** subir sus cambios como copia (`Informe (copia de Juan).docx`) o pedirle que lo libere (`request_unlock`). A quien lo tiene le llega el aviso en cualquier pantalla, con un botón "Liberar".
- **Desbloquear:** subir una versión nueva lo desbloquea solo. `unlock_file` lo libera a mano, o lo fuerza si sos admin del grupo.
- **Vencimiento:** al vencer (`lock_until`) el bloqueo se ignora al instante, y un job de `pg_cron` (cada 15 min) lo limpia para que todos vean el cambio en vivo.

### Documentos

- Un documento es un archivo `.svdoc` (la extensión no se muestra) cuyas versiones son JSON en formato Delta (el de [Quill](https://pub.dev/packages/flutter_quill)), en Storage como cualquier archivo.
- **Editar** toma el bloqueo (2 h, se renueva solo mientras escribís). El autoguardado va a la tabla `documentos` con `guardar_documento`, que exige tener el archivo bloqueado; cada guardado avisa por el canal privado `grupo:{id}:documentos`.
- **Listo** sube el contenido como versión nueva (eso libera el bloqueo) y un trigger descarta el borrador.
- El borrador solo vale como "lo último" mientras su autor tenga el archivo bloqueado. Máximo 1 MB por borrador y 10 por persona.
- Word y PDF se arman en la app (`documentos/domain/docx.dart` y `pdf_export.dart`), sin servidores extra.

### Papelera, destacados, búsqueda, calendario y comentarios

- **Papelera:** `delete_file` marca `files.deleted_at` (borrado lógico). Lo que está en la papelera no se edita, ni se bloquea, ni se renombra (trigger `files_papelera_inmutable`), y su nombre queda libre (el índice único es parcial). `restaurar_archivo` lo devuelve (con "(2)" si el nombre está ocupado) y `eliminar_definitivo` lo borra; los objetos de Storage los borra la limpieza diaria, y mientras tanto nadie los puede leer. `pg_cron` vacía lo de más de 30 días.
- **Destacados y recientes:** tablas `destacados` y `vistos`, propias de cada usuario (RLS). `marcar_visto` guarda los últimos 50.
- **Búsqueda:** `buscar_archivos` corre con los permisos de quien busca y compara sin tildes (`unaccent`, con índice).
- **Calendario:** tareas con `due_date` + tabla `eventos` (parcial, entrega, clase, otro). Los edita o borra quien los creó o un admin.
- **Comentarios:** tabla `comentarios`; un trigger calcula las menciones (solo integrantes del grupo) y avisa por `usuario:{id}:menciones`. El hilo se actualiza por `grupo:{id}:comentarios`.

### Tareas, actividad y aportes

- **Tareas** (`tasks`): el responsable tiene que ser del grupo; `completed_at` lo maneja un trigger.
- **Actividad** (`activity`): la escriben solo los triggers: versiones, bloqueos, renombres, bajas, carpetas, integrantes, tareas, pedidos de liberación. El payload guarda los nombres, así el feed se lee bien aunque después se renombre o borre algo.
- **Aportes** (`group_contributions`): tareas completadas y versiones subidas por integrante. Cuenta también las versiones que el plan free no muestra.

### Bot de Telegram

Comandos: `/vincular CODIGO`, `/pendientes`, `/desvincular`, `/ayuda`.

- **Vincular:** en la app, el admin abre *Avisos por Telegram* y genera un código de un solo uso que vence a los 30 minutos. En el grupo de Telegram se manda `/vincular CODIGO`. No se usa el código de invitación: quien lo tuviera podría escuchar los avisos.
- **Avisos:** cada evento de actividad que interesa se encola en `telegram_outbox` (uno por chat vinculado). `telegram-send` arma el mensaje y lo envía. La base la despierta al instante con `pg_net`, y `pg_cron` reintenta cada minuto lo pendiente (hasta 5 intentos). Si echan al bot de un chat, ese chat se desvincula solo.
- **Recordatorios:** el día anterior a cada fecha límite, a las 10 (hora de Argentina).

**Crear el bot** (una vez): en Telegram, hablale a [@BotFather](https://t.me/BotFather) → `/newbot`. Te da el **token** y el **usuario**; el usuario (sin @) va en `app/.env` → `TELEGRAM_BOT_USERNAME`. Telegram necesita una URL pública para el webhook: en local se puede usar un túnel (por ejemplo `cloudflared tunnel --url http://localhost:54321`).

## Despliegue

**Supabase** (proyecto en supabase.com):

```bash
npx supabase link --project-ref <proyecto>
npx supabase db push                                  # migraciones
npx supabase secrets set --env-file supabase/functions/.env
npx supabase functions deploy telegram-webhook --no-verify-jwt
npx supabase functions deploy telegram-send --no-verify-jwt
npx supabase functions deploy storage-cleanup --no-verify-jwt
```

En el SQL Editor, guardá en Vault la URL base de las funciones y el mismo `INTERNAL_FUNCTIONS_SECRET`:

```sql
select vault.create_secret('https://<proyecto>.supabase.co/functions/v1', 'functions_base_url');
select vault.create_secret('<INTERNAL_FUNCTIONS_SECRET>', 'internal_functions_secret');
```

Registrá el webhook del bot:

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<proyecto>.supabase.co/functions/v1/telegram-webhook&secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```

En Auth → URL Configuration, agregá la URL de la web y `io.studyverse.app://login-callback`.

En Auth → Email Templates, cargá las plantillas de `supabase/templates/` (mandan el código con `{{ .Token }}`), y configurá un SMTP propio en Auth → SMTP Settings: el de Supabase solo manda unos pocos correos por hora.

**Web:** `flutter build web --dart-define-from-file=.env` genera `app/build/web`, para cualquier hosting estático.

**Android:** `flutter build apk --dart-define-from-file=.env` (o `appbundle` para Play Store).

## Preparado para el futuro

La estructura está lista, pero esto no está implementado:

- **Plan premium por grupo:** `groups.plan` y `profiles.plan`, con los límites en la tabla `plan_limits` (free: 500 MB y las últimas 3 versiones visibles; premium: más espacio, historial completo y reporte de aportes en PDF). Los límites se aplican en la base. En *Aportes* ya está el lugar del reporte PDF.
- **Mercado Pago:** el plan solo lo puede cambiar el backend (los clientes no tienen permiso de `UPDATE` sobre `plan`), listo para un webhook de pagos.
- **GitHub y WhatsApp:** la tabla `activity` y la cola de avisos sirven de base para otros canales, igual que Telegram.

## Limitaciones conocidas

- **Tamaño de archivo:** máximo 50 MB, y el archivo se lee entero en memoria antes de subirlo. La vista previa es para archivos de hasta 25 MB (los más grandes se descargan); las planillas muestran hasta 500 filas y 40 columnas, y los textos hasta 200.000 caracteres.
- **Documentos:** se editan de a una persona por vez (no hay edición simultánea con cursores, como en Google Docs). Al importar un .docx las tablas pasan como texto y las imágenes se omiten; las presentaciones se ven solo como texto.
- **Borradores sin terminar:** si alguien cierra la app sin tocar *Listo*, el bloqueo vence a las 2 h; mientras tanto los demás ven la última versión y esa persona recupera lo que escribió al volver a editar.
- **Arrastrar y soltar en la web:** se sueltan archivos, no carpetas.
- **Android:** compila y arranca, pero no está probado de punta a punta en un dispositivo.
- **Login con Google:** necesita credenciales propias de Google Cloud.
- **Antes de producción:** `config.toml` ya exige confirmar el email y contraseñas seguras, pero en el proyecto de supabase.com hay que configurarlo igual en el panel (Auth → Providers → Email y Password). Para Google, `skip_nonce_check = false` salvo que el login nativo de Android lo necesite.
- **Sesiones:** no vencen solas (como en Drive). Cerrar un dispositivo invalida su sesión de inmediato para renovarse, pero el token que ya tenía sigue valiendo hasta una hora.
