import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/validar.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../files/domain/file_item.dart' show formatearFecha;
import '../../groups/domain/group.dart';
import '../domain/aviso.dart';
import 'avisos_providers.dart';

/// Arriba del grupo: el último aviso del docente (y el botón para mandar uno,
/// si soy el docente). No ocupa lugar si no hay nada que mostrar.
class AvisosDelGrupo extends ConsumerWidget {
  const AvisosDelGrupo({super.key, required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (grupo.cursoId == null) return const SizedBox.shrink();
    final avisos = ref.watch(avisosDelGrupoProvider(grupo.id)).value ?? const <AvisoDocente>[];
    final docente = grupo.soloLectura;
    if (avisos.isEmpty && !docente) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ultimo = avisos.firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.campaign_outlined, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ultimo == null
                      ? 'Avisos para este grupo'
                      : 'Aviso de ${ultimo.autorNombre ?? 'tu docente'} · ${formatearFecha(ultimo.createdAt, DateTime.now())}',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ]),
            if (ultimo != null) ...[
              const SizedBox(height: 6),
              Text(ultimo.texto,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onTertiaryContainer)),
            ],
            Wrap(spacing: 4, children: [
              if (avisos.length > 1)
                TextButton(
                  onPressed: () => _verTodos(context, avisos),
                  child: Text('Ver todos (${avisos.length})'),
                ),
              if (docente)
                TextButton.icon(
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Mandar un aviso al grupo'),
                  onPressed: () => mandarAviso(context, ref, cursoId: grupo.cursoId!, grupo: grupo),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _verTodos(BuildContext context, List<AvisoDocente> avisos) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: ListaAvisos(avisos: avisos),
          ),
        ),
      );
}

/// Lista de avisos (el más nuevo arriba).
class ListaAvisos extends StatelessWidget {
  const ListaAvisos({super.key, required this.avisos, this.onBorrar});
  final List<AvisoDocente> avisos;
  final void Function(AvisoDocente)? onBorrar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ahora = DateTime.now();
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      itemCount: avisos.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = avisos[i];
        final destino = a.paraTodoElCurso ? 'A todo el curso' : 'A ${a.grupoNombre ?? 'un grupo'}';
        return ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: Text(a.texto),
          subtitle: Text([
            if (onBorrar != null) destino else (a.autorNombre ?? 'Tu docente'),
            formatearFecha(a.createdAt, ahora),
          ].join(' · ')),
          trailing: onBorrar == null
              ? null
              : IconButton(tooltip: 'Borrar aviso', icon: const Icon(Icons.delete_outline), onPressed: () => onBorrar!(a)),
          titleTextStyle: theme.textTheme.bodyLarge,
        );
      },
    );
  }
}

/// El docente manda un aviso a todo el curso o a un grupo. Con [grupo], va
/// directo a ese grupo; si no, se elige en el diálogo entre [grupos].
Future<void> mandarAviso(
  BuildContext context,
  WidgetRef ref, {
  required String cursoId,
  Group? grupo,
  List<({String id, String nombre})> grupos = const [],
}) async {
  final datos = await showDialog<({String? groupId, String texto})>(
    context: context,
    builder: (_) => _AvisoDialog(grupoFijo: grupo, grupos: grupos),
  );
  if (datos == null || !context.mounted) return;
  try {
    await ref.read(avisosRepositoryProvider).mandar(cursoId: cursoId, groupId: datos.groupId, texto: datos.texto);
    ref.invalidate(avisosDelCursoProvider(cursoId));
    if (grupo != null) ref.invalidate(avisosDelGrupoProvider(grupo.id));
    if (context.mounted) mostrarMensaje(context, 'Aviso enviado');
  } on AvisosFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

class _AvisoDialog extends StatefulWidget {
  const _AvisoDialog({this.grupoFijo, required this.grupos});
  final Group? grupoFijo;
  final List<({String id, String nombre})> grupos;

  @override
  State<_AvisoDialog> createState() => _AvisoDialogState();
}

class _AvisoDialogState extends State<_AvisoDialog> {
  final _texto = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late String? _destino = widget.grupoFijo?.id;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (groupId: _destino, texto: _texto.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.grupoFijo == null ? 'Mandar un aviso' : 'Aviso para ${widget.grupoFijo!.nombre}'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.grupoFijo == null) ...[
              DropdownButtonFormField<String?>(
                initialValue: _destino,
                decoration: const InputDecoration(labelText: 'Para'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todo el curso')),
                  for (final g in widget.grupos) DropdownMenuItem(value: g.id, child: Text(g.nombre)),
                ],
                onChanged: (v) => setState(() => _destino = v),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _texto,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(2000)],
              decoration: const InputDecoration(
                labelText: 'Aviso',
                hintText: 'Ej.: El parcial pasa al jueves 14. Repasen las unidades 1 a 4.',
                alignLabelWithHint: true,
              ),
              autovalidateMode: validarAlCorregir,
              validator: Validar.texto(vacio: 'Escribí el aviso', max: 2000),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(icon: const Icon(Icons.send, size: 18), label: const Text('Mandar'), onPressed: _ok),
      ],
    );
  }
}

/// Las devoluciones de una tarea, debajo de la tarea. Al docente le muestra
/// también el botón para dejar una.
class DevolucionesDeTarea extends ConsumerWidget {
  const DevolucionesDeTarea({super.key, required this.taskId, required this.grupo, this.miId});
  final String taskId;
  final Group grupo;
  final String? miId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(devolucionesProvider(grupo.id)).value?[taskId] ?? const <Devolucion>[];
    final docente = grupo.soloLectura;
    if (lista.isEmpty && !docente) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ultima = lista.lastOrNull;

    // En el celular, sin la sangría del círculo de la tarea.
    final izquierda = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 72.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(izquierda, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (ultima != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${ultima.autor == miId ? 'Tu devolución' : 'Devolución de ${ultima.autorNombre ?? 'tu docente'}'} · '
                '${formatearFecha(ultima.createdAt, DateTime.now())}',
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text(ultima.texto, style: theme.textTheme.bodyMedium),
            ]),
          ),
        Wrap(spacing: 4, children: [
          if (lista.length > 1)
            TextButton(onPressed: () => _verTodas(context, ref, lista), child: Text('Ver todas (${lista.length})')),
          if (docente)
            TextButton.icon(
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('Dar devolución'),
              onPressed: () => darDevolucion(context, ref, taskId: taskId, groupId: grupo.id),
            ),
        ]),
      ]),
    );
  }

  void _verTodas(BuildContext context, WidgetRef ref, List<Devolucion> lista) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
            for (final d in lista.reversed)
              ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: Text(d.texto),
                subtitle: Text('${d.autorNombre ?? 'Tu docente'} · ${formatearFecha(d.createdAt, DateTime.now())}'),
                trailing: d.autor == miId
                    ? IconButton(
                        tooltip: 'Borrar devolución',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await confirmar(context,
                              titulo: '¿Borrar la devolución?', mensaje: d.texto, accion: 'Borrar', peligroso: true);
                          if (!ok || !context.mounted) return;
                          try {
                            await ref.read(avisosRepositoryProvider).borrarDevolucion(d.id);
                            ref.invalidate(devolucionesProvider(d.groupId));
                          } on AvisosFailure catch (e) {
                            if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
                          }
                        },
                      )
                    : null,
              ),
          ]),
        ),
      );
}

/// El docente deja una devolución en una tarea.
Future<void> darDevolucion(BuildContext context, WidgetRef ref, {required String taskId, required String groupId}) async {
  final texto = await showDialog<String>(context: context, builder: (_) => const _DevolucionDialog());
  if (texto == null || !context.mounted) return;
  try {
    await ref.read(avisosRepositoryProvider).devolver(taskId: taskId, groupId: groupId, texto: texto);
    ref.invalidate(devolucionesProvider(groupId));
    if (context.mounted) mostrarMensaje(context, 'Devolución enviada');
  } on AvisosFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

class _DevolucionDialog extends StatefulWidget {
  const _DevolucionDialog();

  @override
  State<_DevolucionDialog> createState() => _DevolucionDialogState();
}

class _DevolucionDialogState extends State<_DevolucionDialog> {
  final _texto = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  void _ok() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _texto.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dar devolución'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _texto,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(2000)],
            decoration: const InputDecoration(
              labelText: 'Devolución',
              hintText: 'Ej.: Buena introducción. Falta citar la bibliografía en el desarrollo.',
              helperText: 'La ve todo el grupo y les avisamos a quienes hicieron la tarea.',
              helperMaxLines: 2,
              alignLabelWithHint: true,
            ),
            autovalidateMode: validarAlCorregir,
            validator: Validar.texto(vacio: 'Escribí la devolución', max: 2000),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok, child: const Text('Enviar')),
      ],
    );
  }
}
