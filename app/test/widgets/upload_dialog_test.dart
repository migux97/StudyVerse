import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/files/domain/files_repository.dart';
import 'package:studyverse/features/files/presentation/upload_dialog.dart';
import 'package:studyverse/features/files/presentation/uploads_controller.dart';

Subida _subida(String nombre, {int tamano = 1024, String? versionDe, String? copiaPorque}) => Subida(
      nombre: nombre,
      tamano: tamano,
      leer: () async => Uint8List(0),
      versionDe: versionDe,
      copiaPorque: copiaPorque,
    );

Future<String?> _abrir(WidgetTester tester, List<Subida> subidas) async {
  String? resultado = 'sin cerrar';
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => resultado = await confirmarSubida(context, subidas),
        child: const Text('abrir'),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return resultado;
}

void main() {
  testWidgets('distingue archivo nuevo, versión nueva y copia', (tester) async {
    await _abrir(tester, [
      _subida('Datos.xlsx'),
      _subida('Informe.docx', versionDe: 'Informe.docx'),
      _subida('Intro (copia de Ana).docx', copiaPorque: 'Juan'),
    ]);

    expect(find.text('Subir 3 archivos'), findsOneWidget);
    expect(find.text('1 KB · archivo nuevo'), findsOneWidget);
    expect(find.text('1 KB · nueva versión'), findsOneWidget);
    expect(find.text('1 KB · Juan edita el original: se sube como copia'), findsOneWidget);
    expect(find.text('¿Qué cambiaste? (opcional)'), findsOneWidget);
  });

  testWidgets('devuelve la nota al confirmar', (tester) async {
    String? nota;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => nota = await confirmarSubida(
            context,
            [_subida('Informe.docx', versionDe: 'Informe.docx')],
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Subir nueva versión'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'corregí la conclusión');
    await tester.tap(find.text('Subir'));
    await tester.pumpAndSettle();
    expect(nota, 'corregí la conclusión');
  });

  testWidgets('si todo supera el máximo, no deja subir', (tester) async {
    await _abrir(tester, [_subida('video.mp4', tamano: maxBytesPorArchivo + 1)]);

    expect(find.textContaining('Supera el máximo de 50 MB'), findsOneWidget);
    final boton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Subir'));
    expect(boton.onPressed, isNull);
  });
}
