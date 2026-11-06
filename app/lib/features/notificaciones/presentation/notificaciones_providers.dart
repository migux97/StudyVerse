import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_notificaciones_repository.dart';
import '../domain/notificacion.dart';

final notificacionesRepositoryProvider = Provider<NotificacionesRepository>(
  (ref) => SupabaseNotificacionesRepository(ref.watch(supabaseClientProvider)),
);

/// Llegó una notificación nueva (contador: Riverpod solo avisa si cambia el valor).
final notificacionesCambiosProvider = StreamProvider<int>((ref) {
  final miId = ref.watch(authStateProvider.select((s) => s.value?.id));
  if (miId == null) return const Stream.empty();
  var n = 0;
  return ref.watch(notificacionesRepositoryProvider).cambios(miId).map((_) => ++n);
});

final notificacionesProvider = FutureProvider.autoDispose<List<Notificacion>>((ref) {
  if (ref.watch(authStateProvider).value == null) return const [];
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(notificacionesRepositoryProvider).recientes();
});

/// Cuántas hay sin leer (el número de la campanita).
final sinLeerProvider = FutureProvider<int>((ref) {
  if (ref.watch(authStateProvider).value == null) return 0;
  ref.watch(notificacionesCambiosProvider);
  return ref.watch(notificacionesRepositoryProvider).sinLeer();
});
