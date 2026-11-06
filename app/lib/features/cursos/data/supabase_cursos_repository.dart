import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/curso.dart';

const _selectCurso = '*, docente:profiles!cursos_docente_id_fkey(nombre)';

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

  @override
  Future<bool> soyTitular(String cursoId) =>
      _guard(() async => await _client.rpc('soy_titular_del_curso', params: {'p_curso_id': cursoId}) as bool);

  @override
  Future<List<DocenteDelCurso>> docentes(String cursoId) => _guard(() async {
        final rows = await _client.rpc('docentes_del_curso', params: {'p_curso_id': cursoId}) as List;
        return rows.cast<Map<String, dynamic>>().map(DocenteDelCurso.fromMap).toList();
      });

  @override
  Future<DocenteDelCurso> sumarAyudante(String cursoId, String usuario) => _guard(() async =>
      DocenteDelCurso.fromMap(
          await _client.rpc('sumar_ayudante', params: {'p_curso_id': cursoId, 'p_usuario': usuario}) as Map<String, dynamic>));

  @override
  Future<void> quitarAyudante(String cursoId, String userId) =>
      _guard(() => _client.rpc('quitar_ayudante', params: {'p_curso_id': cursoId, 'p_user_id': userId}));

  @override
  Future<List<AporteAlumno>> aportes(String cursoId) => _guard(() async {
        final rows = await _client.rpc('aportes_del_curso', params: {'p_curso_id': cursoId}) as List;
        return rows.cast<Map<String, dynamic>>().map(AporteAlumno.fromMap).toList();
      });

  @override
  Future<List<MaterialCurso>> material(String cursoId) => _guard(() async {
        final rows = await _client
            .from('material_curso')
            .select()
            .eq('curso_id', cursoId)
            .order('created_at', ascending: false);
        return rows.map(MaterialCurso.fromMap).toList();
      });

  @override
  Future<MaterialCurso> subirMaterial(String cursoId, {required String nombre, required List<int> bytes}) =>
      _guard(() async {
        final r = await _client.rpc('reservar_material', params: {
          'p_curso_id': cursoId,
          'p_nombre': nombre,
          'p_size_bytes': bytes.length,
        }).single();
        await _client.storage.from('archivos').uploadBinary(r['storage_path'] as String, Uint8List.fromList(bytes));
        return MaterialCurso.fromMap(await _client.rpc('terminar_material', params: {'p_id': r['id']}).single());
      });

  @override
  Future<void> borrarMaterial(String id) => _guard(() => _client.rpc('borrar_material', params: {'p_id': id}));

  @override
  Future<List<int>> bytesDelMaterial(MaterialCurso m) =>
      _guard(() => _client.storage.from('archivos').download(m.storagePath));

  @override
  Future<List<FechaCurso>> fechas(String cursoId) => _guard(() async {
        final rows = await _client.from('fechas_curso').select().eq('curso_id', cursoId).order('fecha', ascending: true);
        return rows.map(FechaCurso.fromMap).toList();
      });

  @override
  Future<void> crearFecha(String cursoId,
          {required String titulo, required String tipo, required DateTime fecha, String? hora, String? nota}) =>
      _guard(() => _client.from('fechas_curso').insert({
            'curso_id': cursoId,
            'titulo': titulo.trim(),
            'tipo': tipo,
            'fecha': '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-'
                '${fecha.day.toString().padLeft(2, '0')}',
            'hora': hora,
            'nota': (nota?.trim().isEmpty ?? true) ? null : nota!.trim(),
            'creado_por': _client.auth.currentUser!.id,
          }));

  @override
  Future<void> borrarFecha(String id) => _guard(() async {
        final borradas = await _client.from('fechas_curso').delete().eq('id', id).select('id');
        if (borradas.isEmpty) throw const CursosFailure('Esa fecha ya no existe');
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on CursosFailure {
      rethrow;
    } on PostgrestException catch (e) {
      throw CursosFailure(switch (e.code) {
        'P0001' => e.message,
        'P0002' => 'Ese curso ya no existe',
        '42501' => 'No tenés permiso para hacer esto',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on StorageException {
      throw const CursosFailure('No pudimos subir o bajar el archivo. Probá de nuevo');
    } on Exception {
      throw const CursosFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
