import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_activity_repository.dart';
import '../domain/activity_item.dart';
import '../domain/activity_repository.dart';

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => SupabaseActivityRepository(ref.watch(supabaseClientProvider)),
);

/// Eventos nuevos en vivo (contador: Riverpod solo avisa si cambia el valor).
final activityChangesProvider = StreamProvider.family<int, String>((ref, groupId) {
  var n = 0;
  return ref.watch(activityRepositoryProvider).changes(groupId).map((_) => ++n);
});

final activityProvider = FutureProvider.family<List<ActivityItem>, String>((ref, groupId) {
  ref.watch(activityChangesProvider(groupId));
  return ref.watch(activityRepositoryProvider).feed(groupId);
});
