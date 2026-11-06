import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../data/supabase_cursos_repository.dart';
import '../domain/curso.dart';
import '../../notificaciones/presentation/notificaciones_providers.dart';

final cursosRepositoryProvider = Provider<CursosRepository>(
  (ref) => SupabaseCursosRepository(ref.watch(supabaseClientProvider)),
);

/// Los cursos que doy. Se vuelve a leer cuando cambian mis grupos (en vivo) o
/// al volver a la pantalla.
final misCursosProvider = FutureProvider.autoDispose<List<Curso>>((ref) {
  if (ref.watch(authStateProvider).value == null) return const [];
  ref.watch(groupsChangesProvider);
  return ref.watch(cursosRepositoryProvider).misCursos();
});

final cursoProvider = FutureProvider.autoDispose.family<Curso, String>(
  (ref, id) => ref.watch(cursosRepositoryProvider).curso(id),
);

final gruposDelCursoProvider = FutureProvider.autoDispose.family<List<GrupoDelCurso>, String>((ref, id) {
  ref.watch(groupsChangesProvider);
  return ref.watch(cursosRepositoryProvider).grupos(id);
});

/// Filtro "solo los grupos sin actividad" del tablero de cada curso.
class SoloInactivos extends Notifier<bool> {
  SoloInactivos(this.cursoId);
  final String cursoId;

  @override
  bool build() => false;

  void poner(bool v) => state = v;
}

final soloInactivosProvider = NotifierProvider.autoDispose.family<SoloInactivos, bool, String>(SoloInactivos.new);

/// ¿Soy quien creó el curso? (los ayudantes no lo cambian ni suman docentes).
final soyTitularProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(cursosRepositoryProvider).soyTitular(id),
);

final docentesDelCursoProvider = FutureProvider.autoDispose.family<List<DocenteDelCurso>, String>(
  (ref, id) => ref.watch(cursosRepositoryProvider).docentes(id),
);

final aportesDelCursoProvider = FutureProvider.autoDispose.family<List<AporteAlumno>, String>((ref, id) {
  ref.watch(groupsChangesProvider);
  return ref.watch(cursosRepositoryProvider).aportes(id);
});

final materialProvider = FutureProvider.autoDispose.family<List<MaterialCurso>, String>((ref, id) {
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(cursosRepositoryProvider).material(id);
});

final fechasCursoProvider = FutureProvider.autoDispose.family<List<FechaCurso>, String>(
  (ref, id) => ref.watch(cursosRepositoryProvider).fechas(id),
);
