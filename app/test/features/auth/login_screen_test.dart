import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:studyverse/features/auth/domain/auth_repository.dart';
import 'package:studyverse/features/auth/presentation/auth_providers.dart';
import 'package:studyverse/features/auth/presentation/login_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repo;

  Widget app() => ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: LoginScreen()),
      );

  setUp(() => repo = _MockAuthRepository());

  testWidgets('valida el formulario antes de llamar al backend', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Ingresá tu email'), findsOneWidget);
    verifyNever(() => repo.signInWithEmail(
        email: any(named: 'email'), password: any(named: 'password')));
  });

  testWidgets('email o contraseña incorrectos: el error va debajo de la contraseña', (tester) async {
    when(() => repo.signInWithEmail(
            email: any(named: 'email'), password: any(named: 'password')))
        .thenThrow(const AuthFailure('El email o la contraseña no coinciden', codigo: 'invalid_credentials'));

    await tester.pumpWidget(app());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@uni.edu.ar');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'incorrecta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    verify(() => repo.signInWithEmail(email: 'ana@uni.edu.ar', password: 'incorrecta'))
        .called(1);
    expect(find.text('El email o la contraseña no coinciden'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'es un error del campo, no un aviso suelto');
  });

  testWidgets('ofrece entrar con un código y con Google', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Entrá a StudyVerse'), findsOneWidget);
    expect(find.text('Entrar con un código por mail'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });
}
