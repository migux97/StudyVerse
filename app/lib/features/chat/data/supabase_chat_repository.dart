import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/realtime/canales.dart';
import '../domain/mensaje.dart';

const _select = '*, autor_perfil:profiles!mensajes_autor_fkey(*), archivo:files(nombre), '
    'respondido:responde_a(id, texto, borrado_at, '
    'autor_perfil:profiles!mensajes_autor_fkey(nombre))';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Mensaje>> pagina(String groupId, {DateTime? antesDe, int limite = 50}) => _guard(() async {
        var q = _client.from('mensajes').select(_select).eq('group_id', groupId);
        if (antesDe != null) q = q.lt('created_at', antesDe.toUtc().toIso8601String());
        final rows = await q.order('created_at', ascending: false).limit(limite);
        return rows.map(Mensaje.fromMap).toList();
      });

  @override
  Future<Mensaje?> mensaje(String id) => _guard(() async {
        final row = await _client.from('mensajes').select(_select).eq('id', id).maybeSingle();
        return row == null ? null : Mensaje.fromMap(row);
      });

  @override
  Future<Mensaje> enviar({required String groupId, String? texto, String? fileId, String? respondeA}) =>
      _guard(() async => Mensaje.fromMap(await _client
          .from('mensajes')
          .insert({
            'group_id': groupId,
            'autor': _client.auth.currentUser!.id,
            'texto': texto,
            'file_id': fileId,
            'responde_a': respondeA,
          })
          .select(_select)
          .single()));

  @override
  Future<Mensaje> editar(String id, String texto) => _guard(() async =>
      Mensaje.fromMap(await _client.from('mensajes').update({'texto': texto}).eq('id', id).select(_select).single()));

  @override
  Future<void> borrar(String id) => _guard(() => _client.rpc('borrar_mensaje', params: {'p_mensaje_id': id}));

  @override
  Future<DateTime?> leidoHasta(String groupId) => _guard(() async {
        final row = await _client.from('chat_leido').select('leido_hasta').eq('group_id', groupId).maybeSingle();
        return row == null ? null : DateTime.parse(row['leido_hasta'] as String);
      });

  @override
  Future<void> marcarLeido(String groupId) =>
      _guard(() => _client.rpc('marcar_chat_leido', params: {'p_group_id': groupId}));

  @override
  Future<Map<String, int>> sinLeer() => _guard(() async {
        final rows = await _client.rpc('chat_sin_leer') as List;
        return {
          for (final r in rows.cast<Map<String, dynamic>>()) r['group_id'] as String: (r['cantidad'] as num).toInt(),
        };
      });

  @override
  Future<List<({String id, String nombre})>> archivos(String groupId) => _guard(() async {
        final rows = await _client
            .from('files')
            .select('id, nombre')
            .eq('group_id', groupId)
            .isFilter('deleted_at', null)
            .order('nombre')
            .limit(300);
        return [for (final r in rows) (id: r['id'] as String, nombre: r['nombre'] as String)];
      });

  @override
  Stream<String> cambios(String groupId) => escucharCanal(_client, Canales.chat(groupId))
      .map((m) => m['mensaje'] as String? ?? '')
      .where((id) => id.isNotEmpty);

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw ChatFailure(switch (e.code) {
        'P0001' => e.message,
        '42501' => 'No tenés permiso para hacer esto',
        '23514' => 'El mensaje no puede quedar vacío',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on Exception {
      throw const ChatFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
