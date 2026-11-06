import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/group.dart';
import 'group_actions.dart';
import 'group_dialogs.dart';
import 'groups_providers.dart';
import 'invite_card.dart';
import '../../cursos/presentation/curso_acciones.dart';
import '../../chat/presentation/chat_providers.dart';

enum SeccionGrupo {
  archivos('Archivos', Icons.folder_outlined, Icons.folder),
  chat('Chat', Icons.forum_outlined, Icons.forum),
  tareas('Tareas', Icons.task_alt_outlined, Icons.task_alt),
  actividad('Actividad', Icons.history_outlined, Icons.history),
  aportes('Aportes', Icons.insights_outlined, Icons.insights);

  const SeccionGrupo(this.etiqueta, this.icono, this.iconoActivo);
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;

  String ruta(String groupId) => switch (this) {
        archivos => Routes.grupo(groupId),
        chat => Routes.chat(groupId),
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

  /// El docente no ve el chat (es de los alumnos).
  List<SeccionGrupo> get _secciones =>
      [for (final s in SeccionGrupo.values) if (s != SeccionGrupo.chat || !grupo.soloLectura) s];

  void _ir(BuildContext context, int i) {
    final destino = _secciones[i];
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
        title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(grupo.nombre, overflow: TextOverflow.ellipsis),
          if (grupo.cursoNombre != null)
            Text(
              [grupo.cursoNombre!, if (grupo.cursoDocente != null && !grupo.soloLectura) 'Prof. ${grupo.cursoDocente}']
                  .join(' · '),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ]),
        actions: [
          if (!grupo.soloLectura)
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
          if (grupo.soloLectura) _MenuDocente(grupo: grupo) else _MenuGrupo(grupo: grupo),
        ],
      ),
      // El docente no crea nada en el grupo.
      floatingActionButton: grupo.soloLectura ? null : floatingActionButton,
      bottomNavigationBar: ancho
          ? null
          : NavigationBar(
              selectedIndex: _secciones.indexOf(seccion).clamp(0, _secciones.length - 1),
              onDestinationSelected: (i) => _ir(context, i),
              destinations: [
                for (final s in _secciones)
                  NavigationDestination(
                    icon: _IconoSeccion(seccion: s, groupId: grupo.id),
                    selectedIcon: Icon(s.iconoActivo),
                    label: s.etiqueta,
                  ),
              ],
            ),
      body: ancho
          ? Row(children: [
              NavigationRail(
                selectedIndex: _secciones.indexOf(seccion).clamp(0, _secciones.length - 1),
                onDestinationSelected: (i) => _ir(context, i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final s in _secciones)
                    NavigationRailDestination(
                      icon: _IconoSeccion(seccion: s, groupId: grupo.id),
                      selectedIcon: Icon(s.iconoActivo),
                      label: Text(s.etiqueta),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _conAviso(body)),
            ])
          : _conAviso(body),
    );
  }

  Widget _conAviso(Widget body) => grupo.soloLectura
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BannerSoloLectura(),
          Expanded(child: body),
        ])
      : body;

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

enum _Accion { telegram, papelera, editar, salir, eliminar, curso }

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
        _Accion.curso => grupo.cursoId == null ? sumarACurso(context, ref, grupo) : quitarDelCurso(context, ref, grupo),
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
        if (grupo.soyAdmin)
          PopupMenuItem(
            value: _Accion.curso,
            child: ListTile(
              leading: Icon(grupo.cursoId == null ? Icons.school_outlined : Icons.link_off),
              title: Text(grupo.cursoId == null ? 'Sumar a un curso' : 'Quitar del curso'),
            ),
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

/// Para el docente: dejar de ver el grupo (lo saca del curso).
class _MenuDocente extends ConsumerWidget {
  const _MenuDocente({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<int>(
      tooltip: 'Más opciones',
      onSelected: (_) => quitarDelCurso(context, ref, grupo),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 0, child: ListTile(leading: Icon(Icons.link_off), title: Text('Quitar del curso'))),
      ],
    );
  }
}

/// Aviso arriba de todo cuando el docente mira un grupo.
class BannerSoloLectura extends StatelessWidget {
  const BannerSoloLectura({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(Icons.visibility_outlined, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Estás viendo este grupo como docente: podés leer y comentar.',
                style: TextStyle(color: scheme.onSecondaryContainer)),
          ),
        ]),
      ),
    );
  }
}

/// Ícono de una sección; el del chat lleva cuántos mensajes hay sin leer.
class _IconoSeccion extends ConsumerWidget {
  const _IconoSeccion({required this.seccion, required this.groupId});
  final SeccionGrupo seccion;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (seccion != SeccionGrupo.chat) return Icon(seccion.icono);
    final n = ref.watch(sinLeerDelGrupoProvider(groupId));
    return Badge(
      isLabelVisible: n > 0,
      label: Text(n > 99 ? '99+' : '$n'),
      child: Icon(seccion.icono),
    );
  }
}
