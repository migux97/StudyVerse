import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_comentarios_repository.dart';
import '../domain/comentario.dart';

final comentariosRepositoryProvider = Provider<ComentariosRepository>(
  (ref) => SupabaseComentariosRepository(ref.watch(supabaseClientProvider)),
);

typedef ClaveComentarios = ({String groupId, String fileId});

/// Contador que sube cada vez que cambian los comentarios de este archivo.
final _cambiosProvider = StreamProvider.autoDispose.family<int, ClaveComentarios>((ref, key) {
  var n = 0;
  return ref
      .watch(comentariosRepositoryProvider)
      .cambios(key.groupId)
      .where((id) => id == key.fileId)
      .map((_) => ++n);
});

/// Comentarios de un archivo, en vivo.
final comentariosProvider = FutureProvider.autoDispose.family<List<Comentario>, ClaveComentarios>((ref, key) {
  ref.watch(_cambiosProvider(key));
  return ref.watch(comentariosRepositoryProvider).comentarios(key.fileId);
});

/// Me mencionaron en un comentario (para avisar en cualquier pantalla).
final mencionesProvider = StreamProvider<Comentario>((ref) {
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  if (miId == null) return const Stream.empty();
  return ref.watch(comentariosRepositoryProvider).menciones(miId);
});

/// El fragmento del documento que está marcado, para comentarlo citándolo.
class CitaController extends Notifier<String?> {
  CitaController(this.fileId);
  final String fileId;

  @override
  String? build() => null;

  void poner(String? cita) => state = cita;
}

/// Por archivo. La pantalla del documento la mantiene viva (en el celular se
/// marca el texto y después se abre la hoja de comentarios); al salir se descarta.
final citaProvider = NotifierProvider.autoDispose.family<CitaController, String?, String>(CitaController.new);
