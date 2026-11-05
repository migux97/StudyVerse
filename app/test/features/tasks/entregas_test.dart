import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/groups/domain/group.dart';
import 'package:studyverse/features/tasks/data/supabase_tasks_repository.dart';
import 'package:studyverse/features/tasks/domain/task.dart';

void main() {
  test('una tarea entregada trae quién, cuándo y la nota', () {
    final t = Task.fromMap({
      'id': 't',
      'group_id': 'g',
      'titulo': 'Introducción',
      'estado': 'entregada',
      'created_at': '2026-11-01T12:00:00Z',
      'entregada_por': 'juan',
      'entregador': {'nombre': 'Juan'},
      'entregada_at': '2026-11-02T10:00:00Z',
      'entrega_nota': 'Está en TP 2',
      'revision_nota': null,
    });
    expect(t.entregada, isTrue);
    expect(t.estado.valor, 'entregada');
    expect(t.entregadaPorNombre, 'Juan');
    expect(t.entregaNota, 'Está en TP 2');
  });

  test('aviso de revisión', () {
    Map<String, dynamic> fila(String estado) => {
          'id': 't',
          'titulo': 'Gráficos',
          'group_id': 'g',
          'estado': estado,
          'revisor': {'nombre': 'Ana'},
        };
    expect(Revision.fromMap(fila('en_progreso')).mensaje, 'Ana te pidió cambios en «Gráficos»');
    expect(Revision.fromMap(fila('hecha')).mensaje, 'Ana aprobó «Gráficos»');
  });

  test('quién puede cerrar tareas', () {
    Group g({required bool admin, required bool aprobar}) => Group(
        id: 'g',
        nombre: 'x',
        inviteCode: 'ABCD2345',
        createdAt: DateTime(2026),
        miRol: admin ? GroupRole.admin : GroupRole.miembro,
        aprobarTareas: aprobar);
    expect(g(admin: false, aprobar: false).puedoCerrarTareas, isTrue);
    expect(g(admin: false, aprobar: true).puedoCerrarTareas, isFalse);
    expect(g(admin: true, aprobar: true).puedoCerrarTareas, isTrue);
  });

  test('los errores de aprobación se muestran tal cual', () {
    expect(traducirErrorTareas('P0001', 'Un admin tiene que aprobarla: marcala como entregada'),
        'Un admin tiene que aprobarla: marcala como entregada');
    expect(traducirErrorTareas('42501', 'permission denied for table tasks'), 'No tenés permiso para hacer esto');
  });
}
