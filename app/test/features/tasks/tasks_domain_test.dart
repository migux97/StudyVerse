import 'package:flutter_test/flutter_test.dart';
import 'package:studyverse/features/tasks/domain/task.dart';

Task _tarea({
  String titulo = 't',
  DateTime? due,
  EstadoTarea estado = EstadoTarea.pendiente,
  DateTime? creada,
  DateTime? completada,
}) =>
    Task(
      id: titulo,
      groupId: 'g',
      titulo: titulo,
      dueDate: due,
      estado: estado,
      completedAt: completada,
      createdAt: creada ?? DateTime(2026, 10, 1),
    );

void main() {
  test('estado: valores de la base', () {
    expect(EstadoTarea.enProgreso.valor, 'en_progreso');
    expect(EstadoTarea.desde('en_progreso'), EstadoTarea.enProgreso);
    expect(EstadoTarea.desde('hecha'), EstadoTarea.hecha);
  });

  test('borrador: la fecha va sin hora', () {
    final m = TaskDraft(titulo: ' Conclusión ', dueDate: DateTime(2026, 3, 5, 18, 30)).toMap();
    expect(m['titulo'], 'Conclusión');
    expect(m['due_date'], '2026-03-05');
    expect(m['estado'], 'pendiente');
  });

  group('vencimiento', () {
    final ahora = DateTime(2026, 11, 1, 15);
    String texto(DateTime due, [EstadoTarea e = EstadoTarea.pendiente]) =>
        describirVencimiento(_tarea(due: due, estado: e), ahora).texto;

    test('textos', () {
      expect(texto(DateTime(2026, 11, 1)), 'Vence hoy');
      expect(texto(DateTime(2026, 11, 2)), 'Vence mañana');
      expect(texto(DateTime(2026, 11, 5)), 'Vence en 4 días');
      expect(texto(DateTime(2026, 11, 20)), 'Vence el 20 nov');
      expect(texto(DateTime(2026, 10, 31)), 'Venció ayer');
      expect(texto(DateTime(2026, 10, 28)), 'Venció hace 4 días');
    });

    test('atrasada solo si no está hecha', () {
      expect(describirVencimiento(_tarea(due: DateTime(2026, 10, 28)), ahora).atrasada, isTrue);
      final hecha = describirVencimiento(_tarea(due: DateTime(2026, 10, 28), estado: EstadoTarea.hecha), ahora);
      expect(hecha.atrasada, isFalse);
      expect(hecha.texto, '28 oct');
    });

    test('pronto = hoy o mañana', () {
      expect(describirVencimiento(_tarea(due: DateTime(2026, 11, 2)), ahora).pronto, isTrue);
      expect(describirVencimiento(_tarea(due: DateTime(2026, 11, 9)), ahora).pronto, isFalse);
    });
  });

  test('orden: primero las que vencen antes, sin fecha al final', () {
    final orden = ordenarTareas([
      _tarea(titulo: 'sin fecha'),
      _tarea(titulo: 'viernes', due: DateTime(2026, 11, 6)),
      _tarea(titulo: 'lunes', due: DateTime(2026, 11, 2)),
    ]);
    expect(orden.map((t) => t.titulo), ['lunes', 'viernes', 'sin fecha']);
  });

  test('las hechas: la última completada primero', () {
    final orden = ordenarTareas([
      _tarea(titulo: 'vieja', estado: EstadoTarea.hecha, completada: DateTime(2026, 10, 1)),
      _tarea(titulo: 'nueva', estado: EstadoTarea.hecha, completada: DateTime(2026, 10, 30)),
    ]);
    expect(orden.first.titulo, 'nueva');
  });

  test('tarea desde la base', () {
    final t = Task.fromMap({
      'id': 't1',
      'group_id': 'g',
      'folder_id': 'f',
      'folder': {'nombre': 'TP 2'},
      'titulo': 'Introducción',
      'assigned_to': 'u',
      'assignee': {'nombre': 'Juan'},
      'due_date': '2026-11-05',
      'estado': 'en_progreso',
      'completed_at': null,
      'created_by': 'a',
      'created_at': '2026-11-01T12:00:00Z',
    });
    expect(t.estado, EstadoTarea.enProgreso);
    expect(t.assignedNombre, 'Juan');
    expect(t.folderNombre, 'TP 2');
    expect(t.dueDate, DateTime(2026, 11, 5));
  });
}
