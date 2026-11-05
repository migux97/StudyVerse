import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../files/presentation/files_providers.dart';
import '../data/supabase_documentos_repository.dart';
import '../domain/documento.dart';

final documentosRepositoryProvider = Provider<DocumentosRepository>(
  (ref) => SupabaseDocumentosRepository(ref.watch(supabaseClientProvider)),
);

typedef ClaveDocumento = ({String groupId, String fileId});

/// Contador que sube cada vez que cambia el borrador de este documento.
final _cambiosDelDocumentoProvider = StreamProvider.autoDispose.family<int, ClaveDocumento>((ref, key) {
  var n = 0;
  return ref
      .watch(documentosRepositoryProvider)
      .cambios(key.groupId)
      .where((id) => id == key.fileId)
      .map((_) => ++n);
});

/// Lo último del documento: el borrador si alguien lo está editando, o la
/// versión guardada. Se actualiza en vivo.
final contenidoDocumentoProvider =
    FutureProvider.autoDispose.family<ContenidoDocumento, ClaveDocumento>((ref, key) async {
  ref.watch(_cambiosDelDocumentoProvider(key));
  final archivo = await ref.watch(fileProvider(key).future);
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  final v = archivo.current;
  final borrador = borradorVigente(
    await ref.read(documentosRepositoryProvider).borrador(key.fileId),
    bloqueadoPor: archivo.lockedBy,
    bloqueoVigente: archivo.estaBloqueado(DateTime.now()),
    miId: miId,
    versionActual: v?.versionNumber,
  );
  if (borrador != null) return borrador;
  if (v == null) return const ContenidoDocumento(ops: [{'insert': '\n'}]);
  final bytes = await ref.watch(fileBytesProvider(v).future);
  return ContenidoDocumento(ops: opsDeVersion(bytes), actualizado: v.createdAt);
});
