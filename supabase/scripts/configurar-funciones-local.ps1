# Configura el bot de Telegram para el entorno LOCAL:
#   1. crea supabase/functions/.env con secretos aleatorios (si no existe),
#   2. guarda en Supabase Vault la URL de telegram-send y el secreto interno,
#      para que la base pueda despertar a la función.
#
# Uso (desde la raíz del repo, con `npx supabase start` corriendo):
#   ./supabase/scripts/configurar-telegram-local.ps1 -BotToken "123456:ABC..."
#   ./supabase/scripts/configurar-telegram-local.ps1 -ApiBase "http://host.docker.internal:8081"   # Telegram simulado
#
# No guarda nada en el repo: .env está en .gitignore y Vault vive en la base local.

param(
  [string]$BotToken = "",
  [string]$ApiBase = "",
  [string]$Contenedor = "supabase_db_tpdrive"
)

$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot "..\functions\.env"

function Nuevo-Secreto {
  -join ((1..40) | ForEach-Object { [char[]]'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789' | Get-Random })
}

# Lee el .env existente (si hay) para no cambiar secretos ya configurados.
$valores = [ordered]@{}
if (Test-Path $envFile) {
  foreach ($linea in Get-Content $envFile) {
    if ($linea -match '^\s*([A-Z_]+)=(.*)$') { $valores[$Matches[1]] = $Matches[2] }
  }
}
if (-not $valores['TELEGRAM_WEBHOOK_SECRET']) { $valores['TELEGRAM_WEBHOOK_SECRET'] = Nuevo-Secreto }
if (-not $valores['TELEGRAM_INTERNAL_SECRET']) { $valores['TELEGRAM_INTERNAL_SECRET'] = Nuevo-Secreto }
if ($BotToken) { $valores['TELEGRAM_BOT_TOKEN'] = $BotToken }
if (-not $valores['TELEGRAM_BOT_TOKEN']) { $valores['TELEGRAM_BOT_TOKEN'] = '' }
if ($ApiBase) { $valores['TELEGRAM_API_BASE'] = $ApiBase }

$contenido = ($valores.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
[IO.File]::WriteAllText((Resolve-Path (Split-Path $envFile)).Path + "\.env", "$contenido`n", (New-Object Text.UTF8Encoding $false))
Write-Host "OK  supabase/functions/.env"

# La base llega a las funciones por el puerto de la API en el host.
$url = "http://host.docker.internal:54321/functions/v1/telegram-send"
$secreto = $valores['TELEGRAM_INTERNAL_SECRET']
$sql = @"
do `$`$
declare i uuid;
begin
  select id into i from vault.secrets where name = 'telegram_send_url';
  if i is null then perform vault.create_secret('$url', 'telegram_send_url');
  else perform vault.update_secret(i, '$url'); end if;

  select id into i from vault.secrets where name = 'telegram_internal_secret';
  if i is null then perform vault.create_secret('$secreto', 'telegram_internal_secret');
  else perform vault.update_secret(i, '$secreto'); end if;
end
`$`$;
"@
$sql | docker exec -i $Contenedor psql -U postgres -q -v ON_ERROR_STOP=1
Write-Host "OK  secretos en Vault (telegram_send_url, telegram_internal_secret)"
Write-Host ""
Write-Host "Ahora: npx supabase functions serve --env-file supabase/functions/.env"
if (-not $valores['TELEGRAM_BOT_TOKEN']) { Write-Host "Falta el token del bot: volvé a correr con -BotToken" }
