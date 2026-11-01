import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/folder_tree.dart';
import '../../files/presentation/explorer_list.dart';
import '../../files/presentation/file_actions.dart';
import '../../files/presentation/files_providers.dart';
import '../../files/presentation/uploads_panel.dart';
import '../domain/group.dart';
import 'group_actions.dart';
import 'group_dialogs.dart';
import 'groups_providers.dart';
import 'invite_card.dart';

/// Explorador de un grupo: carpetas y archivos, estilo Drive.
/// [folderId] null = raíz del grupo.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.groupId, this.folderId});
  final String groupId;
  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupo = ref.watch(groupProvider(groupId));

    return grupo.when(
      // En las recargas por cambios en vivo, seguir mostrando lo anterior.
      skipLoadingOnReload: true,
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // P. ej. si te quitaron del grupo mientras lo tenías abierto.
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: _Aviso(
          icono: Icons.folder_off_outlined,
          texto: e.toString(),
          accion: FilledButton(
            onPressed: () => context.go(Routes.grupos),
            child: const Text('Ir a mis grupos'),
          ),
        ),
      ),
      data: (g) => _Explorador(grupo: g, folderId: folderId),
    );
  }
}

class _Explorador extends ConsumerWidget {
  const _Explorador({required this.grupo, required this.folderId});
  final Group grupo;
  final String? folderId;

  void _abrirCarpeta(BuildContext context, String? id) => context.go(
        id == null ? Routes.grupo(grupo.id) : Routes.carpeta(grupo.id, id),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carpetas = ref.watch(foldersProvider(grupo.id));
    final archivos = ref.watch(filesProvider((groupId: grupo.id, folderId: folderId)));
    final miId = ref.watch(authStateProvider).value?.id;

    final todas = carpetas.value ?? const <Folder>[];
    final ruta = rutaHasta(folderId, todas);
    final carpetaNoExiste = carpetas.hasValue && folderId != null && ruta.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (ruta.isNotEmpty) return _abrirCarpeta(context, ruta.last.parentId);
            context.canPop() ? context.pop() : context.go(Routes.grupos);
          },
        ),
        title: Text(grupo.nombre),
        actions: [
          IconButton(
            tooltip: 'Invitar',
            icon: const Icon(Icons.person_add_alt_outlined),
            onPressed: () => _mostrarInvitacion(context, grupo),
          ),
          IconButton(
            tooltip: 'Integrantes',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => context.push(Routes.miembros(grupo.id)),
          ),
          _MenuGrupo(grupo: grupo),
        ],
      ),
      floatingActionButton: carpetaNoExiste
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
              onPressed: () => _menuNuevo(context, ref, archivos.value ?? const []),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Breadcrumbs(
            grupo: grupo,
            ruta: ruta,
            onTap: (id) => _abrirCarpeta(context, id),
          ),
          Expanded(
            child: carpetaNoExiste
                ? _Aviso(
                    icono: Icons.folder_off_outlined,
                    texto: 'Esta carpeta ya no existe',
                    accion: FilledButton(
                      onPressed: () => _abrirCarpeta(context, null),
                      child: Text('Ir a ${grupo.nombre}'),
                    ),
                  )
                : switch ((carpetas, archivos)) {
                    (AsyncValue(:final error?), _) || (_, AsyncValue(:final error?)) =>
                      _Aviso(icono: Icons.error_outline, texto: error.toString()),
                    (AsyncValue(hasValue: true), AsyncValue(value: final lista?)) =>
                      hijasDe(folderId, todas).isEmpty && lista.isEmpty
                          ? _CarpetaVacia(
                              onSubir: () => elegirYSubir(context, ref,
                                  groupId: grupo.id, folderId: folderId, existentes: lista, miId: miId),
                              onCarpeta: () => nuevaCarpeta(context, ref, grupo.id, folderId),
                            )
                          : RefreshIndicator(
                              onRefresh: () => Future.wait([
                                ref.refresh(foldersProvider(grupo.id).future),
                                ref.refresh(
                                    filesProvider((groupId: grupo.id, folderId: folderId)).future),
                              ]),
                              child: ExplorerList(
                                carpetas: hijasDe(folderId, todas),
                                archivos: lista,
                                miId: miId,
                                soyAdmin: grupo.soyAdmin,
                                onAbrirCarpeta: (c) => _abrirCarpeta(context, c.id),
                              ),
                            ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
          ),
          const UploadsPanel(),
        ],
      ),
    );
  }

  void _menuNuevo(BuildContext context, WidgetRef ref, List<FileItem> existentes) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Subir archivos'),
            onTap: () {
              Navigator.pop(ctx);
              elegirYSubir(context, ref,
                  groupId: grupo.id,
                  folderId: folderId,
                  existentes: existentes,
                  miId: ref.read(authStateProvider).value?.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Nueva carpeta'),
            onTap: () {
              Navigator.pop(ctx);
              nuevaCarpeta(context, ref, grupo.id, folderId);
            },
          ),
          const SizedBox(height: 8),
        ]),
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

/// "TP 2 - Grupo 4 › Informe › Anexos". Cada tramo lleva a esa carpeta.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.grupo, required this.ruta, required this.onTap});
  final Group grupo;
  final List<Folder> ruta;
  final void Function(String? folderId) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tramos = <(String?, String)>[(null, grupo.nombre), for (final c in ruta) (c.id, c.nombre)];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // si no entra, que se vea la carpeta actual
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // minWidth: si entra, que quede alineado a la izquierda.
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth - 24),
          child: Row(children: [
        for (final (i, (id, nombre)) in tramos.indexed) ...[
          if (i > 0) Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: i == tramos.length - 1
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              textStyle: theme.textTheme.titleMedium,
            ),
            onPressed: i == tramos.length - 1 ? null : () => onTap(id),
            child: Text(nombre),
          ),
        ],
          ]),
        ),
      ),
    );
  }
}

class _CarpetaVacia extends StatelessWidget {
  const _CarpetaVacia({required this.onSubir, required this.onCarpeta});
  final VoidCallback onSubir;
  final VoidCallback onCarpeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_upload_outlined, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Esta carpeta está vacía', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Subí el primer archivo o armá carpetas para ordenar el TP.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Subir archivos'),
              onPressed: onSubir,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Nueva carpeta'),
              onPressed: onCarpeta,
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, this.accion});
  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: 24), accion!],
          ]),
        ),
      );
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
            child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar grupo')),
          ),
      ],
    );
  }
}
