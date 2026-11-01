import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/activity_item.dart';
import '../domain/activity_repository.dart';

class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ActivityItem>> feed(String groupId, {int limite = 100}) async {
    try {
      final rows = await _client
          .from('activity')
          .select('*, actor:profiles(nombre)')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(limite);
      return rows.map(ActivityItem.fromMap).toList();
    } on PostgrestException {
      throw const ActivityFailure('No se pudo cargar la actividad');
    }
  }

  @override
  Stream<void> changes(String groupId) {
    late final RealtimeChannel canal;
    final controller = StreamController<void>.broadcast(
      onCancel: () => _client.removeChannel(canal),
    );
    canal = _client
        .channel('actividad-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'activity',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (_) => controller.add(null),
        )
        .subscribe();
    return controller.stream;
  }
}
