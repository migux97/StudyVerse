import 'package:flutter_test/flutter_test.dart';
import 'package:tpdrive/features/groups/domain/telegram.dart';

void main() {
  test('link para agregar el bot a un grupo', () {
    expect(linkAgregarBot('@TPDriveBot'), 'https://t.me/TPDriveBot?startgroup=true');
    expect(linkAgregarBot('TPDriveBot'), 'https://t.me/TPDriveBot?startgroup=true');
  });

  test('chat vinculado desde la base (los ids de grupos son negativos y grandes)', () {
    final l = TelegramLink.fromMap({
      'chat_id': -1001234567890,
      'chat_title': 'TP Bio',
      'linked_at': '2026-11-01T12:00:00Z',
    });
    expect(l.chatId, -1001234567890);
    expect(l.chatTitle, 'TP Bio');
  });
}
