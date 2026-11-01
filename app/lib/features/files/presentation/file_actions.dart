import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../domain/file_item.dart';
import '../domain/files_repository.dart';
import '../domain/folder_tree.dart';
import 'files_providers.dart';
import 'upload_dialog.dart';
import 'uploads_controller.dart';
import 'version_history_sheet.dart';

/// Ejecuta una acción mostrando el error (si hay) en un SnackBar.
Future<bool> _intentar(BuildContext context, Future<void> Function() accion) async {
  try {
    await accion();
    return true;
  } on FilesFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    return false;
  }
}

String? _validarNombre(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Poné un nombre';
  if (t.length > 120) return 'Máximo 120 caracteres';
  return null;
}

// Carpetas ---------------------------------------------------------------------

Future<void> nuevaCarpeta(BuildContext context, WidgetRef ref, String groupId, String? parentId) async {
  final nombre = await pedirTexto(
    context,
    titulo: 'Nueva carpeta',
    etiqueta: 'Nombre',
    accion: 'Crear',
    inicial: 'Carpeta sin nombre',
    validator: _validarNombre,
  );
  if (nombre == null || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).createFolder(groupId, parentId, nombre);
    ref.invalidate(foldersProvider(groupId));
  });
}

Future<void> renombrarCarpeta(BuildContext context, WidgetRef ref, Folder carpeta) async {
  final nombre = await pedirTexto(
    context,
    titulo: 'Cambiar nombre',
    etiqueta: 'Nombre',
    accion: 'Guardar',
    inicial: carpeta.nombre,
    validator: _validarNombre,
  );
  if (nombre == null || nombre == carpeta.nombre || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).renameFolder(carpeta.id, nombre);
    ref.invalidate(foldersProvider(carpeta.groupId));
  });
}

Future<void> eliminarCarpeta(BuildContext context, WidgetRef ref, Folder carpeta) async {
  final ok = await confirmar(
    context,
    titulo: '¿Eliminar "${carpeta.nombre}"?',
    mensaje: 'Solo se pueden eliminar carpetas vacías.',
    accion: 'Eliminar',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).deleteFolder(carpeta.id);
    ref.invalidate(foldersProvider(carpeta.groupId));
  });
}

// Subir ------------------------------------------------------------------------

/// Abre el selector de archivos; si falla (permisos, archivo ilegible) avisa.
Future<T?> _elegir<T>(BuildContext context, Future<T> Function() selector) async {
  try {
    return await selector();
  } catch (e) {
    if (context.mounted) mostrarMensaje(context, 'No se pudieron leer los archivos ($e)', error: true);
    return null;
  }
}

Subida _subidaDe(
  PlatformFile f, {
  String? nombre,
  String? fileId,
  String? versionDe,
  String? bloqueadoPor,
}) =>
    Subida(
      nombre: nombre ?? f.name,
      tamano: f.lengthSync(),
      leer: f.readAsBytes,
      fileId: fileId,
      versionDe: versionDe,
      bloqueadoPor: bloqueadoPor,
    );

/// Elige archivos y los sube a la carpeta. Los que ya existen (mismo nombre)
/// quedan como versión nueva.
Future<void> elegirYSubir(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  required String? folderId,
  required List<FileItem> existentes,
  required String? miId,
}) async {
  final elegidos = await _elegir(context, () => FilePicker.pickFiles(dialogTitle: 'Elegí los archivos para subir'));
  if (elegidos == null || elegidos.isEmpty || !context.mounted) return;

  final ahora = DateTime.now();
  final subidas = elegidos.map((f) {
    final existente = archivoConNombre(f.name, existentes);
    final deOtro = existente?.estadoBloqueo(miId, ahora) == EstadoBloqueo.deOtro;
    return _subidaDe(
      f,
      versionDe: existente?.nombre,
      bloqueadoPor: deOtro ? (existente!.lockedByNombre ?? 'Otra persona') : null,
    );
  }).toList();
  final nota = await confirmarSubida(context, subidas);
  if (nota == null || !context.mounted) return;

  await ref.read(uploadsProvider.notifier).subir(
        groupId: groupId,
        folderId: folderId,
        subidas: subidas.where((s) => s.impedimento == null).toList(),
        nota: nota.isEmpty ? null : nota,
      );
}

/// "Subir nueva versión": el archivo elegido reemplaza al actual, mantiene el nombre.
Future<void> subirNuevaVersion(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final elegido = await _elegir(
      context, () => FilePicker.pickFile(dialogTitle: 'Nueva versión de ${archivo.nombre}'));
  if (elegido == null || !context.mounted) return;

  final subida = _subidaDe(elegido, nombre: archivo.nombre, fileId: archivo.id, versionDe: archivo.nombre);
  final nota = await confirmarSubida(context, [subida]);
  if (nota == null || !context.mounted) return;

  await ref.read(uploadsProvider.notifier).subir(
        groupId: archivo.groupId,
        folderId: archivo.folderId,
        subidas: [if (subida.impedimento == null) subida],
        nota: nota.isEmpty ? null : nota,
      );
}

// Bloqueos -------------------------------------------------------------------------

/// "Estoy editando este archivo": lo bloquea y ofrece descargar la versión actual.
Future<void> bloquearArchivo(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final ok = await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).lock(archivo.id);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
  if (!ok || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      content: const Text(
        'Listo: el grupo ve que lo estás editando. Se desbloquea solo cuando '
        'subís la versión nueva (o a las 24 h).',
      ),
      action: SnackBarAction(
        label: 'Descargar',
        onPressed: () => abrirVersion(context, ref, archivo.current!, archivo.nombre, descargar: true),
      ),
    ));
}

/// Desbloquear el propio, o forzar uno ajeno (admin).
Future<void> desbloquearArchivo(
  BuildContext context,
  WidgetRef ref,
  FileItem archivo, {
  required bool forzar,
}) async {
  if (forzar) {
    final ok = await confirmar(
      context,
      titulo: '¿Forzar el desbloqueo?',
      mensaje: '${archivo.lockedByNombre ?? 'Otra persona'} está editando "${archivo.nombre}". '
          'Si lo desbloqueás, otros van a poder subir versiones y podría perder sus cambios.',
      accion: 'Desbloquear',
      peligroso: true,
    );
    if (!ok || !context.mounted) return;
  }
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).unlock(archivo.id);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
}

// Abrir / descargar ---------------------------------------------------------------

Future<void> abrirVersion(
  BuildContext context,
  WidgetRef ref,
  FileVersion version,
  String nombre, {
  required bool descargar,
}) =>
    _intentar(context, () async {
      final url = await ref
          .read(filesRepositoryProvider)
          .downloadUrl(version, nombre, descargar: descargar);
      // Descargar: en la misma pestaña (el navegador baja el archivo sin salir
      // de la app). Abrir: en una pestaña nueva.
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: descargar ? '_self' : '_blank',
      );
      if (!ok) throw const FilesFailure('No se pudo abrir el archivo');
    });

// Historial / renombrar / eliminar ------------------------------------------------

Future<void> verHistorial(BuildContext context, FileItem archivo) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => VersionHistorySheet(archivo: archivo),
    );

Future<void> renombrarArchivo(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final nombre = await pedirTexto(
    context,
    titulo: 'Cambiar nombre',
    etiqueta: 'Nombre',
    accion: 'Guardar',
    inicial: archivo.nombre,
    seleccionarSinExtension: true,
    validator: (v) {
      final t = v?.trim() ?? '';
      if (t.isEmpty) return 'Poné un nombre';
      if (t.length > 255) return 'Máximo 255 caracteres';
      return null;
    },
  );
  if (nombre == null || nombre == archivo.nombre || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).rename(archivo.id, nombre);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
}

Future<void> eliminarArchivo(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final ok = await confirmar(
    context,
    titulo: '¿Eliminar "${archivo.nombre}"?',
    mensaje: 'Se elimina con todas sus versiones, para todo el grupo. No se puede deshacer.',
    accion: 'Eliminar',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).delete(archivo.id);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
}
