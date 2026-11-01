import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/group.dart';
import 'group_actions.dart';
import 'group_dialogs.dart';
import 'groups_providers.dart';
import 'invite_card.dart';

/// Carpeta de un grupo. Los archivos se suman en la fase 3.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupo = ref.watch(groupProvider(groupId));

    return grupo.when(
      // En las recargas por cambios en vivo, seguir mostrando lo anterior.
      skipLoadingOnReload: true,
      loading:() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // P. ej. si te quitaron del grupo mientras lo tenías abierto.
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.folder_off_outlined,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(e.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(Routes.grupos),
                child: const Text('Ir a mis grupos'),
              ),
            ]),
          ),
        ),
      ),
      data: (g) => Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.grupos),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.nombre),
              if (g.materia != null)
                Text(g.materia!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Invitar',
              icon: const Icon(Icons.person_add_alt_outlined),
              onPressed: () => _mostrarInvitacion(context, g),
            ),
            IconButton(
              tooltip: 'Integrantes',
              icon: const Icon(Icons.group_outlined),
              onPressed: () => context.push(Routes.miembros(g.id)),
            ),
            _MenuGrupo(grupo: g),
          ],
        ),
        body: const _SinArchivos(),
      ),
    );
  }

  void _mostrarInvitacion(BuildContext context, Group g) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: InviteCard(grupo: g),
      ),
    );
  }
}

enum _Accion { editar, salir, eliminar }

class _MenuGrupo extends ConsumerWidget {
  const _MenuGrupo({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_Accion>(
      tooltip: 'Más opciones',
      onSelected: (a) => switch (a) {
        _Accion.editar => editarGrupo(context, ref, grupo),
        _Accion.salir => salirDelGrupo(context, ref, grupo),
        _Accion.eliminar => eliminarGrupo(context, ref, grupo),
      },
      itemBuilder: (_) => [
        if (grupo.soyAdmin)
          const PopupMenuItem(
            value: _Accion.editar,
            child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar grupo')),
          ),
        const PopupMenuItem(
          value: _Accion.salir,
          child: ListTile(leading: Icon(Icons.logout), title: Text('Salir del grupo')),
        ),
        if (grupo.soyAdmin)
          const PopupMenuItem(
            value: _Accion.eliminar,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Eliminar grupo'),
            ),
          ),
      ],
    );
  }
}

class _SinArchivos extends StatelessWidget {
  const _SinArchivos();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.description_outlined, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Todavía no hay archivos', style: theme.textTheme.titleMedium),
        ]),
      ),
    );
  }
}
