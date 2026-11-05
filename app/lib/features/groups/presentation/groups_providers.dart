import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_groups_repository.dart';
import '../data/supabase_telegram_repository.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import '../domain/telegram.dart';

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

/// Si veo el grupo en solo lectura (soy su docente, no integrante).
final soloLecturaProvider = Provider.family<bool, String>(
  (ref, groupId) => ref.watch(groupProvider(groupId)).value?.soloLectura ?? false,
);

final groupMembersProvider = FutureProvider.family<List<GroupMember>, String>((ref, groupId) {
  ref.watch(groupsChangesProvider);
  return ref.watch(groupsRepositoryProvider).members(groupId);
});

final telegramRepositoryProvider = Provider<TelegramRepository>(
  (ref) => SupabaseTelegramRepository(ref.watch(supabaseClientProvider)),
);

/// Cambios en vivo de los chats vinculados (p. ej. cuando alguien manda
/// /vincular desde Telegram con la pantalla abierta).
final telegramChangesProvider = StreamProvider.family<int, String>((ref, groupId) {
  var n = 0;
  return ref.watch(telegramRepositoryProvider).changes(groupId).map((_) => ++n);
});

final telegramLinksProvider = FutureProvider.family<List<TelegramLink>, String>((ref, groupId) {
  ref.watch(telegramChangesProvider(groupId));
  return ref.watch(telegramRepositoryProvider).links(groupId);
});
