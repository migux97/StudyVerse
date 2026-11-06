import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendario.dart';

String _fecha(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// La carpeta de la tarea y la de arriba (para saber de qué materia es).
const _carpeta = 'carpeta:folders(nombre, color, es_materia, '
    'padre:folders!folders_parent_id_fkey(nombre, color, es_materia))';

class SupabaseCalendarioRepository implements CalendarioRepository {
  SupabaseCalendarioRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<FechaCalendario>> fechas(DateTime desde, DateTime hasta) => _guard(() async {
        final (tareas, eventos, delCurso, trabajos, misGrupos) = await (
          _client
              .from('tasks')
              .select('id, titulo, due_date, estado, group_id, grupo:groups(nombre), $_carpeta')
              .gte('due_date', _fecha(desde))
              .lte('due_date', _fecha(hasta)),
          _client
              .from('eventos')
              .select('*, grupo:groups(nombre), materia:folders(nombre, color, es_materia)')
              .gte('fecha', _fecha(desde))
              .lte('fecha', _fecha(hasta)),
          // Lo que pone el docente para todo el curso.
          _client
              .from('fechas_curso')
              .select('*, curso:cursos(nombre)')
              .gte('fecha', _fecha(desde))
              .lte('fecha', _fecha(hasta)),
          _client
              .from('trabajos')
              .select('id, curso_id, titulo, vence_at, curso:cursos(nombre)')
              .gte('vence_at', soloDia(desde).toUtc().toIso8601String())
              .lt('vence_at', soloDia(hasta).add(const Duration(days: 1)).toUtc().toIso8601String()),
          // Mi grupo en cada curso (el docente no lee groups: queda vacío).
          _client.from('groups').select('id, curso_id').not('curso_id', 'is', null),
        ).wait;
        final grupoEnCurso = {for (final g in misGrupos) g['curso_id'] as String: g['id'] as String};
        return [
          ...tareas.map(FechaCalendario.deTarea),
          ...eventos.map(FechaCalendario.deEvento),
          for (final f in delCurso) FechaCalendario.deCurso(f, grupoDelCurso: grupoEnCurso[f['curso_id']]),
          for (final t in trabajos) FechaCalendario.deTrabajo(t, grupoDelCurso: grupoEnCurso[t['curso_id']]),
        ];
      });

  @override
  Future<void> crearEvento(EventoNuevo e) => _guard(() => _client.from('eventos').insert({
        'group_id': e.groupId,
        'titulo': e.titulo.trim(),
        'tipo': e.tipo.name,
        'fecha': _fecha(e.dia),
        'hora': e.hora,
        'nota': (e.nota?.trim().isEmpty ?? true) ? null : e.nota!.trim(),
        'folder_id': e.folderId,
        'created_by': _client.auth.currentUser!.id,
      }));

  @override
  Future<void> borrarEvento(String id) => _guard(() async {
        final borrados = await _client.from('eventos').delete().eq('id', id).select('id');
        if (borrados.isEmpty) throw const CalendarioFailure('Solo quien lo creó o un admin pueden borrarlo');
      });

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on CalendarioFailure {
      rethrow;
    } on PostgrestException {
      throw const CalendarioFailure('Algo salió mal. Probá de nuevo');
    } on Exception {
      throw const CalendarioFailure('Se cortó la conexión. Probá de nuevo');
    }
  }
}
