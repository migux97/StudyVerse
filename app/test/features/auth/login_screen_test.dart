import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tpdrive/features/auth/domain/auth_repository.dart';
import 'package:tpdrive/features/auth/presentation/auth_providers.dart';
import 'package:tpdrive/features/auth/presentation/login_screen.dart';

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

  testWidgets('muestra el error traducido si falla el login', (tester) async {
    when(() => repo.signInWithEmail(
            email: any(named: 'email'), password: any(named: 'password')))
        .thenThrow(const AuthFailure('Email o contraseña incorrectos'));

    await tester.pumpWidget(app());
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@uni.edu.ar');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'incorrecta');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    verify(() => repo.signInWithEmail(email: 'ana@uni.edu.ar', password: 'incorrecta'))
        .called(1);
    expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
  });
}
