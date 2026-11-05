/// Lectura de documentos en formato Delta (el de Quill): una lista de
/// operaciones `{"insert": "texto", "attributes": {...}}`. Los atributos de
/// párrafo (título, lista, alineación) van en el `"\n"` que cierra la línea.
library;

/// Documento vacío (Quill siempre termina con un salto de línea).
const deltaVacio = [
  {'insert': '\n'},
];

/// Un pedazo de texto con el mismo formato (negrita, cursiva…).
class Tramo {
  const Tramo(this.texto, [this.estilo = const {}]);
  final String texto;
  final Map<String, dynamic> estilo;

  bool get negrita => estilo['bold'] == true;
  bool get cursiva => estilo['italic'] == true;
  bool get subrayado => estilo['underline'] == true;
  bool get tachado => estilo['strike'] == true;

  /// Color en "#rrggbb", si tiene.
  String? get color => estilo['color'] as String?;
  String? get fondo => estilo['background'] as String?;
  String? get link => estilo['link'] as String?;
}

/// Una línea (párrafo) con sus tramos y su formato de párrafo.
class Linea {
  const Linea(this.tramos, [this.bloque = const {}]);
  final List<Tramo> tramos;
  final Map<String, dynamic> bloque;

  String get texto => tramos.map((t) => t.texto).join();

  /// 1, 2 o 3 si es un título.
  int? get titulo => bloque['header'] as int?;

  /// 'bullet', 'ordered', 'checked' o 'unchecked'.
  String? get lista => bloque['list'] as String?;

  /// 'center', 'right' o 'justify'.
  String? get alineacion => bloque['align'] as String?;
  bool get cita => bloque['blockquote'] == true;
  int get sangria => (bloque['indent'] as int?) ?? 0;
}

/// Parte las operaciones en líneas. Ignora lo que no es texto (imágenes).
List<Linea> lineasDe(List<dynamic> ops) {
  final lineas = <Linea>[];
  var actual = <Tramo>[];
  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is! String) continue;
    final estilo = Map<String, dynamic>.from((op['attributes'] as Map?) ?? const {});
    final partes = insert.split('\n');
    for (var i = 0; i < partes.length; i++) {
      if (partes[i].isNotEmpty) actual.add(Tramo(partes[i], estilo));
      if (i < partes.length - 1) {
        // El salto de línea lleva el formato del párrafo.
        lineas.add(Linea(actual, estilo));
        actual = <Tramo>[];
      }
    }
  }
  if (actual.isNotEmpty) lineas.add(Linea(actual));
  return lineas;
}

/// Arma las operaciones a partir de líneas (lo inverso de [lineasDe]).
List<Map<String, dynamic>> opsDe(List<Linea> lineas) {
  final ops = <Map<String, dynamic>>[];
  for (final l in lineas) {
    for (final t in l.tramos) {
      if (t.texto.isEmpty) continue;
      ops.add({'insert': t.texto, if (t.estilo.isNotEmpty) 'attributes': t.estilo});
    }
    ops.add({'insert': '\n', if (l.bloque.isNotEmpty) 'attributes': l.bloque});
  }
  return ops.isEmpty ? [...deltaVacio] : ops;
}

/// Texto plano del documento (para buscar o previsualizar).
String textoPlano(List<dynamic> ops) => lineasDe(ops).map((l) => l.texto).join('\n');
