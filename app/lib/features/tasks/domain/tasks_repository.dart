import '../../../core/errors.dart';
import 'task.dart';

class TasksFailure extends AppFailure {
  const TasksFailure(super.mensaje);
}

abstract interface class TasksRepository {
  Future<List<Task>> tasks(String groupId);
  Future<void> create(String groupId, TaskDraft draft);
  Future<void> update(String taskId, TaskDraft draft);
  Future<void> setEstado(String taskId, EstadoTarea estado);
  Future<void> delete(String taskId);

  /// Tareas completadas y versiones subidas por integrante.
  Future<List<Aporte>> contributions(String groupId);

  /// Emite cada vez que cambian las tareas del grupo.
  Stream<void> changes(String groupId);
}
