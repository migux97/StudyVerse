import '../../entregas/domain/trabajo.dart' show formatearNota;
import 'cuestionario.dart';

/// Resultados de un cuestionario para Excel: una fila por intento (o por alumno
/// que no lo hizo). Separado con ";" y con BOM; los decimales van con coma.
String planillaDeResultados(Cuestionario c, List<ResultadoAlumno> alumnos) {
  String celda(Object? v) {
    var s = v?.toString() ?? '';
    // Un texto que empieza con = + - lo toma Excel como fórmula.
    if (v is String && RegExp(r'^[=+\-\t\r]').hasMatch(s)) s = "'$s";
    return RegExp(r'[;"\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String fecha(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(l.day)}/${dos(l.month)}/${l.year} ${dos(l.hour)}:${dos(l.minute)}';
  }

  final filas = <List<Object?>>[
    ['Alumno', 'Grupo', 'Intento', 'Estado', 'Nota', 'Puntaje', 'Puntaje máximo', 'Salidas', 'Tiempo afuera',
      'Empezó', 'Entregó'],
    for (final a in alumnos)
      if (a.intentos.isEmpty)
        [a.nombre, a.grupo, '', 'No lo hizo', '', '', '', '', '', '', '']
      else
        for (final i in a.intentos)
          [
            a.nombre,
            a.grupo,
            i.numero,
            i.pendiente ? 'Por corregir' : estadoIntento(i),
            i.nota == null || i.pendiente ? '' : formatearNota(i.nota!),
            i.puntaje == null ? '' : formatearNota(i.puntaje!),
            i.puntajeMax == null ? '' : formatearNota(i.puntajeMax!),
            i.salidas,
            formatearSegundos(i.segundosAfuera),
            fecha(i.empezadoAt),
            fecha(i.entregadoAt),
          ],
  ];
  return '﻿${filas.map((f) => f.map(celda).join(';')).join('\r\n')}\r\n';
}

/// "Resultados - Parcialito 1.csv" sin caracteres que no van en un nombre de archivo.
String nombreResultados(String titulo) => 'Resultados - ${titulo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')}.csv';
