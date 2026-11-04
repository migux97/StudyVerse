import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lado de la foto de perfil que se sube (los avatares se muestran chicos).
const ladoFoto = 512;

/// Recorta al centro en cuadrado, achica a [ladoFoto] y pasa a JPEG.
/// `null` si el archivo no es una imagen que se pueda leer.
Uint8List? prepararFoto(Uint8List original) {
  final imagen = img.decodeImage(original);
  if (imagen == null) return null;
  final orientada = img.bakeOrientation(imagen);
  final lado = min(orientada.width, orientada.height);
  final cuadrada = img.copyCrop(
    orientada,
    x: (orientada.width - lado) ~/ 2,
    y: (orientada.height - lado) ~/ 2,
    width: lado,
    height: lado,
  );
  final chica = lado > ladoFoto ? img.copyResize(cuadrada, width: ladoFoto, height: ladoFoto) : cuadrada;
  return Uint8List.fromList(img.encodeJpg(chica, quality: 85));
}
