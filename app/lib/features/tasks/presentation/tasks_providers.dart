import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/presentation/activity_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_tasks_repository.dart';
import '../domain/task.dart';
import '../domain/tasks_repository.dart';

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => SupabaseTasksRepository(ref.watch(supabaseClientProvider)),
);

/// Cambios en vivo de las tareas (contador: Riverpod solo avisa si cambia el valor).
final tasksChangesProvider = StreamProvider.family<int, String>((ref, groupId) {
  var n = 0;
  return ref.watch(tasksRepositoryProvider).changes(groupId).map((_) => ++n);
});

final tasksProvider = FutureProvider.family<List<Task>, String>((ref, groupId) {
  ref.watch(tasksChangesProvider(groupId));
  return ref.watch(tasksRepositoryProvider).tasks(groupId);
});

/// "Ana aprobó tu tarea": avisos de revisión de mis entregas, en vivo.
final revisionesProvider = StreamProvider<Revision>((ref) {
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  if (miId == null) return const Stream.empty();
  return ref.watch(tasksRepositoryProvider).revisiones(miId);
});

/// Los aportes cambian con cualquier actividad (versiones, tareas, integrantes).
final contributionsProvider = FutureProvider.family<List<Aporte>, String>((ref, groupId) {
  ref.watch(activityChangesProvider(groupId));
  return ref.watch(tasksRepositoryProvider).contributions(groupId);
});
