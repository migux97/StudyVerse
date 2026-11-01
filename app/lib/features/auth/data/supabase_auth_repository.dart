import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/auth_repository.dart';
import '../domain/profile.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  static SessionUser? _map(User? u) => u == null ? null : SessionUser(id: u.id, email: u.email);

  @override
  SessionUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<SessionUser?> authStateChanges() =>
      _auth.onAuthStateChange.map((s) => _map(s.session?.user));

  @override
  Future<void> signInWithEmail({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<bool> signUpWithEmail({
    required String nombre,
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final res = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'nombre': nombre.trim()},
          emailRedirectTo: kIsWeb ? null : Env.authRedirectMobile,
        );
        return res.session != null;
      });

  @override
  Future<void> signInWithGoogle() => _guard(() => _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : Env.authRedirectMobile,
      ));

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: kIsWeb ? null : Env.authRedirectMobile,
      ));

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AuthException catch (e) {
      throw AuthFailure(traducirErrorAuth(e.code, e.message));
    }
  }
}

/// Traduce los errores de Supabase Auth a mensajes en español.
String traducirErrorAuth(String? code, String message) {
  switch (code) {
    case 'invalid_credentials':
      return 'Email o contraseña incorrectos';
    case 'email_not_confirmed':
      return 'Tenés que confirmar tu email antes de entrar';
    case 'user_already_exists':
    case 'email_exists':
      return 'Ya existe una cuenta con ese email';
    case 'weak_password':
      return 'La contraseña es muy débil';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Demasiados intentos. Probá de nuevo en unos minutos';
    case 'provider_disabled':
      return 'Este método de inicio de sesión no está habilitado';
  }
  return 'No se pudo completar la operación. Intentá de nuevo';
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<Profile> fetchProfile(String userId) async {
    final row = await _client.from('profiles').select().eq('id', userId).single();
    return Profile.fromMap(row);
  }

  @override
  Future<Profile> updateNombre(String userId, String nombre) async {
    final row = await _client
        .from('profiles')
        .update({'nombre': nombre.trim()})
        .eq('id', userId)
        .select()
        .single();
    return Profile.fromMap(row);
  }
}
