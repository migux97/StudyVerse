import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/avisos/domain/aviso.dart';

void main() {
  test('aviso a todo el curso o a un grupo', () {
    final a = AvisoDocente.fromMap({
      'id': 'a',
      'curso_id': 'c',
      'group_id': null,
      'texto': 'El parcial pasa al jueves',
      'created_at': '2026-11-05T12:00:00Z',
      'autor_perfil': {'nombre': 'Laura Gómez'},
    });
    expect(a.paraTodoElCurso, isTrue);
    expect(AvisoNuevo(a).mensaje, 'Laura Gómez: El parcial pasa al jueves');
    expect(a.conGrupo('Grupo 4').grupoNombre, 'Grupo 4');
  });

  test('devolución de una tarea', () {
    final d = Devolucion.fromMap({
      'id': 'd',
      'task_id': 't',
      'group_id': 'g',
      'autor': 'p',
      'texto': 'Falta citar',
      'created_at': '2026-11-05T12:00:00Z',
      'autor_perfil': {'nombre': 'Laura Gómez'},
      'tarea': {'titulo': 'Introducción'},
    });
    expect(DevolucionNueva(d).mensaje, 'Laura Gómez dejó una devolución en «Introducción»');
  });
}
