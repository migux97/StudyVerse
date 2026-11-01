import 'profile.dart';

/// Usuario autenticado, independiente del SDK de Supabase.
class SessionUser {
  const SessionUser({required this.id, this.email});
  final String id;
  final String? email;
}

/// Error de autenticación con un mensaje listo para mostrar.
class AuthFailure implements Exception {
  const AuthFailure(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

abstract interface class AuthRepository {
  SessionUser? get currentUser;
  Stream<SessionUser?> authStateChanges();

  Future<void> signInWithEmail({required String email, required String password});

  /// Devuelve `true` si la cuenta quedó con sesión iniciada, `false` si hay
  /// que confirmar el email primero.
  Future<bool> signUpWithEmail({
    required String nombre,
    required String email,
    required String password,
  });

  Future<void> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

abstract interface class ProfileRepository {
  Future<Profile> fetchProfile(String userId);
  Future<Profile> updateNombre(String userId, String nombre);
}
