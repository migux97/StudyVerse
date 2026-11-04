import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../domain/auth_repository.dart';
import '../domain/cuenta.dart';
import '../domain/profile.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;
  String? get _redirect => kIsWeb ? null : Env.authRedirectMobile;

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
  Future<void> signUpWithEmail({
    required String nombre,
    required String username,
    required String email,
    required String password,
  }) =>
      _guard(() => _auth.signUp(
            email: email.trim(),
            password: password,
            data: {'nombre': nombre.trim(), 'username': username.trim().toLowerCase()},
            emailRedirectTo: _redirect,
          ));

  @override
  Future<bool> usernameDisponible(String username) => _guard(() async =>
      await _client.rpc('username_disponible', params: {'p_username': username}) as bool);

  @override
  Future<void> enviarCodigo(String email, MotivoCodigo motivo) => _guard(() async {
        final e = email.trim();
        switch (motivo) {
          case MotivoCodigo.registro:
            await _auth.resend(email: e, type: OtpType.signup, emailRedirectTo: _redirect);
          case MotivoCodigo.entrar:
            await _auth.signInWithOtp(email: e, shouldCreateUser: false, emailRedirectTo: _redirect);
          case MotivoCodigo.recuperar:
            await _auth.resetPasswordForEmail(e, redirectTo: _redirect);
        }
      });

  @override
  Future<void> verificarCodigo(String email, String codigo, MotivoCodigo motivo, {String? nuevaPassword}) =>
      _guard(() async {
        await _auth.verifyOTP(
          email: email.trim(),
          token: codigo.replaceAll(RegExp(r'\s'), ''),
          type: switch (motivo) {
            MotivoCodigo.registro => OtpType.signup,
            MotivoCodigo.entrar => OtpType.email,
            MotivoCodigo.recuperar => OtpType.recovery,
          },
        );
        if (motivo == MotivoCodigo.recuperar && nuevaPassword != null) {
          try {
            await _auth.updateUser(UserAttributes(password: nuevaPassword));
          } on AuthException catch (e) {
            // La sesión ya quedó iniciada y el router lleva a la app: el aviso
            // tiene que salir por el messenger de la app.
            throw AuthFailure(
              'Entraste, pero no pudimos cambiar la contraseña: ${traducirErrorAuth(e.code, e.message).toLowerCase()}. '
              'Cambiala desde Tu cuenta',
              codigo: 'recuperacion_incompleta',
            );
          }
          // Como en Google: al cambiar la contraseña se cierran las demás sesiones.
          await _auth.signOut(scope: SignOutScope.others);
        }
      });

  @override
  Future<void> signInWithGoogle() =>
      _guard(() => _auth.signInWithOAuth(OAuthProvider.google, redirectTo: _redirect));

  @override
  Future<void> cambiarPassword(String nueva, {String? codigo}) => _guard(() async {
        await _auth.updateUser(UserAttributes(password: nueva, nonce: codigo));
        await _auth.signOut(scope: SignOutScope.others);
      });

  @override
  Future<void> pedirCodigoParaCambiarPassword() => _guard(_auth.reauthenticate);

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  @override
  Future<void> cerrarOtrasSesiones() => _guard(() => _auth.signOut(scope: SignOutScope.others));

  @override
  Future<List<Dispositivo>> dispositivos() => _guard(() async {
        final rows = await _client.rpc('mis_sesiones') as List;
        return rows.map((r) => Dispositivo.fromMap(r as Map<String, dynamic>)).toList();
      });

  @override
  Future<void> cerrarDispositivo(String id) =>
      _guard(() => _client.rpc('cerrar_sesion', params: {'p_session_id': id}));

  @override
  Future<List<CuentaVinculada>> cuentasVinculadas() => _guard(() async {
        final ids = await _auth.getUserIdentities();
        return [
          for (final i in ids)
            CuentaVinculada(
              id: i.identityId,
              proveedor: i.provider,
              email: i.identityData?['email'] as String?,
            ),
        ];
      });

  @override
  Future<void> vincularGoogle() =>
      _guard(() => _auth.linkIdentity(OAuthProvider.google, redirectTo: _redirect));

  @override
  Future<void> desvincular(String identityId) => _guard(() async {
        final ids = await _auth.getUserIdentities();
        if (ids.length < 2) throw const AuthFailure('Necesitás al menos una forma de entrar');
        await _auth.unlinkIdentity(ids.firstWhere((i) => i.identityId == identityId));
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AuthException catch (e) {
      throw AuthFailure(traducirErrorAuth(e.code, e.message), codigo: e.code);
    } on PostgrestException catch (e) {
      throw AuthFailure(e.code == 'P0001' ? e.message : 'Algo salió mal. Probá de nuevo');
    } on AuthFailure {
      rethrow;
    } on Exception {
      // Sin conexión (ClientException, SocketException, timeouts).
      throw const AuthFailure(sinConexion, codigo: 'sin_conexion');
    }
  }
}

const sinConexion = 'No hay conexión. Revisá tu internet y probá de nuevo';

/// Traduce los errores de Supabase Auth a mensajes cortos, como los de Google.
String traducirErrorAuth(String? code, String message) {
  switch (code) {
    case 'invalid_credentials':
      return 'El email o la contraseña no coinciden';
    case 'email_not_confirmed':
      return 'Primero confirmá tu email con el código que te mandamos';
    case 'user_already_exists':
    case 'email_exists':
      return 'Ya hay una cuenta con ese email';
    case 'weak_password':
      return 'Elegí una contraseña más segura';
    case 'same_password':
      return 'Elegí una contraseña distinta a la actual';
    case 'otp_expired':
      return 'El código venció o no es correcto. Pedí uno nuevo';
    case 'otp_disabled':
    case 'user_not_found':
      return 'No hay ninguna cuenta con ese email';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Hiciste muchos intentos seguidos. Esperá un ratito';
    case 'provider_disabled':
      return 'Esta forma de entrar todavía no está disponible';
    case 'identity_already_exists':
      return 'Esa cuenta de Google ya está conectada a otro usuario';
    case 'single_identity_not_deletable':
      return 'Necesitás al menos una forma de entrar';
    case 'manual_linking_disabled':
      return 'Por ahora no se pueden conectar otras cuentas';
    case 'reauthentication_needed':
    case 'reauthentication_not_valid':
      return 'Confirmá que sos vos con el código que te mandamos';
  }
  return 'Algo salió mal. Probá de nuevo';
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final SupabaseClient _client;

  StorageFileApi get _fotos => _client.storage.from('avatares');

  @override
  Future<Profile> fetchProfile(String userId) => _guard(() async {
        final row = await _client.from('profiles').select().eq('id', userId).single();
        return Profile.fromMap(row);
      });

  @override
  Future<Profile> actualizar(String userId, CambiosPerfil cambios) => _guard(() async {
        final row = await _client
            .from('profiles')
            .update(cambios.toMap())
            .eq('id', userId)
            .select()
            .single();
        return Profile.fromMap(row);
      });

  @override
  Future<Profile> subirFoto(String userId, Uint8List jpeg) => _guard(() async {
        final anterior = (await fetchProfile(userId)).avatarPath;
        // Nombre nuevo en cada cambio: así no queda en caché la foto vieja.
        final ruta = '$userId/${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}.jpg';
        await _fotos.uploadBinary(ruta, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        final row = await _client.rpc('set_avatar', params: {'p_path': ruta}).single();
        if (anterior != null) await _borrarSinFallar(anterior);
        return Profile.fromMap(row);
      });

  @override
  Future<Profile> quitarFoto(String userId) => _guard(() async {
        final anterior = (await fetchProfile(userId)).avatarPath;
        final row = await _client.rpc('quitar_avatar').single();
        if (anterior != null) await _borrarSinFallar(anterior);
        return Profile.fromMap(row);
      });

  @override
  String urlFoto(String path) => _fotos.getPublicUrl(path);

  Future<void> _borrarSinFallar(String ruta) async {
    try {
      await _fotos.remove([ruta]);
    } on StorageException {
      // La foto vieja queda en el bucket; no afecta al perfil.
    }
  }

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw AuthFailure(traducirErrorPerfil(e.code, e.message));
    } on StorageException catch (e) {
      throw AuthFailure(e.statusCode == '413'
          ? 'La foto es muy pesada'
          : 'No se pudo subir la foto. Probá de nuevo');
    } on AuthFailure {
      rethrow;
    } on Exception {
      throw const AuthFailure(sinConexion, codigo: 'sin_conexion');
    }
  }
}

String traducirErrorPerfil(String? code, String message) {
  if (code == '23505' && message.contains('username')) return 'Ese nombre de usuario ya está en uso';
  if (code == '23514' && message.contains('username')) return 'Ese nombre de usuario no es válido';
  if (code == 'P0001' || code == 'P0002') return message;
  return 'No se pudieron guardar los cambios';
}
