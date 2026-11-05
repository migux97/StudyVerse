import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'delta.dart';
import 'lectores.dart' show leerParte;

/// Abre un .docx como documento de StudyVerse. Conserva párrafos, títulos,
/// listas, alineación, negrita, cursiva, subrayado, tachado y color. Las
/// tablas pasan como texto (una fila por línea) y las imágenes se omiten.
/// `null` si no es un .docx que se pueda leer.
List<Map<String, dynamic>>? importarDocx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }
  final doc = _xml(zip, 'word/document.xml');
  if (doc == null) return null;
  final vinetas = _numeracionesConVineta(_xml(zip, 'word/numbering.xml'));
  final titulos = _estilosDeTitulo(_xml(zip, 'word/styles.xml'));

  final body = doc.findAllElements('w:body').firstOrNull;
  if (body == null) return null;
  final lineas = <Linea>[];
  for (final el in body.childElements) {
    if (el.name.qualified == 'w:p') {
      lineas.add(_parrafo(el, vinetas, titulos));
    } else if (el.name.qualified == 'w:tbl') {
      for (final fila in el.findAllElements('w:tr')) {
        final celdas = fila.findElements('w:tc').map((c) => c.findAllElements('w:t').map((t) => t.innerText).join());
        lineas.add(Linea([Tramo(celdas.join('  |  '))]));
      }
    }
  }
  return opsDe(lineas);
}

XmlDocument? _xml(Archive zip, String nombre) {
  final texto = leerParte(zip, nombre);
  if (texto == null) return null;
  try {
    return XmlDocument.parse(texto);
  } catch (_) {
    return null;
  }
}

/// numId → si es una lista con vinetas (si no, numerada).
Map<String, bool> _numeracionesConVineta(XmlDocument? numbering) {
  if (numbering == null) return const {};
  final abstractos = <String, bool>{};
  for (final a in numbering.findAllElements('w:abstractNum')) {
    final fmt = a.findAllElements('w:numFmt').firstOrNull?.getAttribute('w:val');
    abstractos[a.getAttribute('w:abstractNumId') ?? ''] = fmt == 'bullet';
  }
  return {
    for (final n in numbering.findAllElements('w:num'))
      n.getAttribute('w:numId') ?? '':
          abstractos[n.findElements('w:abstractNumId').firstOrNull?.getAttribute('w:val')] ?? true,
  };
}

/// styleId → nivel de título (Heading1 / Título 1 / Title…).
Map<String, int> _estilosDeTitulo(XmlDocument? styles) {
  final r = <String, int>{};
  for (final s in styles?.findAllElements('w:style') ?? const <XmlElement>[]) {
    final id = s.getAttribute('w:styleId') ?? '';
    final nombre = (s.findElements('w:name').firstOrNull?.getAttribute('w:val') ?? '').toLowerCase();
    final m = RegExp(r'(heading|título|titulo)\s*([1-6])').firstMatch(nombre);
    if (m != null) {
      r[id] = int.parse(m.group(2)!).clamp(1, 3);
    } else if (nombre == 'title') {
      r[id] = 1;
    }
  }
  return r;
}

Linea _parrafo(XmlElement p, Map<String, bool> vinetas, Map<String, int> titulos) {
  final pPr = p.findElements('w:pPr').firstOrNull;
  final bloque = <String, dynamic>{};
  final estiloId = pPr?.findElements('w:pStyle').firstOrNull?.getAttribute('w:val');
  var titulo = titulos[estiloId];
  final porNombre = RegExp(r'^(Heading|Ttulo|Titulo)([1-6])$').firstMatch(estiloId ?? '');
  if (titulo == null && porNombre != null) titulo = int.parse(porNombre.group(2)!).clamp(1, 3);
  if (titulo != null) bloque['header'] = titulo;
  final numPr = pPr?.findElements('w:numPr').firstOrNull;
  if (numPr != null) {
    final numId = numPr.findElements('w:numId').firstOrNull?.getAttribute('w:val');
    if (numId != null && numId != '0') {
      bloque['list'] = (vinetas[numId] ?? true) ? 'bullet' : 'ordered';
      final nivel = int.tryParse(numPr.findElements('w:ilvl').firstOrNull?.getAttribute('w:val') ?? '') ?? 0;
      if (nivel > 0) bloque['indent'] = nivel;
    }
  }
  switch (pPr?.findElements('w:jc').firstOrNull?.getAttribute('w:val')) {
    case 'center':
      bloque['align'] = 'center';
    case 'right' || 'end':
      bloque['align'] = 'right';
    case 'both' || 'distribute':
      bloque['align'] = 'justify';
  }

  final tramos = <Tramo>[];
  for (final r in p.findAllElements('w:r')) {
    final rPr = r.findElements('w:rPr').firstOrNull;
    final estilo = <String, dynamic>{
      if (_activo(rPr, 'w:b')) 'bold': true,
      if (_activo(rPr, 'w:i')) 'italic': true,
      if (rPr?.findElements('w:u').firstOrNull?.getAttribute('w:val') case final u? when u != 'none') 'underline': true,
      if (_activo(rPr, 'w:strike')) 'strike': true,
    };
    final color = rPr?.findElements('w:color').firstOrNull?.getAttribute('w:val');
    if (color != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(color) && color.toUpperCase() != '000000') {
      estilo['color'] = '#${color.toLowerCase()}';
    }
    final texto = StringBuffer();
    for (final c in r.childElements) {
      switch (c.name.qualified) {
        case 'w:t':
          texto.write(c.innerText);
        case 'w:tab':
          texto.write('\t');
        case 'w:br' || 'w:cr':
          texto.write(' ');
      }
    }
    if (texto.isNotEmpty) tramos.add(Tramo(texto.toString(), estilo));
  }
  return Linea(tramos, bloque);
}

bool _activo(XmlElement? rPr, String tag) {
  final e = rPr?.findElements(tag).firstOrNull;
  if (e == null) return false;
  final v = e.getAttribute('w:val');
  return v == null || (v != '0' && v != 'false');
}

// Exportar ------------------------------------------------------------------------

/// Arma un .docx con el documento. Títulos con los estilos de Word, listas con
/// vinetas o numeradas, y el formato de cada tramo.
Uint8List exportarDocx(List<dynamic> ops) {
  final cuerpo = StringBuffer();
  for (final l in lineasDe(ops)) {
    cuerpo.write('<w:p><w:pPr>');
    if (l.titulo != null) cuerpo.write('<w:pStyle w:val="Heading${l.titulo}"/>');
    if (l.cita) cuerpo.write('<w:pStyle w:val="Quote"/>');
    final lista = l.lista;
    if (lista == 'bullet' || lista == 'ordered') {
      cuerpo.write('<w:numPr><w:ilvl w:val="${l.sangria.clamp(0, 8)}"/>'
          '<w:numId w:val="${lista == 'bullet' ? 1 : 2}"/></w:numPr>');
    } else if (l.sangria > 0) {
      cuerpo.write('<w:ind w:left="${720 * l.sangria}"/>');
    }
    final jc = switch (l.alineacion) { 'center' => 'center', 'right' => 'right', 'justify' => 'both', _ => null };
    if (jc != null) cuerpo.write('<w:jc w:val="$jc"/>');
    cuerpo.write('</w:pPr>');
    if (lista == 'checked' || lista == 'unchecked') {
      cuerpo.write('<w:r><w:t xml:space="preserve">${lista == 'checked' ? '☑' : '☐'} </w:t></w:r>');
    }
    for (final t in l.tramos) {
      cuerpo.write('<w:r><w:rPr>');
      if (t.negrita) cuerpo.write('<w:b/>');
      if (t.cursiva) cuerpo.write('<w:i/>');
      if (t.subrayado) cuerpo.write('<w:u w:val="single"/>');
      if (t.tachado) cuerpo.write('<w:strike/>');
      final color = _hex(t.color);
      if (color != null) cuerpo.write('<w:color w:val="$color"/>');
      final fondo = _hex(t.fondo);
      if (fondo != null) cuerpo.write('<w:shd w:val="clear" w:color="auto" w:fill="$fondo"/>');
      cuerpo.write('</w:rPr><w:t xml:space="preserve">${_escapar(t.texto)}</w:t></w:r>');
    }
    cuerpo.write('</w:p>');
  }

  final archivos = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
        '</Relationships>',
    'word/document.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
        '$cuerpo'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>',
    'word/styles.xml': _estilos,
    'word/numbering.xml': _numeracion,
  };
  final zip = Archive();
  for (final MapEntry(:key, :value) in archivos.entries) {
    zip.addFile(ArchiveFile.bytes(key, utf8.encode(value)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(zip));
}

String? _hex(String? color) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})').firstMatch(color ?? '');
  return m?.group(1)?.toUpperCase();
}

String _escapar(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

const _estilos = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/>'
    '<w:lang w:val="es-AR"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720"/></w:pPr><w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>'
    '</w:styles>';

final _numeracion = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:abstractNum w:abstractNumId="0">${List.generate(9, (i) => '<w:lvl w:ilvl="$i"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
        '<w:lvlText w:val="${i.isEven ? '•' : '◦'}"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="${720 * (i + 1)}" w:hanging="360"/></w:pPr></w:lvl>').join()}</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1">${List.generate(9, (i) => '<w:lvl w:ilvl="$i"><w:start w:val="1"/><w:numFmt w:val="${i.isEven ? 'decimal' : 'lowerLetter'}"/>'
        '<w:lvlText w:val="%${i + 1}."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="${720 * (i + 1)}" w:hanging="360"/></w:pPr></w:lvl>').join()}</w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
    '</w:numbering>';
