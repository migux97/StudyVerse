import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/realtime/canales.dart';
import '../domain/aviso.dart';

const _selectAviso = '*, autor_perfil:profiles!avisos_autor_fkey(nombre)';
const _selectDevolucion = '*, autor_perfil:profiles!devoluciones_autor_fkey(nombre), tarea:tasks(titulo)';

class SupabaseAvisosRepository implements AvisosRepository {
  SupabaseAvisosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<AvisoDocente>> delGrupo(String groupId, String cursoId) => _guard(() async {
        final rows = await _client
            .from('avisos')
            .select(_selectAviso)
            .eq('curso_id', cursoId)
            .or('group_id.is.null,group_id.eq.$groupId')
            .order('created_at', ascending: false)
            .limit(50);
        return rows.map(AvisoDocente.fromMap).toList();
      });

  @override
  Future<List<AvisoDocente>> delCurso(String cursoId) => _guard(() async {
        final rows = await _client
            .from('avisos')
            .select(_selectAviso)
            .eq('curso_id', cursoId)
            .order('created_at', ascending: false)
            .limit(100);
        return rows.map(AvisoDocente.fromMap).toList();
      });

  @override
  Future<void> mandar({required String cursoId, String? groupId, required String texto}) => _guard(() =>
      _client.rpc('mandar_aviso', params: {'p_curso_id': cursoId, 'p_group_id': groupId, 'p_texto': texto}));

  @override
  Future<void> borrar(String avisoId) => _guard(() async {
        final borrados = await _client.from('avisos').delete().eq('id', avisoId).select('id');
        if (borrados.isEmpty) throw const AvisosFailure('Solo quien lo mandó puede borrarlo');
      });

  @override
  Future<List<Devolucion>> devoluciones(String groupId) => _guard(() async {
        final rows = await _client
            .from('devoluciones')
            .select(_selectDevolucion)
            .eq('group_id', groupId)
            .order('created_at', ascending: true);
        return rows.map(Devolucion.fromMap).toList();
      });

  @override
  Future<void> devolver({required String taskId, required String groupId, required String texto}) =>
      _guard(() => _client.from('devoluciones').insert({
            'task_id': taskId,
            'group_id': groupId,
            'texto': texto.trim(),
            'autor': _client.auth.currentUser!.id,
          }));

  @override
  Future<void> borrarDevolucion(String id) => _guard(() async {
        final borradas = await _client.from('devoluciones').delete().eq('id', id).select('id');
        if (borradas.isEmpty) throw const AvisosFailure('Solo quien la escribió puede borrarla');
      });

  @override
  Stream<void> cambios(String groupId) => escucharCanal(_client, Canales.avisos(groupId));

  @override
  Stream<AvisoEntrante> entrantes(String miId) =>
      escucharCanal(_client, Canales.avisosDe(miId), evento: 'aviso').asyncExpand((m) async* {
        // El aviso trae solo el id: se lee con la RLS de siempre.
        try {
          if (m['aviso'] case final String id) {
            final row = await _client.from('avisos').select(_selectAviso).eq('id', id).maybeSingle();
            if (row != null) yield AvisoNuevo(AvisoDocente.fromMap(row), groupId: row['group_id'] as String?);
          } else if (m['devolucion'] case final String id) {
            final row = await _client.from('devoluciones').select(_selectDevolucion).eq('id', id).maybeSingle();
            if (row != null) yield DevolucionNueva(Devolucion.fromMap(row));
          }
        } on PostgrestException {
          // Si ya no se puede ver, no hay nada que avisar.
        }
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on AvisosFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw AvisosFailure(switch (e.code) {
        'P0001' => e.message,
        '42501' => 'No tenés permiso para hacer esto',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on Exception {
      throw const AvisosFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
