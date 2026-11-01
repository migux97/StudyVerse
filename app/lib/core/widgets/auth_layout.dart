import 'package:flutter/material.dart';

/// Contenedor centrado y angosto para las pantallas de acceso.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.titulo, this.subtitulo, required this.child});

  final String titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.folder_shared_rounded, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(titulo,
                      textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  if (subtitulo != null) ...[
                    const SizedBox(height: 8),
                    Text(subtitulo!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 32),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void mostrarMensaje(BuildContext context, String mensaje, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: error ? scheme.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}
