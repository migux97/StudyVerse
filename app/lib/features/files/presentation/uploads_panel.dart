import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'uploads_controller.dart';

/// Panel abajo de todo con el estado de las subidas.
class UploadsPanel extends ConsumerWidget {
  const UploadsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subidas = ref.watch(uploadsProvider);
    if (subidas.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final enCurso = subidas.where((s) => s.estado == EstadoSubida.subiendo || s.estado == EstadoSubida.pendiente).length;
    final errores = subidas.where((s) => s.estado == EstadoSubida.error).length;
    final titulo = enCurso > 0
        ? 'Subiendo ${subidas.length - enCurso + 1} de ${subidas.length}…'
        : errores > 0
            ? '$errores ${errores == 1 ? 'archivo no se pudo subir' : 'archivos no se pudieron subir'}'
            : subidas.length == 1
                ? 'Archivo subido'
                : '${subidas.length} archivos subidos';

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: Text(titulo, style: theme.textTheme.titleSmall),
                trailing: enCurso > 0
                    ? const SizedBox.square(
                        dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close),
                        onPressed: ref.read(uploadsProvider.notifier).limpiar,
                      ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in subidas)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: switch (s.estado) {
                          EstadoSubida.pendiente => const Icon(Icons.schedule, size: 20),
                          EstadoSubida.subiendo => const SizedBox.square(
                              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          EstadoSubida.lista =>
                            Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary),
                          EstadoSubida.error =>
                            Icon(Icons.error, size: 20, color: theme.colorScheme.error),
                        },
                        title: Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: s.error == null ? null : Text(s.error!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
