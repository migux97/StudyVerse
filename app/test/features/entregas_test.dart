import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/calendario/domain/calendario.dart';
import 'package:studyverse/features/cursos/domain/curso.dart';
import 'package:studyverse/features/cursos/domain/exportar.dart';
import 'package:studyverse/features/entregas/domain/trabajo.dart';

Trabajo _trabajo(String id, String titulo, {num max = 10}) => Trabajo(
      id: id,
      cursoId: 'c1',
      titulo: titulo,
      venceAt: DateTime.utc(2026, 11, 14, 23, 59),
      notaMaxima: max,
      createdAt: DateTime.utc(2026, 11, 1),
    );

Entrega _entrega(String trabajo, String grupo, EstadoEntrega estado, {num? nota, DateTime? cuando}) => Entrega(
      id: '$trabajo-$grupo',
      trabajoId: trabajo,
      groupId: grupo,
      fileId: 'f',
      versionNumber: 2,
      entregadaAt: cuando ?? DateTime.utc(2026, 11, 13),
      estado: estado,
      nota: nota,
    );

AporteAlumno _alumno(String nombre, String grupo, {int tareas = 0, int versiones = 0}) => AporteAlumno(
      userId: nombre,
      nombre: nombre,
      username: nombre.toLowerCase(),
      groupId: grupo,
      grupo: 'Grupo $grupo',
      tareasHechas: tareas,
      tareasPendientes: 0,
      versiones: versiones,
      comentarios: 0,
    );

void main() {
  group('notas', () {
    test('se escriben con coma y sin ceros de más', () {
      expect(formatearNota(8), '8');
      expect(formatearNota(7.5), '7,5');
      expect(formatearNota(9.25), '9,25');
      expect(formatearNota(10.0), '10');
    });

    test('se leen con coma o con punto', () {
      expect(leerNota('7,5'), 7.5);
      expect(leerNota(' 8 '), 8);
      expect(leerNota('6.25'), 6.25);
      expect(leerNota('ocho'), isNull);
    });

    test('el estado viene de la base', () {
      expect(EstadoEntrega.desde('a_rehacer'), EstadoEntrega.aRehacer);
      expect(EstadoEntrega.desde('aprobada').corregida, isTrue);
      expect(EstadoEntrega.desde('entregada').corregida, isFalse);
    });

    test('resultado y entrega tarde', () {
      final t = _trabajo('t1', 'TP 1');
      expect(resultado(_entrega('t1', 'g', EstadoEntrega.aprobada, nota: 8)), 'Aprobado · 8');
      expect(_entrega('t1', 'g', EstadoEntrega.entregada).tarde(t), isFalse);
      expect(_entrega('t1', 'g', EstadoEntrega.entregada, cuando: DateTime.utc(2026, 11, 15)).tarde(t), isTrue);
      expect(_entrega('t1', 'g', EstadoEntrega.aRehacer).sePuedeCambiar, isTrue);
      expect(_entrega('t1', 'g', EstadoEntrega.desaprobada).sePuedeCambiar, isFalse);
    });
  });

  group('planilla de notas', () {
    test('una fila por alumno con la nota de su grupo en cada trabajo', () {
      final csv = planillaDeNotas(
        alumnos: [_alumno('Ana', 'a', tareas: 3, versiones: 5), _alumno('Juan', 'b')],
        trabajos: [_trabajo('t1', 'TP 1'), _trabajo('t2', 'TP 2; final')],
        entregas: [
          _entrega('t1', 'a', EstadoEntrega.aprobada, nota: 8.5),
          _entrega('t1', 'b', EstadoEntrega.entregada),
          _entrega('t2', 'a', EstadoEntrega.aRehacer),
        ],
      );
      expect(csv.startsWith('﻿'), isTrue);
      final filas = csv.substring(1).trim().split('\r\n');
      expect(filas[0], startsWith('Grupo;Alumno;Usuario;TP 1;"TP 2; final";Tareas hechas'));
      expect(filas[1], startsWith('Grupo a;Ana;@ana;8,5;A rehacer;3;0;5;0;'));
      expect(filas[2], startsWith('Grupo b;Juan;@juan;Sin corregir;Sin entregar;0;0;0;0;'));
    });

    test('el nombre del archivo no lleva caracteres prohibidos', () {
      expect(nombrePlanilla('Física II / Comisión 3'), 'Notas - Física II - Comisión 3.csv');
    });
  });

  group('tablero', () {
    test('un grupo sin actividad hace más de 7 días está inactivo', () {
      final ahora = DateTime(2026, 11, 20);
      GrupoDelCurso g(DateTime? ultima) => GrupoDelCurso.fromMap({
            'id': 'g',
            'nombre': 'G',
            'tareas': ['hecha', 'pendiente'],
            'ultima_actividad': ultima?.toIso8601String(),
          });
      expect(g(null).inactivo(ahora), isTrue);
      expect(g(DateTime(2026, 11, 10)).inactivo(ahora), isTrue);
      expect(g(DateTime(2026, 11, 18)).inactivo(ahora), isFalse);
      expect(g(null).tareasHechas, 1);
    });
  });

  group('calendario', () {
    test('el vencimiento de un trabajo va como entrega y abre las entregas del grupo', () {
      final f = FechaCalendario.deTrabajo({
        'id': 't1',
        'curso_id': 'c1',
        'titulo': 'TP 2',
        'vence_at': DateTime(2026, 11, 14, 23, 59).toUtc().toIso8601String(),
        'curso': {'nombre': 'Física II'},
      }, grupoDelCurso: 'g1');
      expect(f.tipo, TipoFecha.entrega);
      expect(f.dia, DateTime(2026, 11, 14));
      expect(f.hora, '23:59');
      expect(f.grupo, 'Física II');
      expect(f.ruta, '/grupos/g1/entregas');
      expect(f.delCurso, isTrue);
    });

    test('para el docente abre el trabajo en el curso', () {
      final f = FechaCalendario.deTrabajo({
        'id': 't1',
        'curso_id': 'c1',
        'titulo': 'TP 2',
        'vence_at': DateTime.utc(2026, 11, 14, 12).toIso8601String(),
      });
      expect(f.ruta, '/cursos/c1/trabajos/t1');
    });
  });
}
