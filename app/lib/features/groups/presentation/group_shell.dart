import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/group.dart';
import 'group_actions.dart';
import 'group_dialogs.dart';
import 'groups_providers.dart';
import 'invite_card.dart';

enum SeccionGrupo {
  archivos('Archivos', Icons.folder_outlined, Icons.folder),
  tareas('Tareas', Icons.task_alt_outlined, Icons.task_alt),
  actividad('Actividad', Icons.history_outlined, Icons.history),
  aportes('Aportes', Icons.insights_outlined, Icons.insights);

  const SeccionGrupo(this.etiqueta, this.icono, this.iconoActivo);
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;

  String ruta(String groupId) => switch (this) {
        archivos => Routes.grupo(groupId),
        tareas => Routes.tareas(groupId),
        actividad => Routes.actividad(groupId),
        aportes => Routes.aportes(groupId),
      };
}

/// Carga el grupo y muestra carga/error (p. ej. si te quitaron mientras lo
/// tenías abierto). Con los datos, llama a [builder].
class GroupLoader extends ConsumerWidget {
  const GroupLoader({super.key, required this.groupId, required this.builder});
  final String groupId;
  final Widget Function(Group grupo) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(groupProvider(groupId)).when(
          // En las recargas por cambios en vivo, seguir mostrando lo anterior.
          skipLoadingOnReload: true,
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: Aviso(
              icono: Icons.folder_off_outlined,
              texto: e.toString(),
              accion: FilledButton(
                onPressed: () => context.go(Routes.grupos),
                child: const Text('Ir a mis grupos'),
              ),
            ),
          ),
          data: builder,
        );
  }
}

/// Estructura común de las pantallas de un grupo: barra superior con
/// invitar/integrantes/menú y navegación entre secciones (abajo en el
/// celular, al costado en PC).
class GroupShell extends StatelessWidget {
  const GroupShell({
    super.key,
    required this.grupo,
    required this.seccion,
    required this.body,
    this.floatingActionButton,
    this.onBack,
  });

  final Group grupo;
  final SeccionGrupo seccion;
  final Widget body;
  final Widget? floatingActionButton;

  /// Por defecto vuelve a la pantalla anterior o a "Mis grupos".
  final VoidCallback? onBack;

  static const _anchoRail = 900.0;

  void _ir(BuildContext context, int i) {
    final destino = SeccionGrupo.values[i];
    if (destino != seccion) context.go(destino.ruta(grupo.id));
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width >= _anchoRail;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: onBack ?? () => context.canPop() ? context.pop() : context.go(Routes.grupos),
        ),
        title: Text(grupo.nombre),
        actions: [
          IconButton(
            tooltip: 'Invitar',
            icon: const Icon(Icons.person_add_alt_outlined),
            onPressed: () => _mostrarInvitacion(context),
          ),
          IconButton(
            tooltip: 'Integrantes',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => context.push(Routes.miembros(grupo.id)),
          ),
          _MenuGrupo(grupo: grupo),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: ancho
          ? null
          : NavigationBar(
              selectedIndex: seccion.index,
              onDestinationSelected: (i) => _ir(context, i),
              destinations: [
                for (final s in SeccionGrupo.values)
                  NavigationDestination(icon: Icon(s.icono), selectedIcon: Icon(s.iconoActivo), label: s.etiqueta),
              ],
            ),
      body: ancho
          ? Row(children: [
              NavigationRail(
                selectedIndex: seccion.index,
                onDestinationSelected: (i) => _ir(context, i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final s in SeccionGrupo.values)
                    NavigationRailDestination(
                      icon: Icon(s.icono),
                      selectedIcon: Icon(s.iconoActivo),
                      label: Text(s.etiqueta),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
    );
  }

  void _mostrarInvitacion(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: InviteCard(grupo: grupo),
      ),
    );
  }
}

/// Mensaje centrado con ícono y acción opcional (vacíos, errores).
class Aviso extends StatelessWidget {
  const Aviso({super.key, required this.icono, required this.texto, this.detalle, this.accion});
  final IconData icono;
  final String texto;
  final String? detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(texto, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (detalle != null) ...[
            const SizedBox(height: 8),
            Text(detalle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (accion != null) ...[const SizedBox(height: 24), accion!],
        ]),
      ),
    );
  }
}

enum _Accion { telegram, papelera, editar, salir, eliminar }

class _MenuGrupo extends ConsumerWidget {
  const _MenuGrupo({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_Accion>(
      tooltip: 'Más opciones',
      onSelected: (a) => switch (a) {
        _Accion.telegram => context.push(Routes.telegram(grupo.id)),
        _Accion.papelera => context.push(Routes.papelera(grupo.id)),
        _Accion.editar => editarGrupo(context, ref, grupo),
        _Accion.salir => salirDelGrupo(context, ref, grupo),
        _Accion.eliminar => eliminarGrupo(context, ref, grupo),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _Accion.telegram,
          child: ListTile(leading: Icon(Icons.send_outlined), title: Text('Avisos por Telegram')),
        ),
        const PopupMenuItem(
          value: _Accion.papelera,
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Papelera')),
        ),
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
