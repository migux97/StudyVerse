import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../../notificaciones/presentation/notificaciones_providers.dart';
import '../data/supabase_cuestionarios_repository.dart';
import '../domain/cuestionario.dart';

final cuestionariosRepositoryProvider = Provider<CuestionariosRepository>(
  (ref) => SupabaseCuestionariosRepository(ref.watch(supabaseClientProvider)),
);

/// Los cuestionarios del curso (el alumno ve solo los publicados). Se vuelven a
/// leer cuando llega una notificación (uno nuevo o una corrección).
final cuestionariosProvider = FutureProvider.autoDispose.family<List<Cuestionario>, String>((ref, cursoId) {
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(cuestionariosRepositoryProvider).delCurso(cursoId);
});

final cuestionarioProvider = FutureProvider.autoDispose.family<Cuestionario, String>(
  (ref, id) => ref.watch(cuestionariosRepositoryProvider).cuestionario(id),
);

/// Los cuestionarios del curso del grupo (vacío si no está en un curso).
final cuestionariosDelGrupoProvider = FutureProvider.autoDispose.family<List<Cuestionario>, String>((ref, groupId) async {
  final cursoId = ref.watch(groupProvider(groupId).select((g) => g.value?.cursoId));
  if (cursoId == null) return const [];
  return ref.watch(cuestionariosProvider(cursoId).future);
});

/// Docente: las preguntas con sus respuestas correctas.
final preguntasConClaveProvider = FutureProvider.autoDispose.family<List<Pregunta>, String>(
  (ref, id) => ref.watch(cuestionariosRepositoryProvider).preguntasConClave(id),
);

/// Docente: cada alumno con sus intentos.
final resultadosProvider = FutureProvider.autoDispose.family<List<ResultadoAlumno>, String>(
  (ref, id) => ref.watch(cuestionariosRepositoryProvider).resultados(id),
);

/// Alumno: mis intentos de un cuestionario.
final misIntentosProvider = FutureProvider.autoDispose.family<List<Intento>, String>((ref, id) {
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(cuestionariosRepositoryProvider).misIntentos(id);
});

final detalleIntentoProvider = FutureProvider.autoDispose.family<DetalleIntento, String>(
  (ref, id) => ref.watch(cuestionariosRepositoryProvider).detalle(id),
);
