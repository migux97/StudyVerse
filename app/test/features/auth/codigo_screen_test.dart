import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:studyverse/features/auth/domain/auth_repository.dart';
import 'package:studyverse/features/auth/presentation/auth_providers.dart';
import 'package:studyverse/features/auth/presentation/codigo_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repo;
  setUpAll(() => registerFallbackValue(MotivoCodigo.entrar));
  setUp(() => repo = _MockAuthRepository());

  Widget app(MotivoCodigo motivo, {String? email}) => ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: CodigoScreen(motivo: motivo, email: email)),
      );

  testWidgets('entrar: primero pide el email y manda el código', (tester) async {
    when(() => repo.enviarCodigo(any(), any())).thenAnswer((_) async {});
    await tester.pumpWidget(app(MotivoCodigo.entrar));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@uni.edu.ar');
    await tester.tap(find.text('Mandame el código'));
    await tester.pump();

    verify(() => repo.enviarCodigo('ana@uni.edu.ar', MotivoCodigo.entrar)).called(1);
    expect(find.text('Si hay una cuenta con ana@uni.edu.ar, te llega un código de 6 números'), findsOneWidget,
        reason: 'no revela si el email tiene cuenta');
    expect(find.text('Reenviar en 30 s'), findsOneWidget, reason: 'no deja reenviar al toque');
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Reenviar código'), findsOneWidget);
  });

  testWidgets('entrar: un email sin cuenta sigue igual, sin decir que no existe', (tester) async {
    when(() => repo.enviarCodigo(any(), any())).thenThrow(const AuthFailure('x', codigo: 'otp_disabled'));
    await tester.pumpWidget(app(MotivoCodigo.entrar, email: 'nadie@uni.edu.ar'));
    await tester.tap(find.text('Mandame el código'));
    await tester.pump();
    expect(find.text('Código de 6 números'), findsOneWidget);
    expect(find.textContaining('No encontramos'), findsNothing);
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('registro: el código ya salió, y uno vencido marca el campo', (tester) async {
    when(() => repo.verificarCodigo(any(), any(), any(), nuevaPassword: any(named: 'nuevaPassword')))
        .thenThrow(const AuthFailure('vencido', codigo: 'otp_expired'));
    await tester.pumpWidget(app(MotivoCodigo.registro, email: 'ana@uni.edu.ar'));

    expect(find.text('Confirmá tu email'), findsOneWidget);
    // Con el sexto número se verifica solo, sin tocar "Confirmar".
    await tester.enterText(find.widgetWithText(TextFormField, 'Código de 6 números'), '123456');
    await tester.pump();

    verify(() => repo.verificarCodigo('ana@uni.edu.ar', '123456', MotivoCodigo.registro)).called(1);
    expect(find.text('El código no es correcto o ya venció'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('recuperar: pide la contraseña nueva con sus requisitos', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => repo.enviarCodigo(any(), any())).thenAnswer((_) async {});
    await tester.pumpWidget(app(MotivoCodigo.recuperar, email: 'ana@uni.edu.ar'));
    await tester.tap(find.text('Mandame el código'));
    await tester.pump();

    expect(find.text('Contraseña nueva'), findsOneWidget);
    expect(find.text('Una mayúscula'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Código de 6 números'), '123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña nueva'), 'corta');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pump();
    expect(find.text('Usá 8 caracteres o más'), findsOneWidget);
    verifyNever(() => repo.verificarCodigo(any(), any(), any(), nuevaPassword: any(named: 'nuevaPassword')));
    await tester.pump(const Duration(seconds: 31));
  });
}
