import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/cuenta.dart';
import '../domain/foto.dart';
import '../domain/profile.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);

final authStateProvider = StreamProvider<SessionUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.currentUser;
  yield* repo.authStateChanges();
});

/// Perfil del usuario con sesión iniciada. Los cambios devuelven el error (o
/// null) en vez de dejar el perfil en estado de error.
class CurrentProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return null;
    return ref.read(profileRepositoryProvider).fetchProfile(user.id);
  }

  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  Future<String?> actualizar(CambiosPerfil cambios) =>
      _aplicar((p) => _repo.actualizar(p.id, cambios));

  /// [original] es el archivo elegido; se recorta y achica antes de subirlo.
  Future<String?> subirFoto(Uint8List original) async {
    final jpeg = await compute(prepararFoto, original);
    if (jpeg == null) return 'Esa imagen no se puede abrir. Probá con una JPG o PNG';
    return _aplicar((p) => _repo.subirFoto(p.id, jpeg));
  }

  Future<String?> quitarFoto() => _aplicar((p) => _repo.quitarFoto(p.id));

  Future<String?> _aplicar(Future<Profile> Function(Profile actual) cambio) async {
    final actual = state.value;
    if (actual == null) return null;
    try {
      state = AsyncData(await cambio(actual));
      return null;
    } on AuthFailure catch (e) {
      return e.mensaje;
    }
  }
}

final currentProfileProvider =
    AsyncNotifierProvider<CurrentProfileNotifier, Profile?>(CurrentProfileNotifier.new);

final dispositivosProvider = FutureProvider.autoDispose<List<Dispositivo>>(
  (ref) => ref.watch(authRepositoryProvider).dispositivos(),
);

final cuentasVinculadasProvider = FutureProvider.autoDispose<List<CuentaVinculada>>(
  (ref) => ref.watch(authRepositoryProvider).cuentasVinculadas(),
);
