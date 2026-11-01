import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/auth_layout.dart';
import '../domain/auth_repository.dart';
import 'auth_providers.dart';

class GoogleButton extends ConsumerWidget {
  const GoogleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
      label: const Text('Continuar con Google'),
      onPressed: () async {
        try {
          await ref.read(authRepositoryProvider).signInWithGoogle();
        } on AuthFailure catch (e) {
          if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
        }
      },
    );
  }
}
