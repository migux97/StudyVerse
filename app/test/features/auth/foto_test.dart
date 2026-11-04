import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:studyverse/features/auth/domain/foto.dart';

void main() {
  test('una foto grande y apaisada queda cuadrada, de 512 px y en JPEG', () {
    final original = img.Image(width: 1600, height: 900);
    final png = Uint8List.fromList(img.encodePng(original));

    final lista = prepararFoto(png)!;
    final resultado = img.decodeJpg(lista)!;
    expect((resultado.width, resultado.height), (ladoFoto, ladoFoto));
    expect(lista.length, lessThan(1024 * 1024), reason: 'entra en el límite del bucket');
  });

  test('una chica no se agranda', () {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 200, height: 300)));
    final resultado = img.decodeJpg(prepararFoto(png)!)!;
    expect((resultado.width, resultado.height), (200, 200));
  });

  test('algo que no es una imagen devuelve null', () {
    expect(prepararFoto(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
