import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/forms/validar.dart';
import '../../../core/web/ventana.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
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

final _validarNombre = Validar.nombreArchivo(vacio: 'Ingresá un nombre para la carpeta');

// Carpetas ---------------------------------------------------------------------

Future<void> nuevaCarpeta(BuildContext context, WidgetRef ref, String groupId, String? parentId) async {
  final nombre = await pedirTexto(
    context,
    titulo: 'Nueva carpeta',
    etiqueta: 'Nombre',
    accion: 'Crear',
    inicial: 'Carpeta sin nombre',
    maximo: 120,
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
    maximo: 120,
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
    if (context.mounted) mostrarMensaje(context, 'No pudimos leer esos archivos', error: true);
    return null;
  }
}

/// Un archivo del dispositivo, venga del selector o de arrastrar y soltar.
typedef ArchivoLocal = ({String nombre, int? tamano, Future<Uint8List> Function() leer});

ArchivoLocal _local(PlatformFile f) => (nombre: f.name, tamano: f.lengthSync(), leer: f.readAsBytes);

Subida _subidaDe(
  ArchivoLocal f, {
  String? nombre,
  String? fileId,
  String? versionDe,
  String? copiaPorque,
}) =>
    Subida(
      nombre: nombre ?? f.nombre,
      tamano: f.tamano,
      leer: f.leer,
      fileId: fileId,
      versionDe: versionDe,
      copiaPorque: copiaPorque,
    );

/// Mi nombre de pila para las copias. Espera el perfil: si la página se abrió
/// directo en una carpeta, puede que todavía no se haya cargado.
Future<String> _miNombre(WidgetRef ref) async {
  try {
    final perfil = await ref.read(currentProfileProvider.future);
    return perfil?.nombre.split(' ').first ?? 'otro integrante';
  } catch (_) {
    return 'otro integrante';
  }
}

/// Elige archivos y los sube a la carpeta (ver [subirArchivos]).
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
  await subirArchivos(context, ref,
      groupId: groupId,
      folderId: folderId,
      existentes: existentes,
      miId: miId,
      archivos: elegidos.map(_local).toList());
}

/// Sube archivos a la carpeta, previa confirmación. Los que ya existen (mismo
/// nombre) quedan como versión nueva; si otra persona edita el original, como copia.
Future<void> subirArchivos(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  required String? folderId,
  required List<FileItem> existentes,
  required String? miId,
  required List<ArchivoLocal> archivos,
}) async {
  if (archivos.isEmpty) return;
  final ahora = DateTime.now();
  final yo = await _miNombre(ref);
  if (!context.mounted) return;
  final subidas = archivos.map((f) {
    final existente = archivoConNombre(f.nombre, existentes);
    // Si otra persona lo está editando, no se espera: se sube como copia al lado.
    if (existente?.estadoBloqueo(miId, ahora) == EstadoBloqueo.deOtro) {
      return _subidaDe(
        f,
        nombre: nombreCopia(existente!.nombre, yo, existentes),
        copiaPorque: existente.lockedByNombre ?? 'Otra persona',
      );
    }
    return _subidaDe(f, versionDe: existente?.nombre);
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
/// Con [comoCopia] (otra persona lo está editando) se sube al lado, sin pisarlo.
Future<void> subirNuevaVersion(
  BuildContext context,
  WidgetRef ref,
  FileItem archivo, {
  bool comoCopia = false,
  List<FileItem> existentes = const [],
}) async {
  final elegido = await _elegir(
      context, () => FilePicker.pickFile(dialogTitle: 'Nueva versión de ${archivo.nombre}'));
  if (elegido == null || !context.mounted) return;

  final yo = comoCopia ? await _miNombre(ref) : '';
  if (!context.mounted) return;
  final subida = comoCopia
      ? _subidaDe(
          _local(elegido),
          nombre: nombreCopia(archivo.nombre, yo, existentes),
          copiaPorque: archivo.lockedByNombre ?? 'Otra persona',
        )
      : _subidaDe(_local(elegido), nombre: archivo.nombre, fileId: archivo.id, versionDe: archivo.nombre);
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

/// "Estoy editando este archivo": pregunta por cuánto tiempo, lo bloquea y
/// ofrece descargar la versión actual. Si ya era mío, renueva el tiempo.
Future<void> bloquearArchivo(BuildContext context, WidgetRef ref, FileItem archivo,
    {bool renovar = false}) async {
  final opcion = await _elegirDuracion(context, renovar: renovar);
  if (opcion == null || !context.mounted) return;

  final ok = await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).lock(archivo.id, minutosDeBloqueo(opcion, DateTime.now()));
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
  if (!ok || !context.mounted) return;
  if (renovar) return mostrarMensaje(context, 'Listo, tenés más tiempo');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(aviso(
      context,
      'El grupo ya ve que lo estás editando',
      accion: 'Descargar',
      alTocar: () => abrirVersion(context, ref, archivo.current!, archivo.nombre, descargar: true),
    ));
}

Future<DuracionBloqueo?> _elegirDuracion(BuildContext context, {required bool renovar}) {
  final ahora = DateTime.now();
  final noche = minutosDeBloqueo(DuracionBloqueo.hastaLaNoche, ahora);
  return showModalBottomSheet<DuracionBloqueo>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(renovar ? '¿Cuánto tiempo más?' : '¿Por cuánto tiempo lo vas a editar?'),
          subtitle: const Text('Mientras tanto, el resto puede subir sus cambios como copia o pedirte que lo liberes.'),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('2 horas'),
          subtitle: const Text('Recomendado'),
          onTap: () => Navigator.pop(ctx, DuracionBloqueo.dosHoras),
        ),
        // Si ya es tarde, "hasta esta noche" sería lo mismo que 2 horas.
        if (noche > 120)
          ListTile(
            leading: const Icon(Icons.nights_stay_outlined),
            title: const Text('Hasta esta noche'),
            subtitle: Text('Hasta las 23:59 (${noche ~/ 60} h)'),
            onTap: () => Navigator.pop(ctx, DuracionBloqueo.hastaLaNoche),
          ),
        ListTile(
          leading: const Icon(Icons.today_outlined),
          title: const Text('24 horas'),
          onTap: () => Navigator.pop(ctx, DuracionBloqueo.unDia),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// "Pedirle a Juan que lo libere": le llega un aviso en vivo.
Future<void> pedirLiberacion(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final ok = await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).requestUnlock(archivo.id);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
  if (ok && context.mounted) {
    mostrarMensaje(context,
        'Le avisamos a ${archivo.lockedByNombre ?? 'quien lo está editando'}');
  }
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
}) {
  // Abrir en la web: la pestaña se abre YA, en el clic, y después se le pone
  // la URL (si se abre después de esperar al servidor, Safari la bloquea).
  final pestana = descargar ? null : VentanaPendiente.abrir();
  return _intentar(context, () async {
    try {
      final url = await ref
          .read(filesRepositoryProvider)
          .downloadUrl(version, nombre, descargar: descargar);
      if (pestana != null) return pestana.ir(url);
      // Descargar: en la misma pestaña (el navegador baja el archivo sin salir
      // de la app). En Android: el navegador o la app que corresponda.
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: descargar ? '_self' : '_blank',
      );
      if (!ok) throw const FilesFailure('No se pudo abrir el archivo');
    } catch (_) {
      pestana?.cerrar();
      rethrow;
    }
  });
}

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
    maximo: 255,
    validator: Validar.nombreArchivo(max: 255),
  );
  if (nombre == null || nombre == archivo.nombre || !context.mounted) return;
  await _intentar(context, () async {
    await ref.read(filesRepositoryProvider).rename(archivo.id, nombre);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
  });
}

/// Lo manda a la papelera, sin preguntar (se puede deshacer, como en Drive).
Future<void> eliminarArchivo(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final repo = ref.read(filesRepositoryProvider);
  final ok = await _intentar(context, () async {
    await repo.delete(archivo.id);
    ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
    ref.invalidate(destacadosProvider);
    ref.invalidate(recientesProvider);
  });
  if (!ok || !context.mounted) return;
  mostrarMensaje(
    context,
    'Se movió «${archivo.visible}» a la papelera',
    accion: 'Deshacer',
    alTocar: () async {
      try {
        await repo.restaurar(archivo.id);
        ref.invalidate(filesProvider((groupId: archivo.groupId, folderId: archivo.folderId)));
      } on FilesFailure catch (e) {
        avisarEnLaApp(e.mensaje);
      }
    },
  );
}

Future<void> restaurarArchivo(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final ok = await _intentar(context, () => ref.read(filesRepositoryProvider).restaurar(archivo.id));
  if (!ok || !context.mounted) return;
  ref.invalidate(papeleraProvider(archivo.groupId));
  ref.invalidate(destacadosProvider);
  ref.invalidate(recientesProvider);
  mostrarMensaje(context, 'Restauramos «${archivo.visible}»');
}

Future<void> eliminarParaSiempre(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final ok = await confirmar(
    context,
    titulo: '¿Eliminar «${archivo.visible}» para siempre?',
    mensaje: 'Se borra con todas sus versiones, para todo el grupo. No se puede deshacer.',
    accion: 'Eliminar para siempre',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  final listo = await _intentar(context, () => ref.read(filesRepositoryProvider).eliminarDefinitivo(archivo.id));
  if (!listo || !context.mounted) return;
  ref.invalidate(papeleraProvider(archivo.groupId));
  mostrarMensaje(context, 'Se eliminó para siempre');
}

Future<void> alternarDestacado(BuildContext context, WidgetRef ref, FileItem archivo) async {
  final destacado = ref.read(idsDestacadosProvider).contains(archivo.id);
  final ok = await _intentar(
    context,
    () => ref.read(filesRepositoryProvider).destacar(archivo.id, destacado: !destacado),
  );
  if (!ok || !context.mounted) return;
  ref.invalidate(destacadosProvider);
  mostrarMensaje(context, destacado ? 'Lo sacamos de destacados' : 'Lo agregamos a destacados');
}
