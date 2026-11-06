# Genera app/web/firebase-config.js (para el service worker de los push) con
# los valores FIREBASE_* de app/.env. Correrlo una vez después de completar
# app/.env y antes de `flutter build web`.
#
# Uso (desde la raíz del repo):  ./app/tool/configurar-firebase-web.ps1

$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $raiz ".env"
if (-not (Test-Path $envFile)) { throw "No encontré app/.env" }

$v = @{}
foreach ($linea in Get-Content $envFile) {
  if ($linea -match '^\s*([A-Z_]+)=(.*)$') { $v[$Matches[1]] = $Matches[2].Trim() }
}
foreach ($clave in 'FIREBASE_API_KEY', 'FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_APP_ID_WEB') {
  if (-not $v[$clave]) { throw "Falta $clave en app/.env" }
}

$config = @"
// Generado por app/tool/configurar-firebase-web.ps1 desde app/.env. No editar ni subir.
self.firebaseConfig = {
  apiKey: '$($v['FIREBASE_API_KEY'])',
  projectId: '$($v['FIREBASE_PROJECT_ID'])',
  messagingSenderId: '$($v['FIREBASE_MESSAGING_SENDER_ID'])',
  appId: '$($v['FIREBASE_APP_ID_WEB'])',
};
"@
$destino = Join-Path $raiz "web\firebase-config.js"
[IO.File]::WriteAllText($destino, $config, (New-Object Text.UTF8Encoding $false))
Write-Host "OK  app/web/firebase-config.js"
