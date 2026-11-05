import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_files_repository.dart';
import '../domain/file_item.dart';
import '../domain/files_repository.dart';

final filesRepositoryProvider = Provider<FilesRepository>(
  (ref) => SupabaseFilesRepository(ref.watch(supabaseClientProvider)),
);

/// Cambios en vivo de carpetas/archivos/versiones del grupo. Emite un
/// contador porque Riverpod solo notifica si el valor cambia.
final filesChangesProvider = StreamProvider.family<int, String>((ref, groupId) {
  var n = 0;
  return ref.watch(filesRepositoryProvider).changes(groupId).map((_) => ++n);
});

/// Todas las carpetas del grupo (para navegar y armar los breadcrumbs).
final foldersProvider = FutureProvider.family<List<Folder>, String>((ref, groupId) {
  ref.watch(filesChangesProvider(groupId));
  return ref.watch(filesRepositoryProvider).folders(groupId);
});

/// Archivos de una carpeta (`folderId` null = raíz del grupo).
final filesProvider =
    FutureProvider.family<List<FileItem>, ({String groupId, String? folderId})>((ref, key) {
  ref.watch(filesChangesProvider(key.groupId));
  return ref.watch(filesRepositoryProvider).files(key.groupId, key.folderId);
});

/// Pedidos de liberación que me llegan a mí, en vivo, estés en la pantalla que estés.
final pedidosEntrantesProvider = StreamProvider<PedidoEntrante>((ref) {
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  if (miId == null) return const Stream.empty();
  return ref.watch(filesRepositoryProvider).pedidosEntrantes(miId);
});

/// Un archivo, en vivo (para el visor y el editor).
final fileProvider = FutureProvider.autoDispose.family<FileItem, ({String groupId, String fileId})>((ref, key) {
  ref.watch(filesChangesProvider(key.groupId));
  return ref.watch(filesRepositoryProvider).file(key.fileId);
});

/// Bytes de una versión. Se guardan mientras haya alguien mirándola.
final fileBytesProvider = FutureProvider.autoDispose.family<Uint8List, FileVersion>(
  (ref, v) => ref.watch(filesRepositoryProvider).bytes(v),
);

final versionsProvider =
    FutureProvider.family<List<FileVersion>, ({String groupId, String fileId})>((ref, key) {
  ref.watch(filesChangesProvider(key.groupId));
  return ref.watch(filesRepositoryProvider).versions(key.fileId);
});
