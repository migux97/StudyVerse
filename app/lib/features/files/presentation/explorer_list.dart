import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/file_item.dart';
import '../../visor/presentation/visor_screen.dart';
import 'file_actions.dart';
import 'file_icon.dart';
import 'files_providers.dart';

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
    this.seleccionadoId,
    this.onSeleccionar,
  });

  final List<Folder> carpetas;
  final List<FileItem> archivos;
  final String? miId;
  final bool soyAdmin;
  final void Function(Folder) onAbrirCarpeta;

  /// En PC con panel lateral: tocar un archivo lo elige en vez de abrirlo.
  final String? seleccionadoId;
  final void Function(FileItem)? onSeleccionar;

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
              hermanos: archivos,
              ancho: ancho,
              ahora: ahora,
              bloqueo: a.estadoBloqueo(miId, ahora),
              yaLoPedi: a.pedidoPor(miId),
              soyAdmin: soyAdmin,
              puedeEliminar: soyAdmin || a.createdBy == miId,
              seleccionado: a.id == seleccionadoId,
              onSeleccionar: onSeleccionar == null ? null : () => onSeleccionar!(a),
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

enum _AccionArchivo {
  abrir,
  descargar,
  destacar,
  bloquear,
  renovar,
  desbloquear,
  forzarDesbloqueo,
  pedir,
  subirCopia,
  nuevaVersion,
  historial,
  renombrar,
  eliminar,
}

class _ArchivoTile extends ConsumerWidget {
  const _ArchivoTile({
    required this.archivo,
    required this.hermanos,
    required this.ancho,
    required this.ahora,
    required this.bloqueo,
    required this.yaLoPedi,
    required this.soyAdmin,
    required this.puedeEliminar,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final FileItem archivo;
  final bool seleccionado;
  final VoidCallback? onSeleccionar;

  /// Los demás archivos de la carpeta (para elegir un nombre de copia libre).
  final List<FileItem> hermanos;
  final bool ancho;
  final DateTime ahora;
  final EstadoBloqueo bloqueo;
  final bool yaLoPedi;
  final bool soyAdmin;
  final bool puedeEliminar;

  void _accion(BuildContext context, WidgetRef ref, _AccionArchivo a) {
    final v = archivo.current!;
    switch (a) {
      case _AccionArchivo.abrir:
        abrirArchivo(context, archivo);
      case _AccionArchivo.descargar:
        abrirVersion(context, ref, v, archivo.nombre, descargar: true);
      case _AccionArchivo.destacar:
        alternarDestacado(context, ref, archivo);
      case _AccionArchivo.bloquear:
        bloquearArchivo(context, ref, archivo);
      case _AccionArchivo.renovar:
        bloquearArchivo(context, ref, archivo, renovar: true);
      case _AccionArchivo.desbloquear:
        desbloquearArchivo(context, ref, archivo, forzar: false);
      case _AccionArchivo.forzarDesbloqueo:
        desbloquearArchivo(context, ref, archivo, forzar: true);
      case _AccionArchivo.pedir:
        pedirLiberacion(context, ref, archivo);
      case _AccionArchivo.subirCopia:
        subirNuevaVersion(context, ref, archivo, comoCopia: true, existentes: hermanos);
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

    // Mientras otra persona lo edita no se puede pisar (versión, nombre, eliminar),
    // pero no hace falta esperar: se le pide o se suben los cambios como copia.
    final libreParaMi = bloqueo != EstadoBloqueo.deOtro;
    final editor = archivo.lockedByNombre ?? 'Otra persona';
    final quienesLoPiden = archivo.pedidos.map((p) => p.nombre ?? 'Alguien').toSet().join(', ');
    PopupMenuItem<_AccionArchivo> item(_AccionArchivo valor, IconData icono, String texto,
            {bool habilitado = true, String? detalle}) =>
        PopupMenuItem(
          value: valor,
          enabled: habilitado,
          child: ListTile(
            enabled: habilitado,
            leading: Icon(icono),
            title: Text(texto),
            subtitle: detalle != null
                ? Text(detalle)
                : habilitado
                    ? null
                    : Text('$editor lo está editando'),
          ),
        );

    final menu = PopupMenuButton<_AccionArchivo>(
      tooltip: 'Opciones',
      onSelected: (a) => _accion(context, ref, a),
      itemBuilder: (_) => [
        item(_AccionArchivo.abrir, Icons.visibility_outlined, 'Abrir'),
        item(_AccionArchivo.descargar, Icons.download_rounded, 'Descargar'),
        if (ref.read(idsDestacadosProvider).contains(archivo.id))
          item(_AccionArchivo.destacar, Icons.star_rounded, 'Quitar de destacados')
        else
          item(_AccionArchivo.destacar, Icons.star_outline_rounded, 'Agregar a destacados'),
        const PopupMenuDivider(),
        ...switch (bloqueo) {
          EstadoBloqueo.libre => [
              item(_AccionArchivo.bloquear, Icons.lock_outline, 'Estoy editando este archivo'),
              item(_AccionArchivo.nuevaVersion, Icons.upload_rounded, 'Subir nueva versión'),
            ],
          EstadoBloqueo.mio => [
              item(
                _AccionArchivo.desbloquear,
                Icons.lock_open_outlined,
                archivo.pedidos.isEmpty ? 'Ya terminé: desbloquear' : 'Liberar para $quienesLoPiden',
              ),
              item(_AccionArchivo.renovar, Icons.more_time_rounded, 'Necesito más tiempo',
                  detalle: formatearVencimiento(archivo.vencimientoBloqueo(ahora)!)),
              item(_AccionArchivo.nuevaVersion, Icons.upload_rounded, 'Subir nueva versión',
                  detalle: 'Lo desbloquea solo'),
            ],
          EstadoBloqueo.deOtro => [
              item(
                _AccionArchivo.pedir,
                Icons.front_hand_outlined,
                yaLoPedi ? 'Ya se lo pediste a $editor' : 'Pedirle a $editor que lo libere',
                habilitado: !yaLoPedi,
                detalle: yaLoPedi ? 'Te avisamos cuando lo libere' : null,
              ),
              item(_AccionArchivo.subirCopia, Icons.file_copy_outlined, 'Subir mis cambios como copia',
                  detalle: 'Sin pisar lo que está editando $editor'),
              if (soyAdmin)
                item(_AccionArchivo.forzarDesbloqueo, Icons.lock_open_outlined, 'Forzar desbloqueo'),
            ],
        },
        item(_AccionArchivo.historial, Icons.history_rounded, 'Historial (v${v.versionNumber})'),
        item(_AccionArchivo.renombrar, Icons.edit_outlined, 'Cambiar nombre', habilitado: libreParaMi),
        if (puedeEliminar)
          item(_AccionArchivo.eliminar, Icons.delete_outline, 'Mover a la papelera', habilitado: libreParaMi),
      ],
    );

    final nombre = Row(children: [
      Flexible(child: Text(archivo.visible, maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (ref.watch(idsDestacadosProvider).contains(archivo.id))
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(Icons.star_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      const SizedBox(width: 8),
      _VersionChip(numero: v.versionNumber),
      if (bloqueo != EstadoBloqueo.libre) ...[
        const SizedBox(width: 8),
        Flexible(
          child: _ChipBloqueo(
            texto: switch (bloqueo) {
              EstadoBloqueo.mio when archivo.pedidos.isNotEmpty =>
                'Lo estás editando · $quienesLoPiden lo necesita',
              EstadoBloqueo.mio => 'Lo estás editando',
              _ => '$editor está editando',
            },
            detalle: formatearVencimiento(archivo.vencimientoBloqueo(ahora)!),
            mio: bloqueo == EstadoBloqueo.mio,
          ),
        ),
      ],
    ]);

    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: _IconoConCandado(kind: archivo.kind, bloqueado: bloqueo != EstadoBloqueo.libre),
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
      selected: seleccionado,
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      // Con panel lateral, tocar elige (el panel tiene "Abrir"); sin panel, abre.
      onTap: onSeleccionar ?? () => _accion(context, ref, _AccionArchivo.abrir),
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

class _IconoConCandado extends StatelessWidget {
  const _IconoConCandado({required this.kind, required this.bloqueado});
  final FileKind kind;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    if (!bloqueado) return FileIcon(kind: kind);
    final scheme = Theme.of(context).colorScheme;
    return Stack(clipBehavior: Clip.none, children: [
      FileIcon(kind: kind),
      Positioned(
        right: -4,
        bottom: -4,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
          child: Icon(Icons.lock, size: 12, color: scheme.tertiary),
        ),
      ),
    ]);
  }
}

/// "🔒 Ana está editando", con el vencimiento en el tooltip.
class _ChipBloqueo extends StatelessWidget {
  const _ChipBloqueo({required this.texto, required this.detalle, required this.mio});
  final String texto;
  final String detalle;
  final bool mio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fondo = mio ? scheme.primaryContainer : scheme.tertiaryContainer;
    final frente = mio ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
    return Tooltip(
      message: 'Bloqueado: $detalle',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(8)),
        child: Text(
          '🔒 $texto',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: frente),
        ),
      ),
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
