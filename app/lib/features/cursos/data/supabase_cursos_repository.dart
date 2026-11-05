import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/curso.dart';

const _selectCurso = '*, docente:profiles(nombre)';

class SupabaseCursosRepository implements CursosRepository {
  SupabaseCursosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Curso>> misCursos() => _guard(() async {
        // Con la cantidad de grupos (el docente no lee la tabla de grupos).
        final rows = await _client.rpc('mis_cursos') as List;
        return rows.cast<Map<String, dynamic>>().map(Curso.fromMap).toList();
      });

  @override
  Future<Curso> curso(String cursoId) => _guard(() async {
        final row = await _client.from('cursos').select(_selectCurso).eq('id', cursoId).maybeSingle();
        if (row == null) throw const CursosFailure('Ese curso ya no existe');
        return Curso.fromMap(row);
      });

  @override
  Future<Curso> crear(String nombre) =>
      _guard(() async => Curso.fromMap(await _client.rpc('crear_curso', params: {'p_nombre': nombre}).single()));

  @override
  Future<void> renombrar(String cursoId, String nombre) =>
      _guard(() => _client.from('cursos').update({'nombre': nombre.trim()}).eq('id', cursoId));

  @override
  Future<void> borrar(String cursoId) => _guard(() => _client.from('cursos').delete().eq('id', cursoId));

  @override
  Future<String> regenerarCodigo(String cursoId) => _guard(
      () async => await _client.rpc('regenerar_codigo_curso', params: {'p_curso_id': cursoId}) as String);

  @override
  Future<List<GrupoDelCurso>> grupos(String cursoId) => _guard(() async {
        final rows = await _client.rpc('grupos_del_curso', params: {'p_curso_id': cursoId}) as List;
        return rows.cast<Map<String, dynamic>>().map(GrupoDelCurso.fromMap).toList();
      });

  @override
  Future<Curso> sumarGrupo(String groupId, String codigo) => _guard(() async => Curso.fromMap(
      await _client.rpc('sumar_grupo_a_curso', params: {'p_group_id': groupId, 'p_codigo': codigo}).single()));

  @override
  Future<void> quitarGrupo(String groupId) =>
      _guard(() => _client.rpc('quitar_grupo_de_curso', params: {'p_group_id': groupId}));

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on CursosFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw CursosFailure(switch (e.code) {
        'P0001' => e.message,
        'P0002' => 'Ese curso ya no existe',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on Exception {
      throw const CursosFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
