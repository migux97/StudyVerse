import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../documentos/domain/docx.dart';
import '../../documentos/domain/lectores.dart';
import '../../files/domain/file_item.dart';
import '../../files/presentation/files_providers.dart';
import 'vistas.dart' show decodificarTexto;

/// Más grande que esto no se previsualiza: se ofrece descargarlo.
const maxBytesVistaPrevia = 25 * 1024 * 1024;

/// Hasta acá se muestra un archivo de texto (el resto, descargándolo).
const maxCaracteresTexto = 200000;

// Cada archivo se lee y se interpreta una sola vez por versión (no en cada
// redibujado), y en Android en otro hilo.

final docxProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>?, FileVersion>((ref, v) async {
  final b = await ref.watch(fileBytesProvider(v).future);
  return compute(importarDocx, b);
});

final xlsxProvider = FutureProvider.autoDispose.family<List<Hoja>?, FileVersion>((ref, v) async {
  final b = await ref.watch(fileBytesProvider(v).future);
  return compute(leerXlsx, b);
});

final pptxProvider = FutureProvider.autoDispose.family<List<List<String>>?, FileVersion>((ref, v) async {
  final b = await ref.watch(fileBytesProvider(v).future);
  return compute(leerPptx, b);
});

/// Texto del archivo y si quedó cortado por largo.
final textoProvider = FutureProvider.autoDispose.family<({String texto, bool cortado}), FileVersion>((ref, v) async {
  final texto = decodificarTexto(await ref.watch(fileBytesProvider(v).future));
  return texto.length > maxCaracteresTexto
      ? (texto: texto.substring(0, maxCaracteresTexto), cortado: true)
      : (texto: texto, cortado: false);
});

final csvProvider = FutureProvider.autoDispose.family<Hoja, ({FileVersion v, String nombre})>((ref, k) async {
  final t = await ref.watch(textoProvider(k.v).future);
  return compute((String s) => leerCsv(s, nombre: k.nombre), t.texto);
});

/// URL firmada de 15 minutos para reproducir video o audio (una por versión).
final urlMediaProvider = FutureProvider.autoDispose.family<String, FileVersion>(
  (ref, v) => ref.watch(filesRepositoryProvider).downloadUrl(v, '', descargar: false, segundos: 900),
);
