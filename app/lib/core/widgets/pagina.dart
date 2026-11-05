import 'package:flutter/material.dart';

/// Cuando no hay vista previa (o falla): explica y ofrece descargar.
class SinVista extends StatelessWidget {
  const SinVista({super.key, required this.motivo, this.icono = Icons.visibility_off_outlined, this.accion});
  final String motivo;
  final IconData icono;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(motivo, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (accion != null) ...[const SizedBox(height: 20), accion!],
        ]),
      ),
    );
  }
}

/// Hoja de papel centrada (en pantallas anchas) donde va el documento.
/// Ocupa al menos el alto de la pantalla y, al tocar el espacio en blanco,
/// llama a [alTocarFondo] (para poner el cursor, como en Docs).
class PaginaDocumento extends StatelessWidget {
  const PaginaDocumento({super.key, required this.child, this.alTocarFondo, this.scrollController});
  final Widget child;
  final VoidCallback? alTocarFondo;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    return LayoutBuilder(
      builder: (context, c) => ColoredBox(
        color: ancho ? scheme.surfaceContainer : scheme.surface,
        child: SingleChildScrollView(
          controller: scrollController,
          padding: ancho ? const EdgeInsets.symmetric(vertical: 24) : EdgeInsets.zero,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 816),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: alTocarFondo,
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(minHeight: c.maxHeight - (ancho ? 48 : 0)),
                  decoration: ancho
                      ? BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  padding: ancho ? const EdgeInsets.fromLTRB(72, 64, 72, 96) : const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
