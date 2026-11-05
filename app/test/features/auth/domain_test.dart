import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/core/config/env.dart';
import 'package:studyverse/core/forms/validar.dart';
import 'package:studyverse/core/router/app_router.dart';
import 'package:studyverse/features/auth/data/supabase_auth_repository.dart';
import 'package:studyverse/features/auth/domain/cuenta.dart';
import 'package:studyverse/features/auth/domain/profile.dart';
import 'package:studyverse/features/auth/domain/validators.dart';

void main() {
  group('Validators', () {
    test('email: dice qué le falta, con ejemplo', () {
      expect(Validators.email(''), 'Ingresá tu email');
      expect(Validators.email('ana'), 'Falta el @ en el email');
      expect(Validators.email('ana@'), 'Falta lo que va después del @, como gmail.com');
      expect(Validators.email('@gmail.com'), 'Falta lo que va antes del @');
      expect(Validators.email('ana@gmail'), 'Al email le falta el final, como .com');
      expect(Validators.email('ana@@gmail.com'), 'El email tiene más de un @');
      expect(Validators.email('ana lopez@gmail.com'), 'El email no puede tener espacios');
      expect(Validators.email('ana..lopez@gmail.com'), 'Ingresá un email válido, como nombre@ejemplo.com');
      expect(Validators.email('ana@gmail.c'), 'Ingresá un email válido, como nombre@ejemplo.com');
      expect(Validators.email(' ana@uni.edu.ar '), isNull);
      expect(Validators.email('ana.lopez+tp@gmail.com'), isNull);
    });

    test('email: sugiere el dominio bien escrito', () {
      expect(Validators.sugerenciaEmail('Ana@gmial.com'), 'Ana@gmail.com');
      expect(Validators.sugerenciaEmail('ana@hotmial.com'), 'ana@hotmail.com');
      expect(Validators.sugerenciaEmail('ana@gmail.com'), isNull);
      expect(Validators.sugerenciaEmail('ana@'), isNull);
    });

    test('password: pide 8 caracteres, minúscula, mayúscula y número', () {
      expect(Validators.password(''), 'Ingresá una contraseña');
      expect(Validators.password('abc'), 'Usá 8 caracteres o más');
      expect(Validators.password('abcdefgh'), 'La contraseña necesita una mayúscula y un número');
      expect(Validators.password('abcdefgh1'), 'La contraseña necesita una mayúscula');
      expect(Validators.password('Aa1${'x' * 70}'), 'Usá 72 caracteres como máximo');
      expect(Validators.password('Abcdefg1'), isNull);
    });

    test('requisitos de la contraseña, uno por uno', () {
      expect(RequisitoContrasena.values.where((r) => r.cumple('Prueba123!')).length, 4);
      expect(RequisitoContrasena.mayuscula.cumple('prueba123'), isFalse);
    });

    test('username', () {
      expect(Validators.username(''), 'Elegí un nombre de usuario');
      expect(Validators.username('ab'), 'Usá 3 caracteres o más');
      expect(Validators.username('a' * 21), 'Usá 20 caracteres como máximo');
      expect(Validators.username('ana maria'), 'Usá solo letras, números, punto (.) y guion bajo (_)');
      expect(Validators.username('.ana'), 'Tiene que empezar y terminar con una letra o un número');
      expect(Validators.username('ana..m'), 'No pongas dos símbolos seguidos');
      expect(Validators.username('Ana.Lopez_2'), isNull, reason: 'las mayúsculas se pasan a minúsculas');
    });

    test('código de 6 números', () {
      expect(Validators.codigo(''), 'Ingresá el código');
      expect(Validators.codigo('12a456'), 'El código tiene solo números');
      expect(Validators.codigo('12345'), 'El código tiene 6 números');
      expect(Validators.codigo('123 456'), isNull);
    });

    test('nombre', () {
      expect(Validators.nombre('   '), 'Ingresá tu nombre');
      expect(Validators.nombre('A'), 'El nombre es muy corto');
      expect(Validators.nombre('a' * 81), 'Usá 80 caracteres como máximo');
      expect(Validators.nombre('123'), 'Ingresá un nombre válido, como Ana García');
      expect(Validators.nombre('Grupo 4 & Co.'), isNull);
      expect(Validators.nombre('Ana'), isNull);
      expect(Validators.nombre("José O'Connor-Núñez"), isNull);
    });

    test('confirmar contraseña', () {
      final v = Validators.confirmarPassword(() => 'secreto123');
      expect(v(''), 'Confirmá la contraseña');
      expect(v('otra'), 'Las contraseñas no coinciden. Probá de nuevo');
      expect(v('secreto123'), isNull);
    });
  });

  group('Validar', () {
    test('texto obligatorio con largo máximo', () {
      final v = Validar.texto(vacio: 'Ingresá un nombre para el grupo', max: 5);
      expect(v('  '), 'Ingresá un nombre para el grupo');
      expect(v('123456'), 'Usá 5 caracteres como máximo');
      expect(v('TP 2'), isNull);
    });

    test('nombre de archivo', () {
      final v = Validar.nombreArchivo();
      expect(v(''), 'Ingresá un nombre');
      expect(v('TP: final'), r'No uses estos caracteres: / \ : * ? " < > |');
      expect(v('.oculto'), 'El nombre no puede empezar con un punto');
      expect(v('Informe.'), 'El nombre no puede terminar con un punto');
      expect(v('Informe final.docx'), isNull);
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

    test('foto subida a StudyVerse vs. foto de Google', () {
      expect(Profile.fromMap({...base, 'avatar_url': 'storage:u1/f.jpg'}).avatarPath, 'u1/f.jpg');
      expect(Profile.fromMap({...base, 'avatar_url': 'https://lh3.googleusercontent.com/x'}).avatarPath, isNull);
    });

    test('carrera y universidad', () {
      expect(Profile.fromMap(base).estudios, isNull);
      expect(Profile.fromMap({...base, 'carrera': 'Medicina', 'universidad': 'UBA'}).estudios, 'Medicina · UBA');
      expect(Profile.fromMap({...base, 'universidad': 'UBA'}).estudios, 'UBA');
    });

    test('CambiosPerfil: vacío borra, null no toca', () {
      expect(const CambiosPerfil(carrera: ' ').toMap(), {'carrera': null});
      expect(const CambiosPerfil(username: ' Ana.L ').toMap(), {'username': 'ana.l'});
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

    test('el código por mail es una pantalla de acceso', () {
      expect(authRedirect(loggedIn: false, location: '/codigo/entrar'), isNull);
      expect(authRedirect(loggedIn: true, location: '/codigo/registro'), Routes.grupos);
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
    expect(traducirErrorAuth('invalid_credentials', ''), 'El email o la contraseña no coinciden');
    expect(traducirErrorAuth('otp_expired', ''), contains('Pedí uno nuevo'));
    expect(traducirErrorAuth('algo_raro', 'boom'), 'Algo salió mal. Probá de nuevo');
  });

  test('errores del perfil', () {
    expect(traducirErrorPerfil('23505', 'duplicate key value violates unique constraint "profiles_username_unico"'),
        'Ese nombre de usuario ya está en uso');
    expect(traducirErrorPerfil('XX000', 'boom'), 'No se pudieron guardar los cambios');
  });

  test('dispositivos: nombre legible del navegador', () {
    expect(describirDispositivo('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36'),
        ('Chrome en Windows', false));
    expect(describirDispositivo('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0) AppleWebKit/605.1 Version/17.0 Mobile Safari/604.1'),
        ('Safari en iOS', false));
    expect(describirDispositivo('Mozilla/5.0 (Windows NT 10.0) Chrome/130.0 Edg/130.0'), ('Edge en Windows', false));
    expect(describirDispositivo('Dart/3.13 (dart:io)'), ('App de StudyVerse', true));
    expect(describirDispositivo(null), ('Dispositivo desconocido', false));
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
