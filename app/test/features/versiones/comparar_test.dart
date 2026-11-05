import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/files/domain/file_item.dart';
import 'package:studyverse/features/versiones/domain/comparar.dart';
import 'package:studyverse/features/versiones/domain/historial.dart';
import 'package:studyverse/features/versiones/domain/texto_comparable.dart';

List<String> resumen(Comparacion c) => c.lineas.map((l) => l.toString()).toList();

FileVersion version(int n, DateTime fecha, {String? guardada}) => FileVersion(
      id: 'v$n',
      fileId: 'f',
      versionNumber: n,
      storagePath: 'x/v$n',
      sizeBytes: 10,
      createdAt: fecha,
      guardadaNombre: guardada,
    );

void main() {
  group('compararTextos', () {
    test('marca lo agregado y lo quitado, y deja igual lo demás', () {
      final c = compararTextos('uno\ndos\ntres\ncuatro', 'uno\ntres\ncuatro\ncinco');
      expect(resumen(c), [' uno', '-dos', ' tres', ' cuatro', '+cinco']);
      expect(c.agregadas, 1);
      expect(c.quitadas, 1);
      expect(c.lineas[2].numAntes, 3);
      expect(c.lineas[2].numDespues, 2);
    });

    test('textos iguales: sin cambios (sin importar el salto de línea final ni CRLF)', () {
      expect(compararTextos('a\r\nb\n', 'a\nb').sinCambios, isTrue);
    });

    test('de vacío a algo y de algo a vacío', () {
      expect(resumen(compararTextos('', 'hola')), ['+hola']);
      expect(resumen(compararTextos('hola', '')), ['-hola']);
    });

    test('es mínimo: no marca de más', () {
      final antes = List.generate(200, (i) => 'línea $i').join('\n');
      final despues = antes.replaceFirst('línea 100', 'línea cien');
      final c = compararTextos(antes, despues);
      expect(c.agregadas, 1);
      expect(c.quitadas, 1);
    });

    test('una línea modificada marca solo las palabras que cambiaron', () {
      final c = compararTextos('El TP se entrega el lunes', 'El TP se entrega el martes');
      final quitada = c.lineas.firstWhere((l) => l.tipo == TipoLinea.quitada);
      final agregada = c.lineas.firstWhere((l) => l.tipo == TipoLinea.agregada);
      expect(quitada.fragmentos, [const Fragmento('El TP se entrega el '), const Fragmento('lunes', cambiado: true)]);
      expect(agregada.fragmentos!.last, const Fragmento('martes', cambiado: true));
    });

    test('líneas que no se parecen se muestran enteras', () {
      final c = compararTextos('Introducción', 'Bibliografía consultada');
      expect(c.lineas.every((l) => l.fragmentos == null), isTrue);
    });
  });

  test('con textos al azar, aplicar el diff da el texto nuevo', () {
    final r = Random(7);
    String azar() => List.generate(r.nextInt(40), (_) => 'abcde'[r.nextInt(5)]).join('\n');
    for (var i = 0; i < 300; i++) {
      final a = azar(), b = azar();
      final c = compararTextos(a, b);
      final reconstruido = c.lineas.where((l) => l.tipo != TipoLinea.quitada).map((l) => l.texto).join('\n');
      final original = c.lineas.where((l) => l.tipo != TipoLinea.agregada).map((l) => l.texto).join('\n');
      expect(reconstruido, b, reason: '$a → $b');
      expect(original, a);
    }
  });

  test('dos textos enormes y totalmente distintos terminan rápido y sin colgarse', () {
    final a = List.generate(20000, (i) => 'a$i').join('\n');
    final b = List.generate(20000, (i) => 'b$i').join('\n');
    final reloj = Stopwatch()..start();
    final c = compararTextos(a, b);
    expect(c.quitadas, 20000);
    expect(c.agregadas, 20000);
    expect(reloj.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('plegar deja 3 líneas de contexto y pliega el resto', () {
    final antes = List.generate(30, (i) => '$i').join('\n');
    final despues = antes.replaceFirst('\n15\n', '\nquince\n');
    final bloques = plegar(compararTextos(antes, despues).lineas);
    expect(bloques.map((b) => b.runtimeType.toString()).toList(),
        ['BloquePlegado', 'BloqueLineas', 'BloquePlegado']);
    expect((bloques[0] as BloquePlegado).lineas.length, 12);
    expect((bloques[1] as BloqueLineas).lineas.length, 8);
  });

  test('lado a lado empareja quitadas con agregadas', () {
    final filas = filasLadoALado(compararTextos('a\nb\nc', 'a\nB\nB2\nc').lineas);
    expect(filas.map((f) => '${f.antes?.texto}|${f.despues?.texto}').toList(), ['a|a', 'b|B', 'null|B2', 'c|c']);
  });

  group('texto comparable', () {
    test('documentos de StudyVerse: el texto, sin el formato', () {
      final ops = [
        {'insert': 'Título', 'attributes': {'bold': true}},
        {'insert': '\n', 'attributes': {'header': 1}},
        {'insert': 'Cuerpo\n'},
      ];
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(ops)));
      expect(textoComparable(bytes, 'Informe.svdoc'), 'Título\nCuerpo');
    });

    test('texto con BOM', () {
      expect(textoComparable(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('hola')]), 'a.txt'), 'hola');
    });

    test('qué se puede comparar', () {
      expect(modoComparacion('a.docx'), ModoComparacion.texto);
      expect(modoComparacion('a.csv'), ModoComparacion.texto);
      expect(modoComparacion('a.pdf'), ModoComparacion.pdf);
      expect(modoComparacion('a.png'), ModoComparacion.imagen);
      expect(modoComparacion('a.doc'), ModoComparacion.ninguno);
      expect(modoComparacion('a.mp4'), ModoComparacion.ninguno);
    });

    test('compararVersiones lee y compara', () {
      final c = compararVersiones((
        antes: Uint8List.fromList(utf8.encode('a\nb')),
        despues: Uint8List.fromList(utf8.encode('a\nc')),
        nombre: 'notas.md',
      ));
      expect(resumen(c!), [' a', '-b', '+c']);
    });
  });

  group('historial', () {
    final ahora = DateTime(2026, 11, 5, 18);

    test('encabezados por día', () {
      expect(encabezadoDia(DateTime(2026, 11, 5, 9), ahora), 'Hoy');
      expect(encabezadoDia(DateTime(2026, 11, 4, 23), ahora), 'Ayer');
      expect(encabezadoDia(DateTime(2026, 11, 2), ahora), 'Lunes 2 de noviembre');
      expect(encabezadoDia(DateTime(2025, 3, 3), ahora), 'Lunes 3 de marzo de 2025');
    });

    test('agrupa por día y busca la anterior visible', () {
      final vs = [
        version(5, DateTime(2026, 11, 5, 10)),
        version(4, DateTime(2026, 11, 5, 9)),
        version(2, DateTime(2026, 11, 3), guardada: 'Entrega 1'),
      ];
      final dias = agruparPorDia(vs, ahora);
      expect(dias.map((d) => d.titulo).toList(), ['Hoy', 'Martes 3 de noviembre']);
      expect(dias.first.versiones.length, 2);
      expect(anteriorA(vs, vs[1])!.versionNumber, 2, reason: 'la v3 no está visible');
      expect(anteriorA(vs, vs[2]), isNull);
      expect(etiquetaVersion(vs[2]), 'v2 · Entrega 1');
      expect(horaCorta(DateTime(2026, 11, 5, 9, 5)), '09:05');
    });
  });
}
