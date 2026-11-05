import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_calendario_repository.dart';
import '../domain/calendario.dart';

final calendarioRepositoryProvider = Provider<CalendarioRepository>(
  (ref) => SupabaseCalendarioRepository(ref.watch(supabaseClientProvider)),
);

/// Fechas de los días que se ven en la grilla del mes ([mes] = día 1).
final fechasDelMesProvider = FutureProvider.autoDispose.family<List<FechaCalendario>, DateTime>((ref, mes) {
  final dias = diasDeLaGrilla(mes);
  return ref.watch(calendarioRepositoryProvider).fechas(dias.first, dias.last);
});

/// Lo que viene en la próxima semana (para "Mis grupos").
final proximasFechasProvider = FutureProvider.autoDispose<List<FechaCalendario>>((ref) async {
  final hoy = soloDia(DateTime.now());
  final fechas = await ref.watch(calendarioRepositoryProvider).fechas(hoy, hoy.add(const Duration(days: 7)));
  return proximas(fechas, hoy);
});
