import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/files_repository.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/files_providers.dart';
import '../domain/historial.dart';

/// Historial de versiones a pantalla completa: las guardadas arriba, y el
/// resto por día, con espacio para leer quién cambió qué.
class HistorialScreen extends ConsumerWidget {
  const HistorialScreen({super.key, required this.groupId, required this.fileId});
  final String groupId;
  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivo = ref.watch(fileProvider((groupId: groupId, fileId: fileId)));
    final versiones = ref.watch(versionsProvider((groupId: groupId, fileId: fileId)));
    final puedeComparar = (versiones.value?.length ?? 0) > 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de versiones'),
        bottom: archivo.hasValue
            ? PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    archivo.requireValue.visible,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
            : null,
        actions: [
          if (puedeComparar)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Comparar'),
                onPressed: () => context.push(Routes.comparar(groupId, fileId)),
              ),
            ),
        ],
      ),
      body: switch (archivo) {
        AsyncValue(value: final FileItem a) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListaVersiones(archivo: a),
          ),
        ),
        AsyncValue(hasError: true) => const Center(child: Text('Ese archivo ya no existe o no tenés acceso')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Las versiones agrupadas por día, con las guardadas aparte. En [compacta]
/// (panel lateral) va más apretada y sin la sección de guardadas.
class ListaVersiones extends ConsumerWidget {
  const ListaVersiones({super.key, required this.archivo, this.compacta = false});
  final FileItem archivo;
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final estado = ref.watch(versionsProvider((groupId: archivo.groupId, fileId: archivo.id)));
    final ahora = DateTime.now();

    return estado.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(e is FilesFailure ? e.mensaje : 'Algo salió mal. Probá de nuevo'),
      ),
      data: (lista) {
        final actual = lista.firstOrNull;
        final guardadas = lista.where((v) => v.guardada).toList();
        // Faltan versiones en la lista: el plan oculta las más viejas.
        final ocultas = lista.isNotEmpty && lista.length < lista.first.versionNumber;
        final pad = EdgeInsets.symmetric(horizontal: compacta ? 12 : 16);

        Widget titulo(String t, {IconData? icono}) => Padding(
          padding: pad.copyWith(top: compacta ? 12 : 20, bottom: 4),
          child: Row(
            children: [
              if (icono != null) ...[Icon(icono, size: 18, color: theme.colorScheme.primary), const SizedBox(width: 6)],
              Text(
                t,
                style: (compacta ? theme.textTheme.labelLarge : theme.textTheme.titleSmall)?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

        Widget tile(FileVersion v) => _VersionTile(
          archivo: archivo,
          version: v,
          versiones: lista,
          esActual: v.id == actual?.id,
          compacta: compacta,
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (!compacta && guardadas.isNotEmpty) ...[
              titulo('Guardadas', icono: Icons.bookmark_rounded),
              for (final v in guardadas) tile(v),
              const Divider(height: 24),
            ],
            for (final dia in agruparPorDia(lista, ahora)) ...[
              titulo(dia.titulo),
              for (final v in dia.versiones) tile(v),
            ],
            if (ocultas)
              Padding(
                padding: pad.copyWith(top: 16),
                child: Text(
                  'Con el plan gratis se ven las últimas versiones y las que guardes. Las anteriores siguen guardadas.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _Accion { abrir, comparar, compararCon, guardar, renombrar, quitar, descargar, restaurar }

class _VersionTile extends ConsumerWidget {
  const _VersionTile({
    required this.archivo,
    required this.version,
    required this.versiones,
    required this.esActual,
    required this.compacta,
  });

  final FileItem archivo;
  final FileVersion version;
  final List<FileVersion> versiones;
  final bool esActual;
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = version;
    final anterior = anteriorA(versiones, v);
    final autor = v.uploaderNombre ?? 'Alguien';

    final insignias = <Widget>[
      if (esActual) _Insignia(texto: 'Actual', fondo: scheme.primaryContainer, color: scheme.onPrimaryContainer),
      if (v.guardada)
        _Insignia(
          texto: v.guardadaNombre!,
          icono: Icons.bookmark_rounded,
          fondo: scheme.tertiaryContainer,
          color: scheme.onTertiaryContainer,
        ),
    ];

    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compacta ? 12 : 16, vertical: compacta ? 6 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: compacta ? 15 : 18,
              backgroundColor: esActual ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              child: Text(
                'v${v.versionNumber}',
                style: TextStyle(
                  fontSize: compacta ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  color: esActual ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(width: compacta ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(autor, style: theme.textTheme.titleSmall),
                      ...insignias,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${horaCorta(v.createdAt)} · ${formatBytes(v.sizeBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (v.nota != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '"${v.nota}"',
                      maxLines: compacta ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (anterior != null && !compacta)
              IconButton(
                tooltip: 'Comparar con la v${anterior.versionNumber}',
                icon: const Icon(Icons.compare_arrows),
                onPressed: () => _comparar(context, anterior),
              ),
            PopupMenuButton<_Accion>(
              tooltip: 'Más opciones',
              onSelected: (a) => _accion(context, ref, a, anterior),
              itemBuilder: (_) => [
                if (archivo.kind != FileKind.studyverse) _item(_Accion.abrir, Icons.open_in_new, 'Abrir esta versión'),
                if (anterior != null) _item(_Accion.comparar, Icons.compare_arrows, 'Comparar con la anterior'),
                if (versiones.length > 1)
                  _item(_Accion.compararCon, Icons.difference_outlined, 'Comparar con la actual'),
                const PopupMenuDivider(),
                if (!v.guardada) _item(_Accion.guardar, Icons.bookmark_add_outlined, 'Guardar esta versión'),
                if (v.guardada) _item(_Accion.renombrar, Icons.edit_outlined, 'Cambiar el nombre'),
                if (v.guardada) _item(_Accion.quitar, Icons.bookmark_remove_outlined, 'Quitar de guardadas'),
                const PopupMenuDivider(),
                _item(_Accion.descargar, Icons.download_rounded, 'Descargar'),
                if (!esActual) _item(_Accion.restaurar, Icons.restore_rounded, 'Restaurar esta versión'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_Accion> _item(_Accion a, IconData icono, String texto) => PopupMenuItem(
    value: a,
    child: ListTile(leading: Icon(icono), title: Text(texto), contentPadding: EdgeInsets.zero),
  );

  void _comparar(BuildContext context, FileVersion antes, [FileVersion? despues]) =>
      context.push(Routes.comparar(archivo.groupId, archivo.id, antes: antes.id, despues: (despues ?? version).id));

  Future<void> _accion(BuildContext context, WidgetRef ref, _Accion a, FileVersion? anterior) async {
    final v = version;
    switch (a) {
      case _Accion.abrir:
        await abrirVersion(context, ref, v, archivo.nombre, descargar: false);
      case _Accion.comparar:
        if (anterior != null) _comparar(context, anterior);
      case _Accion.compararCon:
        final actual = versiones.first;
        if (actual.id == v.id) {
          if (anterior != null) _comparar(context, anterior);
        } else {
          _comparar(context, v, actual);
        }
      case _Accion.guardar || _Accion.renombrar:
        final nombre = await pedirTexto(
          context,
          titulo: a == _Accion.guardar ? 'Guardar la v${v.versionNumber}' : 'Cambiar el nombre',
          etiqueta: 'Nombre',
          accion: 'Guardar',
          inicial: v.guardadaNombre,
          ejemplo: 'Ej.: Entrega 1',
          ayuda: 'Las versiones guardadas quedan arriba en el historial y no se ocultan.',
          maximo: 60,
        );
        if (nombre == null || !context.mounted) return;
        await _guardar(
          context,
          ref,
          nombre,
          a == _Accion.guardar ? 'Guardaste la v${v.versionNumber}' : 'Nombre cambiado',
        );
      case _Accion.quitar:
        final ok = await confirmar(
          context,
          titulo: '¿Quitar "${v.guardadaNombre}" de guardadas?',
          mensaje: 'La versión no se borra. Con el plan gratis, si no está entre las últimas, deja de verse.',
          accion: 'Quitar',
        );
        if (!ok || !context.mounted) return;
        await _guardar(context, ref, null, 'Se quitó de guardadas');
      case _Accion.descargar:
        await abrirVersion(context, ref, v, archivo.nombre, descargar: true);
      case _Accion.restaurar:
        final ok = await confirmar(
          context,
          titulo: '¿Restaurar la v${v.versionNumber}?',
          mensaje:
              'Se crea una versión nueva igual a la v${v.versionNumber}. No se borra ninguna versión del historial.',
          accion: 'Restaurar',
        );
        if (!ok || !context.mounted) return;
        try {
          await ref.read(filesRepositoryProvider).restore(v.id);
          if (!context.mounted) return;
          _refrescar(ref);
          mostrarMensaje(context, 'Se restauró la v${v.versionNumber}');
        } on FilesFailure catch (e) {
          if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
        }
    }
  }

  Future<void> _guardar(BuildContext context, WidgetRef ref, String? nombre, String listo) async {
    try {
      await ref.read(filesRepositoryProvider).guardarVersion(version.id, nombre);
      if (!context.mounted) return;
      _refrescar(ref);
      mostrarMensaje(context, listo);
    } on FilesFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  void _refrescar(WidgetRef ref) {
    ref.invalidate(versionsProvider((groupId: archivo.groupId, fileId: archivo.id)));
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto, required this.fondo, required this.color, this.icono});
  final String texto;
  final Color fondo;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[Icon(icono, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
