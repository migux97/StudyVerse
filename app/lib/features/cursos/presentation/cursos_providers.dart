import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../data/supabase_cursos_repository.dart';
import '../domain/curso.dart';

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
