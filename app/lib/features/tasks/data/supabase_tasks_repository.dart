import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/task.dart';
import '../domain/tasks_repository.dart';
import '../../../core/realtime/canales.dart';

class SupabaseTasksRepository implements TasksRepository {
  SupabaseTasksRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Task>> tasks(String groupId) => _guard(() async {
        final rows = await _client
            .from('tasks')
            .select('*, assignee:profiles!tasks_assigned_to_fkey(nombre), folder:folders(nombre)')
            .eq('group_id', groupId);
        return rows.map(Task.fromMap).toList();
      });

  @override
  Future<void> create(String groupId, TaskDraft draft) => _guard(() => _client.from('tasks').insert({
        ...draft.toMap(),
        'group_id': groupId,
        'created_by': _client.auth.currentUser!.id,
      }));

  @override
  Future<void> update(String taskId, TaskDraft draft) =>
      _guard(() => _client.from('tasks').update(draft.toMap()).eq('id', taskId));

  @override
  Future<void> setEstado(String taskId, EstadoTarea estado) =>
      _guard(() => _client.from('tasks').update({'estado': estado.valor}).eq('id', taskId));

  @override
  Future<void> delete(String taskId) => _guard(() async {
        final borradas = await _client.from('tasks').delete().eq('id', taskId).select('id');
        // RLS no da error: simplemente no borra si no te corresponde.
        if (borradas.isEmpty) {
          throw const TasksFailure('Solo quien creó la tarea o un admin pueden eliminarla');
        }
      });

  @override
  Future<List<Aporte>> contributions(String groupId) => _guard(() async {
        final rows = await _client.rpc('group_contributions', params: {'p_group_id': groupId}) as List;
        return rows.cast<Map<String, dynamic>>().map(Aporte.fromMap).toList();
      });

  @override
  Stream<void> changes(String groupId) => escucharCanal(_client, Canales.tareas(groupId));

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw TasksFailure(traducirErrorTareas(e.code, e.message));
    }
  }
}

String traducirErrorTareas(String? code, String message) => switch (code) {
      'P0001' => message,
      '42501' => 'No tenés permiso para hacer esto',
      '23514' => 'El título no puede quedar vacío',
      _ => 'No se pudo guardar la tarea',
    };
