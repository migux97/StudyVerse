import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/core/errors.dart';
import 'package:studyverse/features/groups/domain/groups_repository.dart';

void main() {
  test('los errores de la app no se reintentan', () {
    expect(reintentoProviders(0, const GroupFailure('No tenés acceso')), isNull);
  });

  test('los errores de red se reintentan pocas veces', () {
    const red = SocketException('sin conexión');
    expect(reintentoProviders(0, red), isNotNull);
    expect(reintentoProviders(2, red), isNotNull);
    expect(reintentoProviders(3, red), isNull);
  });
}
