import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
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

/// Perfil del usuario con sesión iniciada.
class CurrentProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final user = ref.watch(authStateProvider).value;
    if (user == null) return null;
    return ref.read(profileRepositoryProvider).fetchProfile(user.id);
  }

  Future<void> updateNombre(String nombre) async {
    final actual = state.value;
    if (actual == null) return;
    state = await AsyncValue.guard(
      () => ref.read(profileRepositoryProvider).updateNombre(actual.id, nombre),
    );
  }
}

final currentProfileProvider =
    AsyncNotifierProvider<CurrentProfileNotifier, Profile?>(CurrentProfileNotifier.new);
