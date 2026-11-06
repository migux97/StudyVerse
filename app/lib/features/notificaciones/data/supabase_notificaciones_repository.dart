import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/realtime/canales.dart';
import '../domain/notificacion.dart';

class SupabaseNotificacionesRepository implements NotificacionesRepository {
  SupabaseNotificacionesRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Notificacion>> recientes({int limite = 50}) => _guard(() async {
        final rows = await _client
            .from('notificaciones')
            .select('id, tipo, titulo, cuerpo, ruta, created_at, leida_at')
            .order('created_at', ascending: false)
            .limit(limite);
        return rows.map(Notificacion.fromMap).toList();
      });

  @override
  Future<int> sinLeer() => _guard(() async {
        final r = await _client.from('notificaciones').select('id').isFilter('leida_at', null).count(CountOption.exact);
        return r.count;
      });

  @override
  Future<void> marcarLeida(String id) => _guard(() => _client
      .from('notificaciones')
      .update({'leida_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id)
      .isFilter('leida_at', null));

  @override
  Future<void> marcarTodas() => _guard(() => _client
      .from('notificaciones')
      .update({'leida_at': DateTime.now().toUtc().toIso8601String()})
      .isFilter('leida_at', null));

  @override
  Stream<void> cambios(String miId) => escucharCanal(_client, Canales.notificaciones(miId));

  @override
  Future<void> registrarDispositivo(String token, String plataforma) => _guard(() =>
      _client.rpc('registrar_dispositivo', params: {'p_token': token, 'p_plataforma': plataforma}));

  @override
  Future<void> quitarDispositivo(String token) =>
      _guard(() => _client.rpc('quitar_dispositivo', params: {'p_token': token}));

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException {
      throw const NotificacionesFailure('Algo salió mal. Probá de nuevo');
    } on Exception {
      throw const NotificacionesFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
