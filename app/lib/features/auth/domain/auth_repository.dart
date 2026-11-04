import 'dart:typed_data';

import '../../../core/errors.dart';
import 'cuenta.dart';
import 'profile.dart';

/// Usuario autenticado, independiente del SDK de Supabase.
class SessionUser {
  const SessionUser({required this.id, this.email});
  final String id;
  final String? email;
}

/// Error de autenticación con un mensaje listo para mostrar.
class AuthFailure extends AppFailure {
  const AuthFailure(super.mensaje, {this.codigo});

  /// Código de Supabase Auth (`invalid_credentials`, …), para decidir dónde mostrarlo.
  final String? codigo;
}

/// Para qué es el código de 6 dígitos que llega por correo.
enum MotivoCodigo {
  /// Confirmar el email de una cuenta nueva.
  registro,

  /// Entrar sin contraseña.
  entrar,

  /// Elegir una contraseña nueva.
  recuperar,
}

abstract interface class AuthRepository {
  SessionUser? get currentUser;
  Stream<SessionUser?> authStateChanges();

  Future<void> signInWithEmail({required String email, required String password});

  /// Crea la cuenta y manda el código para confirmar el email.
  Future<void> signUpWithEmail({
    required String nombre,
    required String username,
    required String email,
    required String password,
  });

  Future<bool> usernameDisponible(String username);

  /// Manda (o reenvía) el código por correo.
  Future<void> enviarCodigo(String email, MotivoCodigo motivo);

  /// Verifica el código; si es correcto queda la sesión iniciada. Para
  /// [MotivoCodigo.recuperar] hay que pasar la contraseña nueva.
  Future<void> verificarCodigo(String email, String codigo, MotivoCodigo motivo, {String? nuevaPassword});

  Future<void> signInWithGoogle();
  /// Cambia la contraseña. Si el último login no es reciente, falla con
  /// `codigo: 'reauthentication_needed'`: hay que pedir un código con
  /// [pedirCodigoParaCambiarPassword] y volver a llamar con [codigo].
  Future<void> cambiarPassword(String nueva, {String? codigo});
  Future<void> pedirCodigoParaCambiarPassword();
  Future<void> signOut();

  /// Cierra la sesión en todos los dispositivos menos este.
  Future<void> cerrarOtrasSesiones();

  Future<List<Dispositivo>> dispositivos();
  Future<void> cerrarDispositivo(String id);

  Future<List<CuentaVinculada>> cuentasVinculadas();
  Future<void> vincularGoogle();
  Future<void> desvincular(String identityId);
}

abstract interface class ProfileRepository {
  Future<Profile> fetchProfile(String userId);
  Future<Profile> actualizar(String userId, CambiosPerfil cambios);

  /// Sube la foto (ya recortada y en JPEG) y la deja como avatar.
  Future<Profile> subirFoto(String userId, Uint8List jpeg);
  Future<Profile> quitarFoto(String userId);

  /// URL pública de una foto subida a StudyVerse (ver [Profile.avatarPath]).
  String urlFoto(String path);
}
