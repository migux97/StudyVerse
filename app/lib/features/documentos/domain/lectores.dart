import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Una hoja de planilla para mostrar como tabla.
class Hoja {
  const Hoja(this.nombre, this.filas);
  final String nombre;
  final List<List<String>> filas;

  int get columnas => filas.fold(0, (m, f) => f.length > m ? f.length : m);
}

/// Límites para que una planilla enorme no trabe la pantalla.
const maxFilas = 500;
const maxColumnas = 40;
const maxDiapositivas = 300;

/// Tope de lo que se descomprime de cada parte de un .docx/.xlsx/.pptx: un
/// archivo armado para "explotar" al descomprimirse no cuelga la app.
const maxBytesDescomprimidos = 20 * 1024 * 1024;

/// Contenido de una parte del zip, o null si no está o es demasiado grande.
String? leerParte(Archive zip, String nombre) {
  final f = zip.findFile(nombre);
  if (f == null || f.size > maxBytesDescomprimidos) return null;
  try {
    final bytes = f.content as List<int>;
    if (bytes.length > maxBytesDescomprimidos) return null;
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Lee un .xlsx (valores ya calculados, no fórmulas). `null` si no se puede.
List<Hoja>? leerXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  XmlDocument? xml(String nombre) {
    final texto = leerParte(zip, nombre);
    if (texto == null) return null;
    try {
      return XmlDocument.parse(texto);
    } catch (_) {
      return null;
    }
  }

  final libro = xml('xl/workbook.xml');
  if (libro == null) return null;
  final compartidos = [
    for (final si in xml('xl/sharedStrings.xml')?.findAllElements('si') ?? const <XmlElement>[])
      si.findAllElements('t').map((t) => t.innerText).join(),
  ];
  final destinos = {
    for (final r in xml('xl/_rels/workbook.xml.rels')?.findAllElements('Relationship') ?? const <XmlElement>[])
      r.getAttribute('Id'): r.getAttribute('Target'),
  };

  final hojas = <Hoja>[];
  for (final s in libro.findAllElements('sheet')) {
    var destino = destinos[s.getAttribute('r:id')] ?? '';
    destino = destino.startsWith('/') ? destino.substring(1) : 'xl/$destino';
    final hoja = xml(destino);
    if (hoja == null) continue;
    final filas = <List<String>>[];
    for (final row in hoja.findAllElements('row')) {
      if (filas.length >= maxFilas) break;
      final r = (int.tryParse(row.getAttribute('r') ?? '') ?? filas.length + 1) - 1;
      while (filas.length < r && filas.length < maxFilas) {
        filas.add(const []);
      }
      final fila = <String>[];
      for (final c in row.findElements('c')) {
        final col = _columna(c.getAttribute('r'));
        if (col == null || col >= maxColumnas) continue;
        while (fila.length < col) {
          fila.add('');
        }
        final tipo = c.getAttribute('t');
        final v = c.findElements('v').firstOrNull?.innerText ?? '';
        fila.add(switch (tipo) {
          's' => compartidos.elementAtOrNull(int.tryParse(v) ?? -1) ?? '',
          'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
          'b' => v == '1' ? 'VERDADERO' : 'FALSO',
          _ => _numero(v),
        });
      }
      filas.add(fila);
    }
    hojas.add(Hoja(s.getAttribute('name') ?? 'Hoja ${hojas.length + 1}', filas));
  }
  return hojas;
}

/// "C7" → 2.
int? _columna(String? ref) {
  final letras = RegExp(r'^[A-Z]+').firstMatch(ref ?? '')?.group(0);
  if (letras == null) return null;
  var n = 0;
  for (final c in letras.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// "3.5000000000000001" → "3,5"; deja igual lo que no es número.
String _numero(String v) {
  final d = double.tryParse(v);
  if (d == null) return v;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return double.parse(d.toStringAsPrecision(12)).toString().replaceAll('.', ',');
}

/// CSV con coma o punto y coma (el que más aparezca en la primera línea),
/// comillas y saltos de línea dentro de comillas.
Hoja leerCsv(String texto, {String nombre = 'Datos'}) {
  final primera = texto.split('\n').first;
  final sep = ';'.allMatches(primera).length > ','.allMatches(primera).length ? ';' : ',';
  final filas = <List<String>>[];
  var fila = <String>[];
  final celda = StringBuffer();
  var comillas = false;
  for (var i = 0; i < texto.length && filas.length < maxFilas; i++) {
    final c = texto[i];
    if (comillas) {
      if (c == '"' && i + 1 < texto.length && texto[i + 1] == '"') {
        celda.write('"');
        i++;
      } else if (c == '"') {
        comillas = false;
      } else {
        celda.write(c);
      }
    } else if (c == '"') {
      comillas = true;
    } else if (c == sep) {
      fila.add(celda.toString());
      celda.clear();
    } else if (c == '\n') {
      fila.add(celda.toString().replaceAll('\r', ''));
      celda.clear();
      filas.add(fila);
      fila = <String>[];
    } else {
      celda.write(c);
    }
  }
  if (celda.isNotEmpty || fila.isNotEmpty) {
    fila.add(celda.toString().replaceAll('\r', ''));
    filas.add(fila);
  }
  return Hoja(nombre, [for (final f in filas) f.take(maxColumnas).toList()]);
}

/// Texto de cada diapositiva de un .pptx, en orden. `null` si no se puede.
List<List<String>>? leerPptx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final diapositivas = zip.files
      .where((f) => RegExp(r'^ppt/slides/slide\d{1,6}\.xml$').hasMatch(f.name))
      .toList()
    ..sort((a, b) => _nro(a.name).compareTo(_nro(b.name)));
  if (diapositivas.isEmpty) return null;
  return [
    for (final f in diapositivas.take(maxDiapositivas))
      () {
        final texto = leerParte(zip, f.name);
        if (texto == null) return <String>[];
        try {
          final doc = XmlDocument.parse(texto);
          return [
            for (final p in doc.findAllElements('a:p'))
              p.findAllElements('a:t').map((t) => t.innerText).join(),
          ].where((t) => t.trim().isNotEmpty).toList();
        } catch (_) {
          return <String>[];
        }
      }(),
  ];
}

int _nro(String nombre) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(nombre)?.group(1) ?? '') ?? 0;
