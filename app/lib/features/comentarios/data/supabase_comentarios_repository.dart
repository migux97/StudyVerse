import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/realtime/canales.dart';
import '../domain/comentario.dart';

const _select = '*, autor_perfil:profiles!comentarios_autor_fkey(*)';

class SupabaseComentariosRepository implements ComentariosRepository {
  SupabaseComentariosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Comentario>> comentarios(String fileId) => _guard(() async {
        final rows = await _client.from('comentarios').select(_select).eq('file_id', fileId).order('created_at', ascending: true);
        return rows.map(Comentario.fromMap).toList();
      });

  @override
  Future<void> comentar({required String fileId, required String groupId, required String texto}) =>
      _guard(() => _client.from('comentarios').insert({
            'file_id': fileId,
            'group_id': groupId,
            'texto': texto.trim(),
            'autor': _client.auth.currentUser!.id,
          }));

  @override
  Future<void> borrar(String id) => _guard(() async {
        final borrados = await _client.from('comentarios').delete().eq('id', id).select('id');
        if (borrados.isEmpty) throw const ComentarioFailure('Solo podés borrar tus comentarios');
      });

  @override
  Stream<String> cambios(String groupId) => escucharCanal(_client, Canales.comentarios(groupId))
      .map((m) => m['archivo'] as String? ?? '')
      .where((id) => id.isNotEmpty);

  @override
  Stream<Comentario> menciones(String miId) =>
      escucharCanal(_client, Canales.menciones(miId), evento: 'mencion').asyncExpand((aviso) async* {
        try {
          final row = await _client
              .from('comentarios')
              .select('$_select, archivo:files(nombre)')
              .eq('id', aviso['comentario'] as String)
              .maybeSingle();
          if (row != null) yield Comentario.fromMap(row);
        } on PostgrestException {
          // Si ya lo borraron, no hay nada que avisar.
        }
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ComentarioFailure {
      rethrow;
    } on PostgrestException {
      throw const ComentarioFailure('Algo salió mal. Probá de nuevo');
    } on Exception {
      throw const ComentarioFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
