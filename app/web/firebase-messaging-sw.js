// Service worker de las notificaciones push en la web (Firebase Cloud
// Messaging). Muestra los push con la app cerrada; tocarlos abre la pantalla
// (el enlace viene en webpush.fcm_options.link).
//
// La configuración sale de firebase-config.js, que genera
// app/tool/configurar-firebase-web.ps1 a partir de app/.env (no se sube al
// repo). Sin ese archivo, no hace nada.
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

try {
  importScripts('firebase-config.js');
} catch (_) {
  // Sin configuración: push desactivado.
}

if (self.firebaseConfig) {
  firebase.initializeApp(self.firebaseConfig);
  firebase.messaging();
}
