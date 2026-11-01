import 'activity_item.dart';

abstract interface class ActivityRepository {
  /// Últimos eventos del grupo, del más nuevo al más viejo.
  Future<List<ActivityItem>> feed(String groupId, {int limite = 100});

  /// Emite cada vez que hay un evento nuevo en el grupo.
  Stream<void> changes(String groupId);
}
