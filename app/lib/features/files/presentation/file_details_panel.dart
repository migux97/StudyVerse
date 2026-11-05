import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../versiones/presentation/historial_screen.dart';
import '../domain/file_item.dart';
import '../../visor/presentation/visor_screen.dart';
import '../../groups/presentation/groups_providers.dart';
import 'file_actions.dart';
import 'file_icon.dart';

/// Panel lateral del explorador en PC: detalles del archivo elegido, acciones
/// principales y su historial de versiones.
class FileDetailsPanel extends ConsumerWidget {
  const FileDetailsPanel({super.key, required this.archivo, required this.miId, required this.onCerrar});

  /// null = no hay nada elegido.
  final FileItem? archivo;
  final String? miId;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final a = archivo;
    if (a == null || a.current == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.touch_app_outlined, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Elegí un archivo para ver sus detalles y versiones',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
      );
    }

    final v = a.current!;
    final ahora = DateTime.now();
    final bloqueo = a.estadoBloqueo(miId, ahora);
    final secundario = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget dato(String etiqueta, String valor) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(etiqueta, style: secundario)),
            Expanded(child: Text(valor, style: theme.textTheme.bodyMedium)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          FileIcon(kind: a.kind, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(a.visible, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
          IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: onCerrar),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          dato('Versión', 'v${v.versionNumber}'),
          dato('Subida por', v.uploaderNombre ?? 'Alguien'),
          dato('Modificado', formatearFecha(v.createdAt, ahora)),
          dato('Tamaño', formatBytes(v.sizeBytes)),
          if (bloqueo != EstadoBloqueo.libre)
            dato(
              'Editando',
              '${bloqueo == EstadoBloqueo.mio ? 'Vos' : a.lockedByNombre ?? 'Otra persona'} · '
                  '${formatearVencimiento(a.vencimientoBloqueo(ahora)!)}',
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Abrir'),
              onPressed: () => abrirArchivo(context, a),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Descargar'),
              onPressed: () => abrirVersion(context, ref, v, a.nombre, descargar: true),
            ),
            if (bloqueo == EstadoBloqueo.libre && !ref.watch(soloLecturaProvider(a.groupId)))
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Estoy editando'),
                onPressed: () => bloquearArchivo(context, ref, a),
              ),
          ]),
        ]),
      ),
      const Divider(height: 24),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(children: [
          Expanded(child: Text('Versiones', style: theme.textTheme.titleSmall)),
          TextButton(onPressed: () => verHistorial(context, a), child: const Text('Ver todo')),
        ]),
      ),
      Expanded(child: ListaVersiones(archivo: a, compacta: true)),
    ]);
  }
}
