import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../../tasks/presentation/tasks_providers.dart';
import '../data/supabase_avisos_repository.dart';
import '../domain/aviso.dart';

final avisosRepositoryProvider = Provider<AvisosRepository>(
  (ref) => SupabaseAvisosRepository(ref.watch(supabaseClientProvider)),
);

/// Avisos nuevos en el grupo (contador: Riverpod solo avisa si cambia el valor).
final avisosCambiosProvider = StreamProvider.family<int, String>((ref, groupId) {
  var n = 0;
  return ref.watch(avisosRepositoryProvider).cambios(groupId).map((_) => ++n);
});

/// Los avisos que ve el grupo, del más nuevo al más viejo. Vacío si el grupo
/// no está en un curso.
final avisosDelGrupoProvider = FutureProvider.autoDispose.family<List<AvisoDocente>, String>((ref, groupId) async {
  final cursoId = ref.watch(groupProvider(groupId).select((g) => g.value?.cursoId));
  if (cursoId == null) return const [];
  ref.watch(avisosCambiosProvider(groupId));
  return ref.watch(avisosRepositoryProvider).delGrupo(groupId, cursoId);
});

final avisosDelCursoProvider = FutureProvider.autoDispose.family<List<AvisoDocente>, String>(
  (ref, cursoId) => ref.watch(avisosRepositoryProvider).delCurso(cursoId),
);

/// Devoluciones de las tareas del grupo, agrupadas por tarea (en vivo con las tareas).
final devolucionesProvider = FutureProvider.autoDispose.family<Map<String, List<Devolucion>>, String>(
  (ref, groupId) async {
    ref.watch(tasksChangesProvider(groupId));
    final lista = await ref.watch(avisosRepositoryProvider).devoluciones(groupId);
    final porTarea = <String, List<Devolucion>>{};
    for (final d in lista) {
      porTarea.putIfAbsent(d.taskId, () => []).add(d);
    }
    return porTarea;
  },
);

/// Avisos y devoluciones que me llegan, para mostrarlos en cualquier pantalla.
final avisosEntrantesProvider = StreamProvider<AvisoEntrante>((ref) {
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  if (miId == null) return const Stream.empty();
  return ref.watch(avisosRepositoryProvider).entrantes(miId);
});
