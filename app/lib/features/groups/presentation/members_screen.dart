import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/user_avatar.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import 'group_actions.dart';
import 'groups_providers.dart';
import 'invite_card.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupo = ref.watch(groupProvider(groupId));
    final miembros = ref.watch(groupMembersProvider(groupId));
    final miId = ref.watch(authStateProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Integrantes')),
      // Los errores primero (p. ej. si te quitaron); en las recargas por
      // cambios en vivo se sigue mostrando la lista anterior.
      body: switch ((grupo, miembros)) {
        (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) =>
          Center(child: Text(error.toString())),
        (AsyncValue(value: final g?), AsyncValue(value: final lista?)) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  InviteCard(grupo: g),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      lista.length == 1 ? '1 integrante' : '${lista.length} integrantes',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Card(
                    child: Column(children: [
                      for (final (i, m) in lista.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _MiembroTile(grupo: g, miembro: m, esYo: m.profile.id == miId),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Salir del grupo'),
                    onPressed: () => salirDelGrupo(context, ref, g),
                  ),
                ],
              ),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

enum _AccionMiembro { hacerAdmin, quitarAdmin, quitar }

class _MiembroTile extends ConsumerWidget {
  const _MiembroTile({required this.grupo, required this.miembro, required this.esYo});
  final Group grupo;
  final GroupMember miembro;
  final bool esYo;

  Future<void> _accion(BuildContext context, WidgetRef ref, _AccionMiembro a) async {
    final repo = ref.read(groupsRepositoryProvider);
    final nombre = miembro.profile.nombre;
    try {
      switch (a) {
        case _AccionMiembro.hacerAdmin:
          await repo.setRole(grupo.id, miembro.profile.id, GroupRole.admin);
        case _AccionMiembro.quitarAdmin:
          await repo.setRole(grupo.id, miembro.profile.id, GroupRole.miembro);
        case _AccionMiembro.quitar:
          final ok = await confirmar(
            context,
            titulo: '¿Quitar a $nombre?',
            mensaje: 'Va a dejar de ver el grupo. Puede volver a entrar con un código de invitación.',
            accion: 'Quitar',
            peligroso: true,
          );
          if (!ok) return;
          await repo.removeMember(grupo.id, miembro.profile.id);
      }
      ref.invalidate(groupMembersProvider(grupo.id));
      ref.invalidate(groupProvider(grupo.id));
    } on GroupFailure catch (e) {
      if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      leading: UserAvatar(profile: miembro.profile),
      title: Text(esYo ? '${miembro.profile.nombre} (vos)' : miembro.profile.nombre),
      subtitle: Text(miembro.esAdmin ? 'Admin' : 'Miembro',
          style: TextStyle(
              color: miembro.esAdmin ? theme.colorScheme.primary : null)),
      trailing: grupo.soyAdmin && !esYo
          ? PopupMenuButton<_AccionMiembro>(
              tooltip: 'Opciones',
              onSelected: (a) => _accion(context, ref, a),
              itemBuilder: (_) => [
                if (miembro.esAdmin)
                  const PopupMenuItem(value: _AccionMiembro.quitarAdmin, child: Text('Quitar admin'))
                else
                  const PopupMenuItem(value: _AccionMiembro.hacerAdmin, child: Text('Hacer admin')),
                const PopupMenuItem(value: _AccionMiembro.quitar, child: Text('Quitar del grupo')),
              ],
            )
          : null,
    );
  }
}
