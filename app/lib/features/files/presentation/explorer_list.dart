import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/file_item.dart';
import 'file_actions.dart';
import 'file_icon.dart';

/// Lista de carpetas y archivos. En pantallas anchas muestra columnas
/// (autor, fecha, tamaño); en el celular, todo en el subtítulo.
class ExplorerList extends StatelessWidget {
  const ExplorerList({
    super.key,
    required this.carpetas,
    required this.archivos,
    required this.miId,
    required this.soyAdmin,
    required this.onAbrirCarpeta,
  });

  final List<Folder> carpetas;
  final List<FileItem> archivos;
  final String? miId;
  final bool soyAdmin;
  final void Function(Folder) onAbrirCarpeta;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    return LayoutBuilder(builder: (context, constraints) {
      final ancho = constraints.maxWidth >= 760;
      return ListView(
        padding: EdgeInsets.fromLTRB(ancho ? 24 : 8, 0, ancho ? 24 : 8, 112),
        children: [
          if (ancho) const _Encabezado(),
          for (final c in carpetas)
            _CarpetaTile(carpeta: c, ancho: ancho, onTap: () => onAbrirCarpeta(c)),
          for (final a in archivos)
            _ArchivoTile(
              archivo: a,
              ancho: ancho,
              ahora: ahora,
              puedeEliminar: soyAdmin || a.createdBy == miId,
            ),
        ],
      );
    });
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 112, 8),
      child: Row(children: [
        Expanded(flex: 5, child: Text('Nombre', style: estilo)),
        Expanded(flex: 2, child: Text('Última versión', style: estilo)),
        Expanded(flex: 2, child: Text('Modificado', style: estilo)),
        SizedBox(width: 80, child: Text('Tamaño', style: estilo, textAlign: TextAlign.right)),
      ]),
    );
  }
}

enum _AccionCarpeta { renombrar, eliminar }

class _CarpetaTile extends ConsumerWidget {
  const _CarpetaTile({required this.carpeta, required this.ancho, required this.onTap});
  final Folder carpeta;
  final bool ancho;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(Icons.folder_rounded, color: Theme.of(context).colorScheme.primary, size: 28),
      title: Text(carpeta.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      trailing: PopupMenuButton<_AccionCarpeta>(
        tooltip: 'Opciones',
        onSelected: (a) => switch (a) {
          _AccionCarpeta.renombrar => renombrarCarpeta(context, ref, carpeta),
          _AccionCarpeta.eliminar => eliminarCarpeta(context, ref, carpeta),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _AccionCarpeta.renombrar,
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre')),
          ),
          PopupMenuItem(
            value: _AccionCarpeta.eliminar,
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar')),
          ),
        ],
      ),
    );
  }
}

enum _AccionArchivo { abrir, descargar, nuevaVersion, historial, renombrar, eliminar }

class _ArchivoTile extends ConsumerWidget {
  const _ArchivoTile({
    required this.archivo,
    required this.ancho,
    required this.ahora,
    required this.puedeEliminar,
  });

  final FileItem archivo;
  final bool ancho;
  final DateTime ahora;
  final bool puedeEliminar;

  void _accion(BuildContext context, WidgetRef ref, _AccionArchivo a) {
    final v = archivo.current!;
    switch (a) {
      case _AccionArchivo.abrir:
        abrirVersion(context, ref, v, archivo.nombre, descargar: false);
      case _AccionArchivo.descargar:
        abrirVersion(context, ref, v, archivo.nombre, descargar: true);
      case _AccionArchivo.nuevaVersion:
        subirNuevaVersion(context, ref, archivo);
      case _AccionArchivo.historial:
        verHistorial(context, archivo);
      case _AccionArchivo.renombrar:
        renombrarArchivo(context, ref, archivo);
      case _AccionArchivo.eliminar:
        eliminarArchivo(context, ref, archivo);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final v = archivo.current!;
    final autor = v.uploaderNombre ?? 'Alguien';
    final fecha = formatearFecha(v.createdAt, ahora);
    final secundario = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final menu = PopupMenuButton<_AccionArchivo>(
      tooltip: 'Opciones',
      onSelected: (a) => _accion(context, ref, a),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _AccionArchivo.abrir,
          child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Abrir')),
        ),
        const PopupMenuItem(
          value: _AccionArchivo.descargar,
          child: ListTile(leading: Icon(Icons.download_rounded), title: Text('Descargar')),
        ),
        const PopupMenuItem(
          value: _AccionArchivo.nuevaVersion,
          child: ListTile(leading: Icon(Icons.upload_rounded), title: Text('Subir nueva versión')),
        ),
        PopupMenuItem(
          value: _AccionArchivo.historial,
          child: ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text('Historial (v${v.versionNumber})'),
          ),
        ),
        const PopupMenuItem(
          value: _AccionArchivo.renombrar,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Cambiar nombre')),
        ),
        if (puedeEliminar)
          const PopupMenuItem(
            value: _AccionArchivo.eliminar,
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar')),
          ),
      ],
    );

    final nombre = Row(children: [
      Flexible(child: Text(archivo.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      _VersionChip(numero: v.versionNumber),
    ]);

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: FileIcon(kind: archivo.kind),
      title: ancho
          ? Row(children: [
              Expanded(flex: 5, child: nombre),
              Expanded(flex: 2, child: Text(autor, style: secundario, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(fecha, style: secundario)),
              SizedBox(
                width: 80,
                child: Text(formatBytes(v.sizeBytes), style: secundario, textAlign: TextAlign.right),
              ),
            ])
          : nombre,
      subtitle: ancho ? null : Text('$autor · $fecha · ${formatBytes(v.sizeBytes)}'),
      onTap: () => _accion(context, ref, _AccionArchivo.abrir),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ancho)
          IconButton(
            tooltip: 'Descargar',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _accion(context, ref, _AccionArchivo.descargar),
          ),
        menu,
      ]),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.numero});
  final int numero;

  @override
  Widget build(BuildContext context) {
    if (numero == 1) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('v$numero', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }
}
