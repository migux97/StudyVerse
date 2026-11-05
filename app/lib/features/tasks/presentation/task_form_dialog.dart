import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/validar.dart';
import '../../files/domain/folder_tree.dart';
import '../../files/presentation/files_providers.dart';
import '../../groups/presentation/groups_providers.dart';
import '../domain/task.dart';

/// Resultado del formulario: guardar los datos o eliminar la tarea.
sealed class ResultadoTarea {}

class GuardarTarea extends ResultadoTarea {
  GuardarTarea(this.draft);
  final TaskDraft draft;
}

class EliminarTarea extends ResultadoTarea {}

/// Crear ([tarea] null) o editar una tarea.
Future<ResultadoTarea?> abrirFormularioTarea(
  BuildContext context, {
  required String groupId,
  Task? tarea,
  bool puedeEliminar = false,
}) =>
    showDialog<ResultadoTarea>(
      context: context,
      builder: (_) => _TareaDialog(groupId: groupId, tarea: tarea, puedeEliminar: puedeEliminar),
    );

class _TareaDialog extends ConsumerStatefulWidget {
  const _TareaDialog({required this.groupId, this.tarea, required this.puedeEliminar});
  final String groupId;
  final Task? tarea;
  final bool puedeEliminar;

  @override
  ConsumerState<_TareaDialog> createState() => _TareaDialogState();
}

class _TareaDialogState extends ConsumerState<_TareaDialog> {
  late final _titulo = TextEditingController(text: widget.tarea?.titulo);
  final _formKey = GlobalKey<FormState>();
  late String? _responsable = widget.tarea?.assignedTo;
  late DateTime? _fecha = widget.tarea?.dueDate;
  late String? _carpeta = widget.tarea?.folderId;
  late EstadoTarea _estado = widget.tarea?.estado ?? EstadoTarea.pendiente;

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoy.add(const Duration(days: 7)),
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
      helpText: 'Fecha límite',
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      GuardarTarea(TaskDraft(
        titulo: _titulo.text,
        assignedTo: _responsable,
        dueDate: _fecha,
        folderId: _carpeta,
        estado: _estado,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final miembros = ref.watch(groupMembersProvider(widget.groupId)).value ?? const [];
    // Los TP son las carpetas de primer nivel.
    final carpetas = hijasDe(null, ref.watch(foldersProvider(widget.groupId)).value ?? const []);
    final localizations = MaterialLocalizations.of(context);
    final editando = widget.tarea != null;

    return AlertDialog(
      title: Text(editando ? 'Editar tarea' : 'Nueva tarea'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _titulo,
                autofocus: !editando,
                decoration: const InputDecoration(
                  labelText: '¿Qué hay que hacer?',
                  hintText: 'Ej.: Escribir la conclusión',
                ),
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                autovalidateMode: validarAlCorregir,
                validator: Validar.texto(vacio: 'Escribí qué hay que hacer', max: 200),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: miembros.any((m) => m.profile.id == _responsable) ? _responsable : null,
                decoration: const InputDecoration(labelText: 'Responsable'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin responsable')),
                  for (final m in miembros)
                    DropdownMenuItem(value: m.profile.id, child: Text(m.profile.nombre)),
                ],
                onChanged: (v) => setState(() => _responsable = v),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _elegirFecha,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Fecha límite',
                    suffixIcon: _fecha == null
                        ? const Icon(Icons.event_outlined)
                        : IconButton(
                            tooltip: 'Quitar fecha',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _fecha = null),
                          ),
                  ),
                  child: Text(_fecha == null ? 'Sin fecha' : localizations.formatFullDate(_fecha!)),
                ),
              ),
              if (carpetas.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: carpetas.any((c) => c.id == _carpeta) ? _carpeta : null,
                  decoration: const InputDecoration(labelText: 'TP / carpeta (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todo el grupo')),
                    for (final c in carpetas) DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                  ],
                  onChanged: (v) => setState(() => _carpeta = v),
                ),
              ],
              if (editando) ...[
                const SizedBox(height: 16),
                SegmentedButton<EstadoTarea>(
                  segments: [
                    for (final e in EstadoTarea.values) ButtonSegment(value: e, label: Text(e.etiqueta)),
                  ],
                  selected: {_estado},
                  onSelectionChanged: (s) => setState(() => _estado = s.single),
                ),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        if (editando && widget.puedeEliminar)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, EliminarTarea()),
            child: const Text('Eliminar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _guardar,
          child: Text(editando ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
