import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_groups_repository.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>(
  (ref) => SupabaseGroupsRepository(ref.watch(supabaseClientProvider)),
);

/// Avisa (en vivo) que algo cambió en mis grupos o sus integrantes.
/// Emite un contador: Riverpod solo notifica si el valor cambia, así que
/// emitir siempre `null` dejaría de avisar después del primer evento.
final groupsChangesProvider = StreamProvider<int>((ref) {
  ref.watch(authStateProvider.select((s) => s.value?.id));
  var n = 0;
  return ref.watch(groupsRepositoryProvider).changes().map((_) => ++n);
});

final myGroupsProvider = FutureProvider<List<Group>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  ref.watch(groupsChangesProvider);
  return ref.watch(groupsRepositoryProvider).myGroups();
});

final groupProvider = FutureProvider.family<Group, String>((ref, groupId) {
  ref.watch(groupsChangesProvider);
  return ref.watch(groupsRepositoryProvider).getGroup(groupId);
});

final groupMembersProvider = FutureProvider.family<List<GroupMember>, String>((ref, groupId) {
  ref.watch(groupsChangesProvider);
  return ref.watch(groupsRepositoryProvider).members(groupId);
});
