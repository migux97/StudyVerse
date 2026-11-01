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
    this.bloqueadoPor,
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

  /// Si el archivo existente lo está editando otra persona (no se puede subir).
  final String? bloqueadoPor;

  /// Por qué no se puede subir, o `null` si se puede.
  String? get impedimento {
    if ((tamano ?? 0) > maxBytesPorArchivo) {
      return 'Supera el máximo de ${maxBytesPorArchivo ~/ 1024 ~/ 1024} MB';
    }
    if (bloqueadoPor != null) return '$bloqueadoPor lo está editando';
    return null;
  }

  EstadoSubida estado;
  String? error;
}

/// Cola de subidas en curso. Se sube de a uno para no saturar la conexión.
class UploadsController extends Notifier<List<Subida>> {
  @override
  List<Subida> build() => const [];

  bool get ocupado => state.any((s) => s.estado == EstadoSubida.subiendo);

  Future<void> subir({
    required String groupId,
    required String? folderId,
    required List<Subida> subidas,
    String? nota,
  }) async {
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
        s.error = 'No se pudo subir. Intentá de nuevo';
        _marcar(s, EstadoSubida.error);
      }
    }
    ref.invalidate(filesProvider((groupId: groupId, folderId: folderId)));
  }

  void limpiar() => state = state.where((s) => s.estado == EstadoSubida.subiendo).toList();

  void _marcar(Subida s, EstadoSubida estado) {
    s.estado = estado;
    state = [...state];
  }
}

final uploadsProvider = NotifierProvider<UploadsController, List<Subida>>(UploadsController.new);
