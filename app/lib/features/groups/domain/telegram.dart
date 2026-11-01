import '../../../core/errors.dart';

class TelegramFailure extends AppFailure {
  const TelegramFailure(super.mensaje);
}

/// Un chat de Telegram que recibe los avisos del grupo.
class TelegramLink {
  const TelegramLink({required this.chatId, this.chatTitle, required this.linkedAt});

  final int chatId;
  final String? chatTitle;
  final DateTime linkedAt;

  factory TelegramLink.fromMap(Map<String, dynamic> map) => TelegramLink(
        chatId: (map['chat_id'] as num).toInt(),
        chatTitle: map['chat_title'] as String?,
        linkedAt: DateTime.parse(map['linked_at'] as String),
      );
}

/// Código de un solo uso para "/vincular CODIGO" (vence a los 30 minutos).
class CodigoTelegram {
  const CodigoTelegram({required this.codigo, required this.vence});
  final String codigo;
  final DateTime vence;
}

abstract interface class TelegramRepository {
  Future<List<TelegramLink>> links(String groupId);
  Future<CodigoTelegram> crearCodigo(String groupId);
  Future<void> desvincular(String groupId, int chatId);
  Stream<void> changes(String groupId);
}

/// Link para agregar el bot a un grupo de Telegram ("startgroup").
String linkAgregarBot(String usuarioBot) =>
    'https://t.me/${usuarioBot.replaceFirst('@', '')}?startgroup=true';
