import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../../notificaciones/presentation/notificaciones_providers.dart';
import '../data/supabase_entregas_repository.dart';
import '../domain/trabajo.dart';

final entregasRepositoryProvider = Provider<EntregasRepository>(
  (ref) => SupabaseEntregasRepository(ref.watch(supabaseClientProvider)),
);

/// Los trabajos del curso, por vencimiento. Se vuelven a leer cuando llega una
/// notificación (trabajo nuevo, entrega o nota).
final trabajosProvider = FutureProvider.autoDispose.family<List<Trabajo>, String>((ref, cursoId) {
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(entregasRepositoryProvider).trabajos(cursoId);
});

final trabajoProvider = FutureProvider.autoDispose.family<Trabajo, String>(
  (ref, id) => ref.watch(entregasRepositoryProvider).trabajo(id),
);

/// Todas las entregas del curso (docente).
final entregasDelCursoProvider = FutureProvider.autoDispose.family<List<Entrega>, String>((ref, cursoId) {
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(entregasRepositoryProvider).delCurso(cursoId);
});

/// Las entregas del grupo, por trabajo.
final entregasDelGrupoProvider = FutureProvider.autoDispose.family<Map<String, Entrega>, String>((ref, groupId) async {
  ref.watch(notificacionesCambiosProvider);
  final lista = await ref.watch(entregasRepositoryProvider).delGrupo(groupId);
  return {for (final e in lista) e.trabajoId: e};
});

/// Los trabajos del curso del grupo (vacío si el grupo no está en un curso).
final trabajosDelGrupoProvider = FutureProvider.autoDispose.family<List<Trabajo>, String>((ref, groupId) async {
  final cursoId = ref.watch(groupProvider(groupId).select((g) => g.value?.cursoId));
  if (cursoId == null) return const [];
  return ref.watch(trabajosProvider(cursoId).future);
});
