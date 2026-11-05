import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/documentos/domain/delta.dart';
import 'package:studyverse/features/documentos/domain/docx.dart';
import 'package:studyverse/features/documentos/domain/documento.dart';
import 'package:studyverse/features/documentos/domain/lectores.dart';
import 'package:studyverse/features/documentos/domain/pdf_export.dart';
import 'package:studyverse/features/files/domain/file_item.dart';

final _ops = <Map<String, dynamic>>[
  {'insert': 'Informe final'},
  {'insert': '\n', 'attributes': {'header': 1}},
  {'insert': 'Texto con '},
  {'insert': 'negrita', 'attributes': {'bold': true}},
  {'insert': ' y '},
  {'insert': 'color', 'attributes': {'color': '#e53935', 'italic': true}},
  {'insert': ' — ñandú.\n'},
  {'insert': 'Primero'},
  {'insert': '\n', 'attributes': {'list': 'ordered'}},
  {'insert': 'Viñeta'},
  {'insert': '\n', 'attributes': {'list': 'bullet'}},
  {'insert': 'Centrado'},
  {'insert': '\n', 'attributes': {'align': 'center'}},
];

Uint8List _zip(Map<String, String> archivos) {
  final a = Archive();
  for (final MapEntry(:key, :value) in archivos.entries) {
    a.addFile(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(a));
}

void main() {
  group('Delta', () {
    test('se parte en líneas con su formato de párrafo', () {
      final l = lineasDe(_ops);
      expect(l.map((x) => x.texto), ['Informe final', 'Texto con negrita y color — ñandú.', 'Primero', 'Viñeta', 'Centrado']);
      expect(l[0].titulo, 1);
      expect(l[1].tramos[1].negrita, isTrue);
      expect(l[1].tramos[3].color, '#e53935');
      expect(l[2].lista, 'ordered');
      expect(l[4].alineacion, 'center');
    });

    test('ida y vuelta: líneas → ops → líneas', () {
      final vuelta = lineasDe(opsDe(lineasDe(_ops)));
      expect(vuelta.map((x) => x.texto), lineasDe(_ops).map((x) => x.texto));
      expect(vuelta[2].lista, 'ordered');
    });

    test('un documento vacío o roto se abre vacío', () {
      expect(opsDeVersion(Uint8List(0)), deltaVacio);
      expect(opsDeVersion(Uint8List.fromList(utf8.encode('no es json'))), deltaVacio);
      expect(opsDeVersion(bytesDeOps(_ops)), _ops);
    });
  });

  group('Word', () {
    test('exportar y volver a importar conserva texto, títulos, listas y formato', () {
      final docx = exportarDocx(_ops);
      final ops = importarDocx(docx)!;
      final l = lineasDe(ops);
      expect(l.map((x) => x.texto), contains('Texto con negrita y color — ñandú.'));
      expect(l.firstWhere((x) => x.texto == 'Informe final').titulo, 1);
      expect(l.firstWhere((x) => x.texto == 'Primero').lista, 'ordered');
      expect(l.firstWhere((x) => x.texto == 'Viñeta').lista, 'bullet');
      expect(l.firstWhere((x) => x.texto == 'Centrado').alineacion, 'center');
      final parrafo = l.firstWhere((x) => x.texto.startsWith('Texto con'));
      expect(parrafo.tramos.firstWhere((t) => t.texto == 'negrita').negrita, isTrue);
      expect(parrafo.tramos.firstWhere((t) => t.texto == 'color').color, '#e53935');
    });

    test('importa los títulos de un Word en español ("Título 1")', () {
      final docx = _zip({
        'word/document.xml': '<w:document xmlns:w="w"><w:body>'
            '<w:p><w:pPr><w:pStyle w:val="Ttulo2"/></w:pPr><w:r><w:t>Marco teórico</w:t></w:r></w:p>'
            '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
            '</w:body></w:document>',
        'word/styles.xml': '<w:styles xmlns:w="w"><w:style w:styleId="Ttulo2"><w:name w:val="heading 2"/></w:style></w:styles>',
      });
      final l = lineasDe(importarDocx(docx)!);
      expect(l.first.texto, 'Marco teórico');
      expect(l.first.titulo, 2);
      expect(l[1].texto, 'A  |  B', reason: 'las tablas pasan como texto');
    });

    test('algo que no es un .docx no se importa', () {
      expect(importarDocx(Uint8List.fromList([1, 2, 3])), isNull);
      expect(importarDocx(_zip({'otra/cosa.xml': '<x/>'})), isNull);
    });
  });

  test('PDF: arma un archivo PDF válido', () async {
    final pdf = await exportarPdf(_ops, titulo: 'Informe');
    expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(1000));
  });

  group('Planillas y presentaciones', () {
    test('xlsx: hojas, textos compartidos, números y celdas salteadas', () {
      final xlsx = _zip({
        'xl/workbook.xml': '<workbook><sheets><sheet name="Notas" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
        'xl/sharedStrings.xml': '<sst><si><t>Alumno</t></si><si><t>Nota</t></si><si><t>Ana</t></si></sst>',
        'xl/worksheets/sheet1.xml': '<worksheet><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
            '<row r="3"><c r="A3" t="s"><v>2</v></c><c r="C3"><v>8.5</v></c></row>'
            '</sheetData></worksheet>',
      });
      final hojas = leerXlsx(xlsx)!;
      expect(hojas.single.nombre, 'Notas');
      expect(hojas.single.filas[0], ['Alumno', 'Nota']);
      expect(hojas.single.filas[1], isEmpty, reason: 'la fila 2 no existe');
      expect(hojas.single.filas[2], ['Ana', '', '8,5']);
      expect(hojas.single.columnas, 3);
    });

    test('csv con punto y coma y comillas', () {
      final h = leerCsv('Nombre;Comentario\nAna;"Dijo ""hola""; y se fue"\n');
      expect(h.filas, [
        ['Nombre', 'Comentario'],
        ['Ana', 'Dijo "hola"; y se fue'],
      ]);
    });

    test('pptx: el texto de cada diapositiva en orden', () {
      final pptx = _zip({
        'ppt/slides/slide10.xml': '<p:sld><a:p><a:t>Décima</a:t></a:p></p:sld>',
        'ppt/slides/slide2.xml': '<p:sld><a:p><a:t>Objetivos</a:t></a:p><a:p><a:t>Uno</a:t></a:p></p:sld>',
      });
      expect(leerPptx(pptx), [
        ['Objetivos', 'Uno'],
        ['Décima'],
      ]);
    });
  });

  group('Borradores', () {
    const b = ContenidoDocumento(ops: [], borradorDe: 'Ana', autorId: 'ana', baseVersion: 3);
    ContenidoDocumento? vigente({String? bloqueadoPor, bool vigente = true, String? miId, int? version = 3}) =>
        borradorVigente(b, bloqueadoPor: bloqueadoPor, bloqueoVigente: vigente, miId: miId, versionActual: version);

    test('mientras su autor lo tiene bloqueado, todos ven el borrador', () {
      expect(vigente(bloqueadoPor: 'ana', miId: 'juan'), same(b));
    });

    test('si el bloqueo se liberó, los demás ven la versión guardada', () {
      expect(vigente(bloqueadoPor: null, miId: 'juan'), isNull);
      expect(vigente(bloqueadoPor: 'ana', vigente: false, miId: 'juan'), isNull);
    });

    test('el autor recupera lo que no terminó', () {
      final r = vigente(bloqueadoPor: null, miId: 'ana');
      expect(r?.recuperado, isTrue);
    });

    test('salvo que alguien haya subido otra versión mientras tanto', () {
      expect(vigente(bloqueadoPor: null, miId: 'ana', version: 4), isNull);
    });
  });

  test('una parte del zip que se infla demasiado no se lee', () {
    final grande = Archive()..addFile(ArchiveFile.bytes('word/document.xml', Uint8List(maxBytesDescomprimidos + 1)));
    final zip = Uint8List.fromList(ZipEncoder().encodeBytes(grande));
    expect(zip.length, lessThan(1024 * 1024), reason: 'comprimido es chico');
    expect(importarDocx(zip), isNull);
  });

  test('los documentos de StudyVerse se muestran sin extensión', () {
    expect(nombreVisible('Informe.svdoc'), 'Informe');
    expect(nombreVisible('Informe.docx'), 'Informe.docx');
    expect(fileKindFor('Informe.svdoc'), FileKind.studyverse);
  });
}
