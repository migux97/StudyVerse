import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../files/domain/file_item.dart';
import '../../files/presentation/files_providers.dart';
import '../domain/comparar.dart';
import '../domain/texto_comparable.dart';

/// Más grande que esto no se compara adentro de la app.
const maxBytesComparacion = 25 * 1024 * 1024;

typedef ClaveComparacion = ({FileVersion antes, FileVersion despues, String nombre});

/// Resultado de comparar: las líneas, o por qué no se pudo.
sealed class ResultadoComparacion {
  const ResultadoComparacion();
}

class ComparacionLista extends ResultadoComparacion {
  const ComparacionLista(this.comparacion);
  final Comparacion comparacion;
}

class ComparacionImposible extends ResultadoComparacion {
  const ComparacionImposible(this.motivo);
  final String motivo;
}

/// Compara dos versiones. Se calcula una vez por par (no en cada redibujado).
/// El texto se compara en otro hilo en Android; el de los PDF se lee en este
/// (pdfrx no corre en otro hilo), dejando respirar a la pantalla entre páginas.
final comparacionProvider = FutureProvider.autoDispose.family<ResultadoComparacion, ClaveComparacion>((ref, k) async {
  if (k.antes.sizeBytes > maxBytesComparacion || k.despues.sizeBytes > maxBytesComparacion) {
    return const ComparacionImposible('Estas versiones son muy grandes para compararlas acá. Descargalas para verlas.');
  }
  final modo = modoComparacion(k.nombre);
  if (modo != ModoComparacion.texto && modo != ModoComparacion.pdf) {
    return const ComparacionImposible(
      'Este tipo de archivo no se puede comparar acá. Abrí las dos versiones para verlas.',
    );
  }
  final (antes, despues) = await (
    ref.watch(fileBytesProvider(k.antes).future),
    ref.watch(fileBytesProvider(k.despues).future),
  ).wait;

  if (modo == ModoComparacion.pdf) {
    final (a, b) = await (_textoPdf(antes), _textoPdf(despues)).wait;
    if (a == null || b == null) {
      return const ComparacionImposible(
        'No pudimos leer el texto de este PDF. Si es escaneado, no tiene texto para comparar.',
      );
    }
    return ComparacionLista(await compute(_compararTextos, (a, b)));
  }

  final c = await compute(compararVersiones, (antes: antes, despues: despues, nombre: k.nombre));
  return c == null
      ? const ComparacionImposible('No pudimos leer alguna de las versiones. Probá descargarlas.')
      : ComparacionLista(c);
});

Comparacion _compararTextos((String, String) t) => compararTextos(t.$1, t.$2);

/// El texto de un PDF, página por página (`null` si no se pudo leer o no tiene texto).
Future<String?> _textoPdf(Uint8List bytes) async {
  PdfDocument? doc;
  try {
    // Hace falta si todavía no se abrió ningún visor de PDF (se inicializa una vez).
    await pdfrxFlutterInitialize();
    doc = await PdfDocument.openData(bytes);
    final partes = <String>[];
    for (final p in doc.pages) {
      await Future<void>.delayed(Duration.zero);
      final texto = (await p.loadText())?.fullText.trim() ?? '';
      partes.add('── Página ${p.pageNumber} ──');
      if (texto.isNotEmpty) partes.add(texto);
    }
    final hayTexto = partes.any((l) => !l.startsWith('── Página '));
    return hayTexto ? partes.join('\n') : null;
  } catch (_) {
    return null;
  } finally {
    await doc?.dispose();
  }
}
