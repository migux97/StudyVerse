import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/cuestionario.dart';

class SupabaseCuestionariosRepository implements CuestionariosRepository {
  SupabaseCuestionariosRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Cuestionario>> delCurso(String cursoId) => _guard(() async {
        final rows = await _client
            .from('cuestionarios')
            .select()
            .eq('curso_id', cursoId)
            .order('cierra_at', ascending: true);
        return rows.map(Cuestionario.fromMap).toList();
      });

  @override
  Future<Cuestionario> cuestionario(String id) => _guard(() async {
        final row = await _client.from('cuestionarios').select().eq('id', id).maybeSingle();
        if (row == null) throw const CuestionariosFailure('Ese cuestionario ya no existe');
        return Cuestionario.fromMap(row);
      });

  @override
  Future<Cuestionario> guardar({String? id, String? cursoId, required DatosCuestionario datos}) =>
      _guard(() async => Cuestionario.fromMap(await _client.rpc('guardar_cuestionario', params: {
            'p_id': id,
            'p_curso_id': cursoId,
            'p_titulo': datos.titulo,
            'p_descripcion': datos.descripcion,
            'p_abre_at': datos.abreAt.toUtc().toIso8601String(),
            'p_cierra_at': datos.cierraAt.toUtc().toIso8601String(),
            'p_duracion_min': datos.duracionMin,
            'p_intentos': datos.intentos,
            'p_resultados': datos.resultadosAlCerrar ? 'al_cerrar' : 'al_entregar',
            'p_mezclar': datos.mezclar,
            'p_tope_salidas': datos.topeSalidas,
            'p_nota_maxima': datos.notaMaxima,
          }).single()));

  @override
  Future<void> publicar(String id) => _guard(() => _client.rpc('publicar_cuestionario', params: {'p_id': id}));

  @override
  Future<void> borrar(String id) => _guard(() => _client.rpc('borrar_cuestionario', params: {'p_id': id}));

  @override
  Future<List<Pregunta>> preguntasConClave(String cuestionarioId) => _guard(() async {
        final rows = await _client.rpc('preguntas_con_clave', params: {'p_cuestionario_id': cuestionarioId});
        return [for (final r in rows as List<dynamic>) Pregunta.fromMap(r as Map<String, dynamic>)];
      });

  @override
  Future<void> guardarPreguntas(String cuestionarioId, List<Pregunta> preguntas) => _guard(() => _client.rpc(
        'guardar_preguntas',
        params: {'p_cuestionario_id': cuestionarioId, 'p_preguntas': [for (final p in preguntas) p.toMap()]},
      ));

  @override
  Future<List<ResultadoAlumno>> resultados(String cuestionarioId) => _guard(() async {
        final r = await _client.rpc('resultados_del_cuestionario', params: {'p_cuestionario_id': cuestionarioId});
        return [for (final a in r as List<dynamic>) ResultadoAlumno.fromMap(a as Map<String, dynamic>)];
      });

  @override
  Future<void> corregir(String intentoId, String preguntaId, {required num puntaje, String? comentario}) =>
      _guard(() => _client.rpc('corregir_respuesta', params: {
            'p_intento_id': intentoId,
            'p_pregunta_id': preguntaId,
            'p_puntaje': puntaje,
            'p_comentario': comentario,
          }));

  @override
  Future<List<Intento>> misIntentos(String cuestionarioId) => _guard(() async {
        final r = await _client.rpc('mis_intentos', params: {'p_cuestionario_id': cuestionarioId});
        return [for (final i in r as List<dynamic>) Intento.fromMap(i as Map<String, dynamic>)];
      });

  @override
  Future<String> empezar(String cuestionarioId) =>
      _guard(() async => await _client.rpc('empezar_intento', params: {'p_cuestionario_id': cuestionarioId}) as String);

  @override
  Future<IntentoAbierto> abrir(String intentoId, String sesion) => _guard(() async {
        final antes = DateTime.now();
        final r = await _client.rpc('abrir_intento', params: {'p_intento_id': intentoId, 'p_sesion': sesion});
        // La hora del servidor se compara con la mitad del viaje de ida y vuelta.
        final medio = antes.add(DateTime.now().difference(antes) ~/ 2);
        return IntentoAbierto.fromMap(r as Map<String, dynamic>, ahoraLocal: medio);
      });

  @override
  Future<void> responder(String intentoId, String sesion, String preguntaId, Object? valor) =>
      _guard(() => _client.rpc('responder', params: {
            'p_intento_id': intentoId,
            'p_sesion': sesion,
            'p_pregunta_id': preguntaId,
            'p_valor': valor,
          }));

  @override
  Future<({int salidas, bool entregado})> avisarSalida(String intentoId, String sesion,
          {required bool volvio, int segundos = 0}) =>
      _guard(() async {
        final r = await _client.rpc('avisar_salida', params: {
          'p_intento_id': intentoId,
          'p_sesion': sesion,
          'p_volvio': volvio,
          'p_segundos': segundos,
        }) as Map<String, dynamic>;
        return (salidas: (r['salidas'] as num).toInt(), entregado: r['entregado'] as bool);
      });

  @override
  Future<void> entregar(String intentoId) =>
      _guard(() => _client.rpc('entregar_intento', params: {'p_intento_id': intentoId}));

  @override
  Future<DetalleIntento> detalle(String intentoId) => _guard(() async =>
      DetalleIntento.fromMap(await _client.rpc('detalle_intento', params: {'p_intento_id': intentoId}) as Map<String, dynamic>));

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on CuestionariosFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == 'SV001') throw OtraSesionFailure(e.message);
      throw CuestionariosFailure(switch (e.code) {
        'P0001' => e.message,
        'P0002' => 'Eso ya no existe',
        '42501' => 'No tenés permiso para hacer esto',
        _ => 'Algo salió mal. Probá de nuevo',
      });
    } on FormatException {
      throw const CuestionariosFailure('Algo salió mal. Probá de nuevo');
    } on TypeError {
      throw const CuestionariosFailure('Algo salió mal. Probá de nuevo');
    } on Exception {
      throw const CuestionariosFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
