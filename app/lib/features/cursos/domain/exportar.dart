import '../../entregas/domain/trabajo.dart';
import 'curso.dart';

/// Planilla de notas del curso: una fila por alumno, con la nota (o el estado)
/// de su grupo en cada trabajo y sus aportes. Separada con ";" y con BOM, como
/// la abre Excel en español; los decimales van con coma.
String planillaDeNotas({
  required List<AporteAlumno> alumnos,
  required List<Trabajo> trabajos,
  required List<Entrega> entregas,
}) {
  String celda(Object? v) {
    final s = v?.toString() ?? '';
    return RegExp(r'[;"\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String fecha(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  final porGrupo = {for (final e in entregas) (e.trabajoId, e.groupId): e};
  String resultadoDe(Trabajo t, String groupId) {
    final e = porGrupo[(t.id, groupId)];
    if (e == null) return 'Sin entregar';
    if (e.nota != null) return formatearNota(e.nota!);
    return e.estado == EstadoEntrega.entregada ? 'Sin corregir' : e.estado.texto;
  }

  final filas = <List<Object?>>[
    [
      'Grupo',
      'Alumno',
      'Usuario',
      for (final t in trabajos) t.titulo,
      'Tareas hechas',
      'Tareas pendientes',
      'Versiones subidas',
      'Comentarios',
      'Última actividad',
    ],
    for (final a in alumnos)
      [
        a.grupo,
        a.nombre,
        a.username == null ? '' : '@${a.username}',
        for (final t in trabajos) resultadoDe(t, a.groupId),
        a.tareasHechas,
        a.tareasPendientes,
        a.versiones,
        a.comentarios,
        fecha(a.ultimaActividad),
      ],
  ];
  return '﻿${filas.map((f) => f.map(celda).join(';')).join('\r\n')}\r\n';
}

/// "Notas - Física II · Comisión 3.csv" sin caracteres que no van en un nombre de archivo.
String nombrePlanilla(String curso) => 'Notas - ${curso.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')}.csv';
