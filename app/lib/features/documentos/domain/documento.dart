import 'dart:convert';
import 'dart:typed_data';

import '../../../core/errors.dart';
import 'delta.dart';

class DocumentoFailure extends AppFailure {
  const DocumentoFailure(super.mensaje, {this.sinConexion = false});

  /// Falló la red (se reintenta); si no, el servidor lo rechazó (no se reintenta).
  final bool sinConexion;
}

/// Contenido de un documento de StudyVerse: el borrador que se está editando
/// (si hay) o la última versión guardada.
class ContenidoDocumento {
  const ContenidoDocumento({
    required this.ops,
    this.borradorDe,
    this.autorId,
    this.baseVersion,
    this.actualizado,
    this.recuperado = false,
  });
  final List<dynamic> ops;

  /// Quién escribió el borrador (null si es la versión guardada).
  final String? borradorDe;
  final String? autorId;

  /// Versión desde la que salió el borrador.
  final int? baseVersion;
  final DateTime? actualizado;

  /// Borrador propio que quedó sin terminar (se cerró la app o venció el bloqueo).
  final bool recuperado;

  bool get esBorrador => borradorDe != null;

  ContenidoDocumento comoRecuperado() => ContenidoDocumento(
        ops: ops,
        borradorDe: borradorDe,
        autorId: autorId,
        baseVersion: baseVersion,
        actualizado: actualizado,
        recuperado: true,
      );
}

/// Qué mostrar: el borrador vale como "lo último" mientras su autor tenga el
/// archivo bloqueado. Si no, se ve la versión guardada, salvo para el autor,
/// que recupera lo que no terminó (si nadie subió otra versión mientras tanto).
ContenidoDocumento? borradorVigente(
  ContenidoDocumento? borrador, {
  required String? bloqueadoPor,
  required bool bloqueoVigente,
  required String? miId,
  required int? versionActual,
}) {
  if (borrador == null) return null;
  if (bloqueoVigente && bloqueadoPor != null && bloqueadoPor == borrador.autorId) return borrador;
  if (miId != null && miId == borrador.autorId && borrador.baseVersion == versionActual) {
    return borrador.comoRecuperado();
  }
  return null;
}

/// Lee una versión guardada (JSON). Un archivo vacío o roto es un documento vacío.
List<dynamic> opsDeVersion(Uint8List bytes) {
  if (bytes.isEmpty) return [...deltaVacio];
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is List && json.isNotEmpty) return json;
    if (json is Map && json['ops'] is List) return json['ops'] as List;
  } catch (_) {}
  return [...deltaVacio];
}

Uint8List bytesDeOps(List<dynamic> ops) => Uint8List.fromList(utf8.encode(jsonEncode(ops)));

abstract interface class DocumentosRepository {
  /// El borrador en curso, si alguien lo está editando o lo dejó sin terminar.
  Future<ContenidoDocumento?> borrador(String fileId);

  /// Autoguardado (hay que tener el archivo bloqueado). Devuelve cuándo quedó guardado.
  Future<DateTime> guardar(String fileId, List<dynamic> ops);

  /// Emite el id del documento cada vez que cambia un borrador del grupo.
  Stream<String> cambios(String groupId);
}
