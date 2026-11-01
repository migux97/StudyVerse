import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/group.dart';
import '../domain/groups_repository.dart';
import '../domain/invite.dart';

class SupabaseGroupsRepository implements GroupsRepository {
  SupabaseGroupsRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  @override
  Future<List<Group>> myGroups() => _guard(() async {
        final rows = await _client
            .from('group_members')
            .select('rol, groups(*, group_members(count))')
            .eq('user_id', _uid);
        final grupos = rows.map(_grupoConRol).toList()
          ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
        return grupos;
      });

  @override
  Future<Group> getGroup(String groupId) => _guard(() async {
        final row = await _client
            .from('group_members')
            .select('rol, groups(*, group_members(count))')
            .eq('user_id', _uid)
            .eq('group_id', groupId)
            .maybeSingle();
        if (row == null) throw const GroupFailure('No tenés acceso a este grupo');
        return _grupoConRol(row);
      });

  static Group _grupoConRol(Map<String, dynamic> row) {
    final g = row['groups'] as Map<String, dynamic>;
    final conteo = (g['group_members'] as List?)?.firstOrNull as Map<String, dynamic>?;
    return Group.fromMap(
      g,
      miRol: GroupRole.values.byName(row['rol'] as String),
      cantidadMiembros: (conteo?['count'] as num?)?.toInt(),
    );
  }

  @override
  Future<List<GroupMember>> members(String groupId) => _guard(() async {
        final rows = await _client
            .from('group_members')
            .select('rol, joined_at, profiles(*)')
            .eq('group_id', groupId);
        return ordenarMiembros(rows.map(GroupMember.fromMap));
      });

  @override
  Future<Group> create({required String nombre, String? materia}) => _guard(() async {
        final row = await _client
            .rpc('create_group', params: {'p_nombre': nombre, 'p_materia': materia})
            .single();
        return Group.fromMap(row, miRol: GroupRole.admin, cantidadMiembros: 1);
      });

  @override
  Future<Group> join(String codigo) => _guard(() async {
        final row = await _client
            .rpc('join_group', params: {'p_code': Invite.normalizar(codigo)})
            .single();
        return Group.fromMap(row);
      });

  @override
  Future<void> update(String groupId, {required String nombre, String? materia}) =>
      _guard(() async {
        final materiaLimpia = materia?.trim();
        await _client.from('groups').update({
          'nombre': nombre.trim(),
          'materia': (materiaLimpia == null || materiaLimpia.isEmpty) ? null : materiaLimpia,
        }).eq('id', groupId);
      });

  @override
  Future<String> regenerateInviteCode(String groupId) => _guard(() async =>
      await _client.rpc('regenerate_invite_code', params: {'p_group_id': groupId}) as String);

  @override
  Future<void> removeMember(String groupId, String userId) => _guard(() =>
      _client.rpc('remove_member', params: {'p_group_id': groupId, 'p_user_id': userId}));

  @override
  Future<void> setRole(String groupId, String userId, GroupRole rol) => _guard(() => _client.rpc(
        'set_member_role',
        params: {'p_group_id': groupId, 'p_user_id': userId, 'p_rol': rol.name},
      ));

  @override
  Future<void> leave(String groupId) =>
      _guard(() => _client.rpc('leave_group', params: {'p_group_id': groupId}));

  @override
  Future<void> delete(String groupId) =>
      _guard(() => _client.from('groups').delete().eq('id', groupId));

  @override
  Stream<void> changes() {
    late final RealtimeChannel canal;
    final controller = StreamController<void>.broadcast(
      onCancel: () => _client.removeChannel(canal),
    );
    void emitir(PostgresChangePayload _) => controller.add(null);
    canal = _client
        .channel('grupos-$_uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'groups', callback: emitir)
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'group_members',
            callback: emitir)
        .subscribe();
    return controller.stream;
  }

  Future<T> _guard<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on PostgrestException catch (e) {
      throw GroupFailure(traducirErrorGrupo(e.code, e.message));
    }
  }
}

/// Las funciones SQL ya devuelven mensajes en español para los errores de
/// negocio (P0001); el resto se traduce acá.
String traducirErrorGrupo(String? code, String message) {
  switch (code) {
    case 'P0001':
      return message;
    case 'P0002':
      return 'El código de invitación no existe o ya no es válido';
    case '42501':
      return 'No tenés permiso para hacer esto';
    case '23514':
      return 'Revisá los datos: el nombre no puede quedar vacío';
  }
  return 'No se pudo completar la operación. Intentá de nuevo';
}
