import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuración leída de `--dart-define-from-file=.env`.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// URL pública de la versión web; se usa para armar los links de invitación.
  static const _webUrl = String.fromEnvironment('WEB_URL');
  static String get webUrl =>
      _webUrl.isNotEmpty ? _webUrl : (kIsWeb ? Uri.base.origin : 'http://localhost:3000');

  /// Usuario del bot de Telegram (sin @), p. ej. StudyVerseBot.
  static const telegramBot = String.fromEnvironment('TELEGRAM_BOT_USERNAME');

  /// Deep link al que vuelve el login con Google en Android.
  static const authRedirectMobile = 'io.studyverse.app://login-callback';

  // Firebase (notificaciones push). Opcional: sin esto, solo hay campanita.
  static const _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _firebaseAppIdWeb = String.fromEnvironment('FIREBASE_APP_ID_WEB');
  static const _firebaseAppIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const firebaseVapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  static String get _firebaseAppId => kIsWeb ? _firebaseAppIdWeb : _firebaseAppIdAndroid;

  static bool get firebaseConfigurado =>
      _firebaseApiKey.isNotEmpty &&
      _firebaseProjectId.isNotEmpty &&
      _firebaseSenderId.isNotEmpty &&
      _firebaseAppId.isNotEmpty &&
      (!kIsWeb || firebaseVapidKey.isNotEmpty);

  static FirebaseOptions get firebaseOptions => FirebaseOptions(
        apiKey: _firebaseApiKey,
        appId: _firebaseAppId,
        messagingSenderId: _firebaseSenderId,
        projectId: _firebaseProjectId,
      );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// URL de Supabase efectiva para la plataforma actual.
  static String get resolvedSupabaseUrl => resolveSupabaseUrl(
        supabaseUrl,
        isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );
}

/// El emulador de Android no ve el `localhost` de la PC: lo ve como 10.0.2.2.
String resolveSupabaseUrl(String url, {required bool isAndroid}) {
  if (!isAndroid) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
    return uri.replace(host: '10.0.2.2').toString();
  }
  return url;
}
