import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/push/push.dart';
import 'core/errors.dart';
import 'core/theme/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En la web, que la URL refleje también las pantallas abiertas con push
  // (así recargar no te devuelve al inicio).
  GoRouter.optionURLReflectsImperativeAPIs = true;

  if (!Env.isConfigured) {
    runApp(const _ConfigFaltante());
    return;
  }

  await Supabase.initialize(
    url: Env.resolvedSupabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );

  // Notificaciones push (si Firebase está configurado).
  await Push.iniciar();

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Navegación privada u otro bloqueo: se sigue sin preferencias guardadas.
  }

  runApp(ProviderScope(
    retry: reintentoProviders,
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const StudyVerseApp(),
  ));
}

class _ConfigFaltante extends StatelessWidget {
  const _ConfigFaltante();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Falta la configuración de Supabase.\n'
                'Copiá app/.env.example a app/.env, completalo y corré:\n'
                'flutter run --dart-define-from-file=.env',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
