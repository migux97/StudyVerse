import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/activity_item.dart';
import '../domain/activity_repository.dart';
import '../../../core/realtime/canales.dart';

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
  Stream<void> changes(String groupId) => escucharCanal(_client, Canales.actividad(groupId));
}
