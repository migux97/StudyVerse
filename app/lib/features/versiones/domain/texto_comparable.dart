import 'dart:convert';
import 'dart:typed_data';

import '../../documentos/domain/delta.dart';
import '../../documentos/domain/docx.dart';
import '../../documentos/domain/documento.dart';
import '../../documentos/domain/lectores.dart';
import '../../files/domain/file_item.dart';
import 'comparar.dart';

/// Cómo se compara un tipo de archivo.
enum ModoComparacion {
  /// Se saca el texto y se compara línea por línea.
  texto,

  /// Se lee el texto del PDF (no se puede en otro hilo: lo hace la pantalla).
  pdf,

  /// Una imagen al lado de la otra, o una sobre otra con un deslizador.
  imagen,

  /// No hay forma de compararlo adentro de la app (video, zip, .doc viejo…).
  ninguno,
}

ModoComparacion modoComparacion(String nombre) {
  final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
  return switch (fileKindFor(nombre)) {
    FileKind.studyverse || FileKind.codigo || FileKind.texto => ModoComparacion.texto,
    FileKind.documento when ext == 'docx' => ModoComparacion.texto,
    FileKind.planilla when ext == 'xlsx' || ext == 'csv' => ModoComparacion.texto,
    FileKind.presentacion when ext == 'pptx' => ModoComparacion.texto,
    FileKind.pdf => ModoComparacion.pdf,
    FileKind.imagen when ext != 'heic' => ModoComparacion.imagen,
    _ => ModoComparacion.ninguno,
  };
}

/// El texto de una versión, listo para compararlo línea por línea: el de un
/// documento sin formato, una planilla fila por fila, una presentación
/// diapositiva por diapositiva. `null` si no se pudo leer.
String? textoComparable(Uint8List bytes, String nombre) {
  final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
  switch (fileKindFor(nombre)) {
    case FileKind.studyverse:
      return textoPlano(opsDeVersion(bytes));
    case FileKind.documento when ext == 'docx':
      final ops = importarDocx(bytes);
      return ops == null ? null : textoPlano(ops);
    case FileKind.planilla when ext == 'xlsx':
      final hojas = leerXlsx(bytes);
      if (hojas == null) return null;
      return [
        for (final h in hojas) ...[if (hojas.length > 1) '── Hoja: ${h.nombre} ──', for (final f in h.filas) _fila(f)],
      ].join('\n');
    case FileKind.presentacion when ext == 'pptx':
      final diapositivas = leerPptx(bytes);
      if (diapositivas == null) return null;
      return [
        for (var i = 0; i < diapositivas.length; i++) ...['── Diapositiva ${i + 1} ──', ...diapositivas[i]],
      ].join('\n');
    case FileKind.codigo || FileKind.texto || FileKind.planilla:
      // Texto plano (incluye .csv). Sin BOM.
      final sinBom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
          ? bytes.sublist(3)
          : bytes;
      return utf8.decode(sinBom, allowMalformed: true);
    default:
      return null;
  }
}

/// Una fila de planilla: las celdas separadas con " | ", sin las vacías del final.
String _fila(List<String> celdas) {
  var n = celdas.length;
  while (n > 0 && celdas[n - 1].trim().isEmpty) {
    n--;
  }
  return celdas.take(n).join(' | ');
}

/// Lo que se le pasa a otro hilo para comparar (y lo que devuelve).
typedef PedidoComparacion = ({Uint8List antes, Uint8List despues, String nombre});

/// Lee las dos versiones y las compara. `null` si alguna no se pudo leer.
/// Pensada para `compute` (otro hilo en Android; en la web corre igual).
Comparacion? compararVersiones(PedidoComparacion p) {
  final a = textoComparable(p.antes, p.nombre);
  final b = textoComparable(p.despues, p.nombre);
  if (a == null || b == null) return null;
  return compararTextos(a, b);
}
