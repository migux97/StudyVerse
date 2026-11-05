import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/core/widgets/text_input_dialog.dart';
import 'package:studyverse/features/auth/presentation/campos.dart';

void main() {
  testWidgets('CampoEmail: muestra el ejemplo, valida y corrige el dominio mal escrito', (tester) async {
    final email = TextEditingController();
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Form(key: form, child: CampoEmail(controller: email))),
      ),
    ));

    expect(find.text('nombre@ejemplo.com'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'ana');
    form.currentState!.validate();
    await tester.pump();
    expect(find.text('Falta el @ en el email'), findsOneWidget);

    // El error se va apenas se corrige, sin volver a enviar.
    await tester.enterText(find.byType(TextFormField), 'ana@gmial.com');
    await tester.pump();
    expect(find.text('Falta el @ en el email'), findsNothing);
    expect(find.textContaining('¿Quisiste decir'), findsOneWidget);

    await tester.tap(find.textContaining('¿Quisiste decir'));
    await tester.pump();
    expect(email.text, 'ana@gmail.com');
    expect(find.textContaining('¿Quisiste decir'), findsNothing);
  });

  testWidgets('pedirTexto: ejemplo, campo vacío y largo máximo', (tester) async {
    String? resultado = 'sin tocar';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => resultado = await pedirTexto(
            context,
            titulo: 'Tu carrera',
            etiqueta: 'Carrera',
            accion: 'Guardar',
            ejemplo: 'Ej.: Ingeniería en Sistemas',
            maximo: 10,
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ej.: Ingeniería en Sistemas'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(find.text('Completá este campo'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Ingeniería Civil');
    await tester.pump();
    expect(find.text('Completá este campo'), findsNothing);
    expect(find.text('10 / 10'), findsOneWidget, reason: 'no deja pasar del máximo');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(resultado, 'Ingeniería');
  });
}
