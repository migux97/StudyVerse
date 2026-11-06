import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/notificaciones/domain/notificacion.dart';
import 'package:studyverse/features/notificaciones/presentation/notificaciones_providers.dart';
import 'package:studyverse/features/notificaciones/presentation/notificaciones_screen.dart';

void main() {
  test('lee una notificación de la base', () {
    final n = Notificacion.fromMap({
      'id': 'n',
      'tipo': 'tarea_asignada',
      'titulo': 'Ana te asignó «Introducción»',
      'cuerpo': null,
      'ruta': '/grupos/g/tareas',
      'created_at': '2026-11-06T12:00:00Z',
      'leida_at': null,
    });
    expect(n.tipo, TipoNotificacion.tareaAsignada);
    expect(n.leida, isFalse);
  });

  test('solo se abren rutas internas', () {
    expect(rutaValida('/grupos/abc-123/tareas'), isTrue);
    expect(rutaValida('https://otro.sitio'), isFalse);
    expect(rutaValida('/grupos/../../x?y=1'), isFalse);
    expect(rutaValida('javascript:alert(1)'), isFalse);
  });

  testWidgets('la campanita muestra cuántas hay sin leer', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sinLeerProvider.overrideWith((ref) async => 3)],
      child: const MaterialApp(home: Scaffold(body: BotonNotificaciones())),
    ));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('Notificaciones (3 sin leer)'), findsOneWidget);
  });
}
