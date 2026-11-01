import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/telegram.dart';

class SupabaseTelegramRepository implements TelegramRepository {
  SupabaseTelegramRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<TelegramLink>> links(String groupId) => _guard(() async {
        final rows = await _client
            .from('telegram_links')
            .select('chat_id, chat_title, linked_at')
            .eq('group_id', groupId)
            .order('linked_at');
        return rows.map(TelegramLink.fromMap).toList();
      });

  @override
  Future<CodigoTelegram> crearCodigo(String groupId) => _guard(() async {
        final row = await _client
            .rpc('create_telegram_link_code', params: {'p_group_id': groupId})
            .single();
        return CodigoTelegram(
          codigo: row['code'] as String,
          vence: DateTime.parse(row['expires_at'] as String),
        );
      });

  @override
  Future<void> desvincular(String groupId, int chatId) => _guard(() async {
        final borrados = await _client
            .from('telegram_links')
            .delete()
            .eq('group_id', groupId)
            .eq('chat_id', chatId)
            .select('chat_id');
        if (borrados.isEmpty) throw const TelegramFailure('Solo el admin puede desconectar Telegram');
      });

  @override
  Stream<void> changes(String groupId) {
    late final RealtimeChannel canal;
    final controller = StreamController<void>.broadcast(
      onCancel: () => _client.removeChannel(canal),
    );
    canal = _client
        .channel('telegram-$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'telegram_links',
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

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw TelegramFailure(
        e.code == '42501' ? 'Solo el admin puede conectar Telegram' : 'No se pudo completar. Intentá de nuevo',
      );
    }
  }
}
