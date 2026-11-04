import 'package:flutter/material.dart';

export 'avisos.dart';

/// Marca de StudyVerse: ícono y nombre.
class LogoStudyVerse extends StatelessWidget {
  const LogoStudyVerse({super.key, this.tamano = 28});
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tamano * 1.4,
          height: tamano * 1.4,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(tamano * 0.4),
          ),
          child: Icon(Icons.auto_stories_rounded, size: tamano * 0.85, color: scheme.primary),
        ),
        SizedBox(width: tamano * 0.4),
        Text(
          'StudyVerse',
          style: TextStyle(
            fontSize: tamano * 0.8,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

/// Contenedor centrado y angosto para las pantallas de acceso. En pantallas
/// anchas va en una tarjeta, como el login de Google.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.child,
    this.alVolver,
  });

  final String titulo;
  final String? subtitulo;
  final Widget child;

  /// Si está, muestra la flecha para volver.
  final VoidCallback? alVolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ancho = MediaQuery.sizeOf(context).width >= 600;

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: LogoStudyVerse()),
        const SizedBox(height: 28),
        Text(titulo, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        if (subtitulo != null) ...[
          const SizedBox(height: 8),
          Text(subtitulo!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 28),
        child,
      ],
    );

    return Scaffold(
      backgroundColor: ancho ? scheme.surfaceContainerLow : scheme.surface,
      appBar: alVolver == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: BackButton(onPressed: alVolver),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: ancho ? 24 : 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: ancho
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(36, 40, 36, 32),
                        child: contenido,
                      ),
                    )
                  : contenido,
            ),
          ),
        ),
      ),
    );
  }
}
