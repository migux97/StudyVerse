import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/errors.dart';

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

  runApp(const ProviderScope(retry: reintentoProviders, child: TpDriveApp()));
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
