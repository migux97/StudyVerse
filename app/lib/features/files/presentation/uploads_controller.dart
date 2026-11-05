import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/files_repository.dart';
import 'files_providers.dart';

enum EstadoSubida { pendiente, subiendo, lista, error }

/// Un archivo a subir. [leer] se llama recién al subirlo (no cargar todo en memoria antes).
class Subida {
  Subida({
    required this.nombre,
    required this.tamano,
    required this.leer,
    this.fileId,
    this.versionDe,
    this.copiaPorque,
    this.estado = EstadoSubida.pendiente,
    this.error,
  });

  final String nombre;
  final int? tamano;
  final Future<Uint8List> Function() leer;

  /// Si se sube como versión nueva de un archivo puntual ("Subir nueva versión").
  final String? fileId;

  /// Nombre del archivo existente del que va a ser versión nueva (para mostrarlo).
  final String? versionDe;

  /// Quién está editando el original, si esto se sube como copia para no pisarlo.
  final String? copiaPorque;

  /// Por qué no se puede subir, o `null` si se puede.
  String? get impedimento => (tamano ?? 0) > maxBytesPorArchivo
      ? 'Supera el máximo de ${maxBytesPorArchivo ~/ 1024 ~/ 1024} MB'
      : null;

  EstadoSubida estado;
  String? error;
}

/// Cola de subidas en curso. Se sube de a uno para no saturar la conexión.
class UploadsController extends Notifier<List<Subida>> {
  /// Cuánto queda a la vista "Archivo subido" antes de irse solo, como en Drive.
  static const ocultarDespues = Duration(seconds: 5);

  Timer? _ocultar;

  @override
  List<Subida> build() {
    ref.onDispose(() => _ocultar?.cancel());
    return const [];
  }

  bool get ocupado => state.any((s) => s.estado == EstadoSubida.subiendo);

  Future<void> subir({
    required String groupId,
    required String? folderId,
    required List<Subida> subidas,
    String? nota,
  }) async {
    _ocultar?.cancel();
    state = [...state.where((s) => s.estado == EstadoSubida.subiendo), ...subidas];
    final repo = ref.read(filesRepositoryProvider);

    for (final s in subidas) {
      _marcar(s, EstadoSubida.subiendo);
      try {
        await repo.upload(
          groupId: groupId,
          folderId: folderId,
          nombre: s.nombre,
          bytes: await s.leer(),
          fileId: s.fileId,
          nota: nota,
        );
        _marcar(s, EstadoSubida.lista);
      } on FilesFailure catch (e) {
        s.error = e.mensaje;
        _marcar(s, EstadoSubida.error);
      } catch (_) {
        s.error = 'No se pudo subir';
        _marcar(s, EstadoSubida.error);
      }
    }
    ref.invalidate(filesProvider((groupId: groupId, folderId: folderId)));
    _programarOcultar();
  }

  /// Si terminó todo bien, el aviso se va solo. Los errores quedan hasta que
  /// se cierran, para que se puedan leer.
  void _programarOcultar() {
    _ocultar?.cancel();
    if (state.isEmpty || state.any((s) => s.estado != EstadoSubida.lista)) return;
    _ocultar = Timer(ocultarDespues, () {
      if (state.every((s) => s.estado == EstadoSubida.lista)) state = const [];
    });
  }

  void limpiar() {
    _ocultar?.cancel();
    state = state.where((s) => s.estado == EstadoSubida.subiendo).toList();
  }

  void _marcar(Subida s, EstadoSubida estado) {
    s.estado = estado;
    state = [...state];
  }
}

final uploadsProvider = NotifierProvider<UploadsController, List<Subida>>(UploadsController.new);
