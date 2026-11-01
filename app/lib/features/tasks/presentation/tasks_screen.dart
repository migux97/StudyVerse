import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/group_shell.dart';
import '../domain/task.dart';
import '../domain/tasks_repository.dart';
import 'task_form_dialog.dart';
import 'tasks_providers.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) =>
      GroupLoader(groupId: groupId, builder: (g) => _Tareas(grupo: g));
}

class _Tareas extends ConsumerStatefulWidget {
  const _Tareas({required this.grupo});
  final Group grupo;

  @override
  ConsumerState<_Tareas> createState() => _TareasState();
}

class _TareasState extends ConsumerState<_Tareas> {
  bool _soloMias = false;
  bool _verHechas = false;

  Group get grupo => widget.grupo;

  Future<void> _intentar(Future<void> Function() accion) async {
    try {
      await accion();
      ref.invalidate(tasksProvider(grupo.id));
    } on TasksFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

  Future<void> _nueva() async {
    final r = await abrirFormularioTarea(context, groupId: grupo.id);
    if (r is GuardarTarea) {
      await _intentar(() => ref.read(tasksRepositoryProvider).create(grupo.id, r.draft));
    }
  }

  Future<void> _editar(Task t, String? miId) async {
    final r = await abrirFormularioTarea(
      context,
      groupId: grupo.id,
      tarea: t,
      puedeEliminar: grupo.soyAdmin || t.createdBy == miId,
    );
    switch (r) {
      case GuardarTarea(:final draft):
        await _intentar(() => ref.read(tasksRepositoryProvider).update(t.id, draft));
      case EliminarTarea():
        if (!mounted) return;
        final ok = await confirmar(context,
            titulo: '¿Eliminar la tarea?', mensaje: '"${t.titulo}"', accion: 'Eliminar', peligroso: true);
        if (ok) await _intentar(() => ref.read(tasksRepositoryProvider).delete(t.id));
      case null:
        break;
    }
  }

  void _cambiarEstado(Task t, EstadoTarea estado) =>
      _intentar(() => ref.read(tasksRepositoryProvider).setEstado(t.id, estado));

  @override
  Widget build(BuildContext context) {
    final tareas = ref.watch(tasksProvider(grupo.id));
    final miId = ref.watch(authStateProvider).value?.id;

    return GroupShell(
      grupo: grupo,
      seccion: SeccionGrupo.tareas,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva tarea'),
        onPressed: _nueva,
      ),
      body: tareas.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Aviso(icono: Icons.error_outline, texto: e.toString()),
        data: (todas) {
          if (todas.isEmpty) {
            return Aviso(
              icono: Icons.task_alt_outlined,
              texto: 'Todavía no hay tareas',
              detalle: 'Repartan el TP: cada tarea con su responsable y su fecha límite.',
              accion: FilledButton.icon(
                icon: const Icon(Icons.add_task),
                label: const Text('Crear la primera'),
                onPressed: _nueva,
              ),
            );
          }

          final visibles = _soloMias ? todas.where((t) => t.assignedTo == miId) : todas;
          List<Task> de(EstadoTarea e) => ordenarTareas(visibles.where((t) => t.estado == e));
          final pendientes = de(EstadoTarea.pendiente);
          final enProgreso = de(EstadoTarea.enProgreso);
          final hechas = de(EstadoTarea.hecha);
          final ahora = DateTime.now();

          Widget tile(Task t) => _TareaTile(
                tarea: t,
                ahora: ahora,
                esMia: t.assignedTo == miId,
                onTap: () => _editar(t, miId),
                onEstado: (e) => _cambiarEstado(t, e),
              );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 112),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Todas'), icon: Icon(Icons.groups_outlined)),
                        ButtonSegment(value: true, label: Text('Mías'), icon: Icon(Icons.person_outline)),
                      ],
                      selected: {_soloMias},
                      onSelectionChanged: (s) => setState(() => _soloMias = s.single),
                    ),
                  ),
                  if (pendientes.isEmpty && enProgreso.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _soloMias ? 'No tenés tareas pendientes 🎉' : 'No quedan tareas pendientes 🎉',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  if (enProgreso.isNotEmpty) ...[
                    _Titulo('En progreso', enProgreso.length),
                    ...enProgreso.map(tile),
                  ],
                  if (pendientes.isNotEmpty) ...[
                    _Titulo('Pendientes', pendientes.length),
                    ...pendientes.map(tile),
                  ],
                  if (hechas.isNotEmpty) ...[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: _Titulo('Hechas', hechas.length),
                      trailing: Icon(_verHechas ? Icons.expand_less : Icons.expand_more),
                      onTap: () => setState(() => _verHechas = !_verHechas),
                    ),
                    if (_verHechas) ...hechas.map(tile),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, this.cantidad);
  final String texto;
  final int cantidad;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child: Text('$texto · $cantidad', style: Theme.of(context).textTheme.titleSmall),
      );
}

class _TareaTile extends StatelessWidget {
  const _TareaTile({
    required this.tarea,
    required this.ahora,
    required this.esMia,
    required this.onTap,
    required this.onEstado,
  });

  final Task tarea;
  final DateTime ahora;
  final bool esMia;
  final VoidCallback onTap;
  final void Function(EstadoTarea) onEstado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final venc = tarea.dueDate == null ? null : describirVencimiento(tarea, ahora);

    final (icono, color) = switch (tarea.estado) {
      EstadoTarea.pendiente => (Icons.radio_button_unchecked, scheme.outline),
      EstadoTarea.enProgreso => (Icons.timelapse, scheme.tertiary),
      EstadoTarea.hecha => (Icons.check_circle, scheme.primary),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        // Tocar el círculo la marca hecha (o la reabre); el menú da las 3 opciones.
        leading: IconButton(
          tooltip: tarea.hecha ? 'Marcar como pendiente' : 'Marcar como hecha',
          icon: Icon(icono, color: color),
          onPressed: () => onEstado(tarea.hecha ? EstadoTarea.pendiente : EstadoTarea.hecha),
        ),
        title: Text(
          tarea.titulo,
          style: tarea.hecha
              ? TextStyle(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant)
              : null,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Dato(
              icono: Icons.person_outline,
              texto: tarea.assignedTo == null
                  ? 'Sin responsable'
                  : esMia
                      ? 'Vos'
                      : (tarea.assignedNombre ?? 'Ex integrante'),
              resaltado: esMia,
            ),
            if (venc != null)
              _Dato(
                icono: venc.atrasada ? Icons.warning_amber_rounded : Icons.event_outlined,
                texto: venc.texto,
                color: venc.atrasada ? scheme.error : (venc.pronto ? scheme.tertiary : null),
              ),
            if (tarea.folderNombre != null) _Dato(icono: Icons.folder_outlined, texto: tarea.folderNombre!),
          ]),
        ),
        trailing: PopupMenuButton<EstadoTarea>(
          tooltip: 'Cambiar estado',
          onSelected: onEstado,
          itemBuilder: (_) => [
            for (final e in EstadoTarea.values)
              CheckedPopupMenuItem(value: e, checked: e == tarea.estado, child: Text(e.etiqueta)),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icono, required this.texto, this.color, this.resaltado = false});
  final IconData icono;
  final String texto;
  final Color? color;
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icono, size: 16, color: c),
      const SizedBox(width: 4),
      Text(texto,
          style: TextStyle(
              fontSize: 13, color: c, fontWeight: resaltado ? FontWeight.w600 : FontWeight.normal)),
    ]);
  }
}
