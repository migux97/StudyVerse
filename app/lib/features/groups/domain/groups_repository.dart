import '../../../core/errors.dart';
import 'group.dart';

class GroupFailure extends AppFailure {
  const GroupFailure(super.mensaje);
}

abstract interface class GroupsRepository {
  Future<List<Group>> myGroups();
  Future<Group> getGroup(String groupId);
  Future<List<GroupMember>> members(String groupId);

  Future<Group> create({required String nombre, String? materia});
  Future<Group> join(String codigo);
  Future<void> update(String groupId, {required String nombre, String? materia});
  Future<String> regenerateInviteCode(String groupId);
  Future<void> removeMember(String groupId, String userId);
  Future<void> setRole(String groupId, String userId, GroupRole rol);
  Future<void> leave(String groupId);
  Future<void> delete(String groupId);

  /// Emite cada vez que cambian los grupos o integrantes visibles.
  Stream<void> changes();
}
