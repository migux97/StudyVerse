import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'delta.dart';

/// Arma un PDF A4 con el documento: títulos, listas, citas, alineación y el
/// formato de cada tramo. Las fuentes base del PDF cubren el español (tildes, ñ).
Future<Uint8List> exportarPdf(List<dynamic> ops, {String? titulo}) {
  final doc = pw.Document(title: titulo, creator: 'StudyVerse');
  final lineas = lineasDe(ops);
  final numeros = <int, int>{};

  final bloques = <pw.Widget>[];
  for (final l in lineas) {
    final lista = l.lista;
    if (lista != 'ordered') numeros.remove(l.sangria);
    final tamano = switch (l.titulo) { 1 => 20.0, 2 => 16.0, 3 => 13.5, _ => 11.0 };
    final base = pw.TextStyle(
      fontSize: tamano,
      fontWeight: l.titulo != null ? pw.FontWeight.bold : null,
      fontStyle: l.cita ? pw.FontStyle.italic : null,
      color: l.cita ? PdfColors.grey700 : null,
      lineSpacing: 2,
    );
    final texto = pw.RichText(
      textAlign: switch (l.alineacion) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.left,
      },
      text: pw.TextSpan(
        style: base,
        children: l.tramos.isEmpty
            ? [const pw.TextSpan(text: ' ')]
            : [for (final t in l.tramos) pw.TextSpan(text: t.texto, style: _estilo(t))],
      ),
    );

    String? marca;
    if (lista == 'bullet') marca = l.sangria.isEven ? '•' : '-';
    if (lista == 'checked') marca = '[x]';
    if (lista == 'unchecked') marca = '[ ]';
    if (lista == 'ordered') {
      final n = (numeros[l.sangria] ?? 0) + 1;
      numeros[l.sangria] = n;
      marca = '$n.';
    }

    final sangria = 18.0 * l.sangria + (l.cita ? 14 : 0);
    bloques.add(pw.Padding(
      padding: pw.EdgeInsets.only(
        left: sangria,
        top: l.titulo != null ? 10 : 0,
        bottom: l.titulo != null ? 4 : 5,
      ),
      child: marca == null
          ? texto
          : pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 22, child: pw.Text(marca, style: base)),
              pw.Expanded(child: texto),
            ]),
    ));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(56),
    build: (_) => bloques.isEmpty ? [pw.SizedBox()] : bloques,
  ));
  return doc.save();
}

pw.TextStyle _estilo(Tramo t) {
  final decoraciones = [
    if (t.subrayado || t.link != null) pw.TextDecoration.underline,
    if (t.tachado) pw.TextDecoration.lineThrough,
  ];
  return pw.TextStyle(
    fontWeight: t.negrita ? pw.FontWeight.bold : null,
    fontStyle: t.cursiva ? pw.FontStyle.italic : null,
    decoration: decoraciones.isEmpty ? null : pw.TextDecoration.combine(decoraciones),
    color: _color(t.color) ?? (t.link != null ? PdfColors.blue700 : null),
    background: _color(t.fondo) == null ? null : pw.BoxDecoration(color: _color(t.fondo)),
  );
}

PdfColor? _color(String? hex) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})').firstMatch(hex ?? '');
  return m == null ? null : PdfColor.fromHex(m.group(1)!);
}
