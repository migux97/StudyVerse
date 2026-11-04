import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../domain/file_item.dart';
import '../domain/files_repository.dart';
import 'file_actions.dart';
import 'file_icon.dart';
import 'files_providers.dart';

/// Historial de versiones en una hoja inferior (celular o menú del archivo).
class VersionHistorySheet extends StatelessWidget {
  const VersionHistorySheet({super.key, required this.archivo});
  final FileItem archivo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: FileIcon(kind: archivo.kind),
              title: Text(archivo.nombre, style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Historial de versiones'),
            ),
            const Divider(height: 1),
            Flexible(child: VersionList(archivo: archivo)),
          ],
        ),
      ),
    );
  }
}

/// Lista de versiones: quién, cuándo, tamaño y nota. Descargar o restaurar.
/// La usan la hoja de historial y el panel lateral en PC.
class VersionList extends ConsumerWidget {
  const VersionList({super.key, required this.archivo, this.compacta = false});
  final FileItem archivo;

  /// Para el panel lateral: menos padding.
  final bool compacta;

  Future<void> _restaurar(BuildContext context, WidgetRef ref, FileVersion v) async {
    final ok = await confirmar(
      context,
      titulo: '¿Restaurar la v${v.versionNumber}?',
      mensaje: 'Se crea una versión nueva igual a la v${v.versionNumber}. '
          'No se borra ninguna versión del historial.',
      accion: 'Restaurar',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(filesRepositoryProvider).restore(v.id);
      ref.invalidate(versionsProvider((groupId: archivo.groupId, fileId: archivo.id)));
      ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
      if (context.mounted) mostrarMensaje(context, 'Se restauró la v${v.versionNumber}');
    } on FilesFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final versiones = ref.watch(versionsProvider((groupId: archivo.groupId, fileId: archivo.id)));
    final ahora = DateTime.now();

    return versiones.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(e.toString())),
      data: (lista) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final v in lista)
            _VersionTile(
              version: v,
              // La actual es siempre la más nueva (también al restaurar),
              // y así se actualiza en vivo sin depender de [archivo].
              esActual: v.id == lista.first.id,
              ahora: ahora,
              compacta: compacta,
              onDescargar: () => abrirVersion(context, ref, v, archivo.nombre, descargar: true),
              onRestaurar: () => _restaurar(context, ref, v),
            ),
          // El plan free muestra solo las últimas versiones.
          if (lista.isNotEmpty && lista.last.versionNumber > 1)
            Padding(
              padding: EdgeInsets.fromLTRB(compacta ? 16 : 24, 12, compacta ? 16 : 24, 0),
              child: Text(
                'Con el plan gratis se ven las últimas ${lista.length} versiones. '
                'Las anteriores siguen guardadas.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.esActual,
    required this.ahora,
    required this.compacta,
    required this.onDescargar,
    required this.onRestaurar,
  });

  final FileVersion version;
  final bool esActual;
  final DateTime ahora;
  final bool compacta;
  final VoidCallback onDescargar;
  final VoidCallback onRestaurar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: compacta ? const EdgeInsets.symmetric(horizontal: 12) : null,
      dense: compacta,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: esActual ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        child: Text('v${version.versionNumber}',
            style: TextStyle(
                fontSize: 12,
                color: esActual ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)),
      ),
      title: Text(
        [
          version.uploaderNombre ?? 'Alguien',
          formatearFecha(version.createdAt, ahora),
          formatBytes(version.sizeBytes),
        ].join(' · '),
      ),
      subtitle: version.nota == null && !esActual
          ? null
          : Text([if (esActual) 'Versión actual', ?version.nota].join(' — ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Descargar',
          icon: const Icon(Icons.download_rounded),
          onPressed: onDescargar,
        ),
        if (!esActual)
          IconButton(
            tooltip: 'Restaurar esta versión',
            icon: const Icon(Icons.restore_rounded),
            onPressed: onRestaurar,
          ),
      ]),
    );
  }
}
