import 'package:flutter_test/flutter_test.dart';
import 'package:tpdrive/core/config/env.dart';
import 'package:tpdrive/core/router/app_router.dart';
import 'package:tpdrive/features/auth/data/supabase_auth_repository.dart';
import 'package:tpdrive/features/auth/domain/profile.dart';
import 'package:tpdrive/features/auth/domain/validators.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), 'Ingresá tu email');
      expect(Validators.email('ana@'), 'El email no es válido');
      expect(Validators.email(' ana@uni.edu.ar '), isNull);
    });

    test('password', () {
      expect(Validators.password(''), 'Ingresá tu contraseña');
      expect(Validators.password('1234567'), 'Mínimo 8 caracteres');
      expect(Validators.password('12345678'), isNull);
    });

    test('nombre', () {
      expect(Validators.nombre('   '), 'Ingresá tu nombre');
      expect(Validators.nombre('a' * 81), 'Máximo 80 caracteres');
      expect(Validators.nombre('Ana'), isNull);
    });

    test('confirmar contraseña', () {
      final v = Validators.confirmarPassword(() => 'secreto123');
      expect(v('otra'), 'Las contraseñas no coinciden');
      expect(v('secreto123'), isNull);
    });
  });

  group('Profile', () {
    final base = {
      'id': 'u1',
      'nombre': 'Ana María López',
      'avatar_url': null,
      'plan': 'premium',
      'created_at': '2026-11-01T12:00:00Z',
    };

    test('fromMap', () {
      final p = Profile.fromMap(base);
      expect(p.plan, Plan.premium);
      expect(p.createdAt.isUtc, isTrue);
    });

    test('iniciales', () {
      expect(Profile.fromMap(base).iniciales, 'AM');
      expect(Profile.fromMap({...base, 'nombre': 'juan'}).iniciales, 'J');
    });
  });

  group('authRedirect', () {
    test('sin sesión manda al login', () {
      expect(authRedirect(loggedIn: false, location: '/'), Routes.login);
      expect(authRedirect(loggedIn: false, location: '/registro'), isNull);
    });

    test('sin sesión recuerda a dónde se quería ir', () {
      expect(authRedirect(loggedIn: false, location: '/unirse/ABCD2345'),
          '/login?from=%2Funirse%2FABCD2345');
    });

    test('con sesión no muestra pantallas de acceso', () {
      expect(authRedirect(loggedIn: true, location: '/login'), Routes.grupos);
      expect(authRedirect(loggedIn: true, location: '/perfil'), isNull);
    });

    test('después del login vuelve al destino, solo si es interno', () {
      expect(authRedirect(loggedIn: true, location: '/login', from: '/unirse/ABCD2345'),
          '/unirse/ABCD2345');
      expect(authRedirect(loggedIn: true, location: '/login', from: '//evil.com'), Routes.grupos);
      expect(authRedirect(loggedIn: true, location: '/login', from: 'https://evil.com'),
          Routes.grupos);
    });
  });

  test('errores de auth en español', () {
    expect(traducirErrorAuth('invalid_credentials', ''), 'Email o contraseña incorrectos');
    expect(traducirErrorAuth('algo_raro', 'boom'), startsWith('No se pudo'));
  });

  test('URL local se adapta al emulador de Android', () {
    expect(resolveSupabaseUrl('http://127.0.0.1:54321', isAndroid: true),
        'http://10.0.2.2:54321');
    expect(resolveSupabaseUrl('http://127.0.0.1:54321', isAndroid: false),
        'http://127.0.0.1:54321');
    expect(resolveSupabaseUrl('https://abc.supabase.co', isAndroid: true),
        'https://abc.supabase.co');
  });
}
