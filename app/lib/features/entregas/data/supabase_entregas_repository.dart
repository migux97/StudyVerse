import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/trabajo.dart';

const _selectEntrega = '*, archivo:files(nombre), quien:profiles!entregas_entregada_por_fkey(nombre)';

class SupabaseEntregasRepository implements EntregasRepository {
  SupabaseEntregasRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Trabajo>> trabajos(String cursoId) => _guard(() async {
        final rows = await _client
            .from('trabajos')
            .select('*, curso:cursos(nombre)')
            .eq('curso_id', cursoId)
            .order('vence_at', ascending: true);
        return rows.map(Trabajo.fromMap).toList();
      });

  @override
  Future<Trabajo> trabajo(String trabajoId) => _guard(() async {
        final row = await _client.from('trabajos').select('*, curso:cursos(nombre)').eq('id', trabajoId).maybeSingle();
        if (row == null) throw const EntregasFailure('Ese trabajo ya no existe');
        return Trabajo.fromMap(row);
      });

  @override
  Future<Trabajo> crear({
    required String cursoId,
    required String titulo,
    String? consigna,
    required DateTime venceAt,
    required num notaMaxima,
  }) =>
      _guard(() async => Trabajo.fromMap(await _client.rpc('crear_trabajo', params: {
            'p_curso_id': cursoId,
            'p_titulo': titulo,
            'p_consigna': consigna,
            'p_vence_at': venceAt.toUtc().toIso8601String(),
            'p_nota_maxima': notaMaxima,
          }).single()));

  @override
  Future<Trabajo> editar(Trabajo t,
          {required String titulo, String? consigna, required DateTime venceAt, required num notaMaxima}) =>
      _guard(() async => Trabajo.fromMap(await _client.rpc('editar_trabajo', params: {
            'p_trabajo_id': t.id,
            'p_titulo': titulo,
            'p_consigna': consigna,
            'p_vence_at': venceAt.toUtc().toIso8601String(),
            'p_nota_maxima': notaMaxima,
          }).single()));

  @override
  Future<void> borrar(String trabajoId) =>
      _guard(() => _client.rpc('borrar_trabajo', params: {'p_trabajo_id': trabajoId}));

  @override
  Future<List<Entrega>> delCurso(String cursoId) => _guard(() async {
        final rows = await _client
            .from('entregas')
            .select('$_selectEntrega, trabajo:trabajos!inner(curso_id)')
            .eq('trabajo.curso_id', cursoId);
        return rows.map(Entrega.fromMap).toList();
      });

  @override
  Future<List<Entrega>> delGrupo(String groupId) => _guard(() async {
        final rows = await _client.from('entregas').select(_selectEntrega).eq('group_id', groupId);
        return rows.map(Entrega.fromMap).toList();
      });

  @override
  Future<Entrega> entregar({required String trabajoId, required String groupId, required String fileId}) =>
      _guard(() async {
        final e = await _client.rpc('entregar_trabajo', params: {
          'p_trabajo_id': trabajoId,
          'p_group_id': groupId,
          'p_file_id': fileId,
        }).single();
        return _conDatos(e['id'] as String);
      });

  @override
  Future<Entrega> corregir(String entregaId, {required EstadoEntrega estado, num? nota, String? devolucion}) =>
      _guard(() async {
        await _client.rpc('corregir_entrega', params: {
          'p_entrega_id': entregaId,
          'p_estado': estado.db,
          'p_nota': nota,
          'p_devolucion': devolucion,
        });
        return _conDatos(entregaId);
      });

  Future<Entrega> _conDatos(String id) async =>
      Entrega.fromMap(await _client.from('entregas').select(_selectEntrega).eq('id', id).single());

  @override
  Future<List<int>> bytesDeLaVersion(String fileId, int version) => _guard(() async {
        final v = await _client
            .from('file_versions')
            .select('storage_path')
            .eq('file_id', fileId)
            .eq('version_number', version)
            .single();
        return _client.storage.from('archivos').download(v['storage_path'] as String);
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on EntregasFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw EntregasFailure(switch (e.code) {
        'P0001' => e.message,
        'P0002' => 'Eso ya no existe',
        '42501' => 'No tenés permiso para hacer esto',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on StorageException {
      throw const EntregasFailure('No pudimos bajar el archivo. Probá de nuevo');
    } on Exception {
      throw const EntregasFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
