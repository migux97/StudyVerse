import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/validar.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../groups/domain/group.dart';
import '../../groups/domain/groups_repository.dart';
import '../../groups/presentation/group_shell.dart';
import '../../groups/presentation/groups_providers.dart';
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

  /// Devuelve si salió bien (si no, ya mostró el error).
  Future<bool> _intentar(Future<void> Function() accion) async {
    try {
      await accion();
      ref.invalidate(tasksProvider(grupo.id));
      return true;
    } on TasksFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      return false;
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
      puedeCerrar: grupo.puedoCerrarTareas,
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

  void _cambiarEstado(Task t, EstadoTarea estado) {
    if (estado == t.estado) return;
    // Un admin que pasa a hecha una entregada la está aprobando.
    if (estado == EstadoTarea.hecha && t.entregada && grupo.soyAdmin) {
      _revisar(t, aprobar: true);
      return;
    }
    // Con aprobación, "hecha" de alguien que no es admin = entregarla.
    if (estado == EstadoTarea.entregada || (estado == EstadoTarea.hecha && !grupo.puedoCerrarTareas)) {
      _entregar(t);
      return;
    }
    _intentar(() => ref.read(tasksRepositoryProvider).setEstado(t.id, estado));
  }

  Future<void> _entregar(Task t) async {
    final nota = await pedirTexto(
      context,
      titulo: 'Entregar "${t.titulo}"',
      etiqueta: 'Nota para quien la revisa (opcional)',
      ejemplo: 'Ej.: Lo subí a la carpeta TP 2',
      ayuda: grupo.aprobarTareas ? 'Un admin la revisa y la aprueba.' : null,
      accion: 'Entregar',
      maximo: 500,
      validator: Validar.opcional(500),
    );
    if (nota == null || !mounted) return;
    final ok = await _intentar(() => ref.read(tasksRepositoryProvider).entregar(t.id, nota: nota));
    if (ok && mounted) mostrarMensaje(context, 'Entregaste «${t.titulo}»');
  }

  Future<void> _revisar(Task t, {required bool aprobar}) async {
    String? nota;
    if (!aprobar) {
      nota = await pedirTexto(
        context,
        titulo: 'Pedir cambios',
        etiqueta: 'Qué hay que cambiar',
        ejemplo: 'Ej.: Falta la bibliografía',
        ayuda: 'La tarea vuelve a "En progreso" y le avisamos a quien la entregó.',
        accion: 'Pedir cambios',
        maximo: 500,
        validator: Validar.texto(vacio: 'Contale qué hay que cambiar', max: 500),
      );
      if (nota == null || !mounted) return;
    }
    final ok =
        await _intentar(() => ref.read(tasksRepositoryProvider).revisar(t.id, aprobar: aprobar, nota: nota));
    if (ok && mounted) mostrarMensaje(context, aprobar ? 'Aprobaste «${t.titulo}»' : 'Le pediste cambios');
  }

  Future<void> _setAprobar(bool v) async {
    try {
      await ref.read(groupsRepositoryProvider).setAprobarTareas(grupo.id, v);
      ref.invalidate(groupProvider(grupo.id));
      if (mounted) {
        mostrarMensaje(context, v ? 'Ahora un admin aprueba las tareas' : 'Ya no hace falta aprobar las tareas');
      }
    } on GroupFailure catch (e) {
      if (mounted) mostrarMensaje(context, e.mensaje, error: true);
    }
  }

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
          final entregadas = de(EstadoTarea.entregada);
          final hechas = de(EstadoTarea.hecha);
          final ahora = DateTime.now();

          Widget tile(Task t) => _TareaTile(
                tarea: t,
                ahora: ahora,
                esMia: t.assignedTo == miId,
                onTap: () => _editar(t, miId),
                onEstado: (e) => _cambiarEstado(t, e),
                grupo: grupo,
                miId: miId,
                onRevisar: (aprobar) => _revisar(t, aprobar: aprobar),
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
                  if (grupo.soyAdmin)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      secondary: const Icon(Icons.verified_outlined),
                      title: const Text('Las tareas las aprueba un admin'),
                      subtitle: const Text('Quien hace una tarea la marca como entregada y un admin la aprueba'),
                      value: grupo.aprobarTareas,
                      onChanged: _setAprobar,
                    )
                  else if (grupo.aprobarTareas)
                    const ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(Icons.verified_outlined),
                      title: Text('En este grupo, un admin aprueba las tareas'),
                      subtitle: Text('Cuando termines una, marcala como entregada'),
                    ),
                  if (entregadas.isNotEmpty) ...[
                    _Titulo(grupo.soyAdmin ? 'Para revisar' : 'Entregadas', entregadas.length),
                    ...entregadas.map(tile),
                  ],
                  if (pendientes.isEmpty && enProgreso.isEmpty && entregadas.isEmpty)
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
    required this.grupo,
    required this.miId,
    required this.onRevisar,
  });

  final Task tarea;
  final DateTime ahora;
  final bool esMia;
  final VoidCallback onTap;
  final void Function(EstadoTarea) onEstado;
  final Group grupo;
  final String? miId;
  final void Function(bool aprobar) onRevisar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final venc = tarea.dueDate == null ? null : describirVencimiento(tarea, ahora);

    final (icono, color) = switch (tarea.estado) {
      EstadoTarea.pendiente => (Icons.radio_button_unchecked, scheme.outline),
      EstadoTarea.enProgreso => (Icons.timelapse, scheme.tertiary),
      EstadoTarea.entregada => (Icons.outbox, scheme.secondary),
      EstadoTarea.hecha => (Icons.check_circle, scheme.primary),
    };
    final puedeCerrar = grupo.puedoCerrarTareas;
    // Qué hace tocar el círculo.
    final (tooltip, siguiente) = switch (tarea.estado) {
      EstadoTarea.hecha => ('Marcar como pendiente', EstadoTarea.pendiente),
      EstadoTarea.entregada when puedeCerrar => ('Aprobar', EstadoTarea.hecha),
      EstadoTarea.entregada => ('Esperando que un admin la apruebe', null),
      _ when puedeCerrar => ('Marcar como hecha', EstadoTarea.hecha),
      _ => ('Entregar', EstadoTarea.entregada),
    };
    final entrego = tarea.entregadaPor == null
        ? null
        : tarea.entregadaPor == miId
            ? 'Entregaste'
            : 'Entregó ${tarea.entregadaPorNombre ?? 'un ex integrante'}';
    final estiloNota = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final tile = ListTile(
        onTap: onTap,
        // Tocar el círculo la marca hecha (o la reabre); el menú da las 3 opciones.
        leading: IconButton(
          tooltip: tooltip,
          icon: Icon(icono, color: color),
          onPressed: switch (siguiente) {
            null => null,
            // El admin aprueba desde el círculo igual que con el botón.
            EstadoTarea.hecha when tarea.entregada => () => onRevisar(true),
            final s => () => onEstado(s),
          },
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
            if (tarea.entregada && entrego != null) _Dato(icono: Icons.outbox_outlined, texto: entrego),
            if (tarea.entregada && tarea.entregaNota != null)
              SizedBox(width: double.infinity, child: Text('"${tarea.entregaNota}"', style: estiloNota)),
            if (!tarea.hecha && !tarea.entregada && tarea.revisionNota != null)
              SizedBox(
                width: double.infinity,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Cambios pedidos: ', style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600)),
                    TextSpan(text: tarea.revisionNota),
                  ]),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ]),
        ),
        trailing: PopupMenuButton<EstadoTarea>(
          tooltip: 'Cambiar estado',
          onSelected: onEstado,
          itemBuilder: (_) => [
            for (final e in EstadoTarea.values)
              if ((e != EstadoTarea.entregada || grupo.aprobarTareas || tarea.entregada) &&
                  (e != EstadoTarea.hecha || puedeCerrar || tarea.hecha))
                CheckedPopupMenuItem(
                  value: e,
                  checked: e == tarea.estado,
                  child: Text(e == EstadoTarea.entregada && !tarea.entregada ? 'Entregar…' : e.etiqueta),
                ),
          ],
        ),
      );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tile,
        // El admin revisa desde acá (fuera del ListTile, para que entre en el celular).
        if (tarea.entregada && grupo.soyAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Aprobar'),
                onPressed: () => onRevisar(true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: const Text('Pedir cambios'),
                onPressed: () => onRevisar(false),
              ),
            ]),
          ),
      ]),
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
