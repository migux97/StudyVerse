import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/colores_materia.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import '../domain/invite.dart';
import 'groups_providers.dart';

/// Crea un grupo y abre su carpeta.
Future<void> crearGrupo(BuildContext context, WidgetRef ref) async {
  final datos = await showDialog<({String nombre, List<String> materias})>(
    context: context,
    builder: (_) => const _GrupoFormDialog(titulo: 'Nuevo grupo', accion: 'Crear', conMaterias: true),
  );
  if (datos == null || !context.mounted) return;
  try {
    final g = await ref
        .read(groupsRepositoryProvider)
        .create(nombre: datos.nombre, materias: datos.materias);
    ref.invalidate(myGroupsProvider);
    if (context.mounted) context.push(Routes.grupo(g.id));
  } on GroupFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

/// Cambia el nombre del grupo (solo admin). Las materias se manejan adentro del grupo.
Future<void> editarGrupo(BuildContext context, WidgetRef ref, Group grupo) async {
  final datos = await showDialog<({String nombre, List<String> materias})>(
    context: context,
    builder: (_) => _GrupoFormDialog(titulo: 'Editar grupo', accion: 'Guardar', nombre: grupo.nombre),
  );
  if (datos == null || !context.mounted) return;
  try {
    await ref
        .read(groupsRepositoryProvider)
        .update(grupo.id, nombre: datos.nombre);
    ref.invalidate(groupProvider(grupo.id));
    ref.invalidate(myGroupsProvider);
  } on GroupFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

/// Pide un código (o un link pegado) y abre la pantalla de unirse.
Future<void> unirseConCodigo(BuildContext context, WidgetRef ref) async {
  final codigo = await showDialog<String>(
    context: context,
    builder: (_) => const _UnirseDialog(),
  );
  if (codigo != null && context.mounted) context.push(Routes.unirse(codigo));
}

class _GrupoFormDialog extends StatefulWidget {
  const _GrupoFormDialog({required this.titulo, required this.accion, this.nombre, this.conMaterias = false});
  final String titulo;
  final String accion;
  final String? nombre;

  /// Al crear: se cargan las materias (después se manejan desde el grupo).
  final bool conMaterias;

  @override
  State<_GrupoFormDialog> createState() => _GrupoFormDialogState();
}

class _GrupoFormDialogState extends State<_GrupoFormDialog> {
  late final _nombre = TextEditingController(text: widget.nombre);
  final _materia = TextEditingController();
  final _focoMateria = FocusNode();
  final _materias = <String>[];
  String? _errorMateria;
  final _formKey = GlobalKey<FormState>();

  /// El mismo tope que el plan gratis en la base (plan_limits.materias).
  static const _maxMaterias = 20;

  @override
  void dispose() {
    _nombre.dispose();
    _materia.dispose();
    _focoMateria.dispose();
    super.dispose();
  }

  /// Suma lo escrito como materia. Devuelve false si había un problema.
  bool _agregarMateria() {
    final m = _materia.text.trim();
    if (m.isEmpty) return true;
    final error = Validar.nombreArchivo(vacio: 'Ingresá el nombre de la materia')(m) ??
        (_materias.any((x) => x.toLowerCase() == m.toLowerCase()) ? 'Ya la agregaste' : null) ??
        (_materias.length >= _maxMaterias ? 'Podés agregar hasta $_maxMaterias materias' : null);
    setState(() {
      _errorMateria = error;
      if (error == null) {
        _materias.add(m);
        _materia.clear();
      }
    });
    _focoMateria.requestFocus();
    return error == null;
  }

  void _ok() {
    // Lo que quedó escrito sin apretar Enter también cuenta.
    if (widget.conMaterias && !_agregarMateria()) return;
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (nombre: _nombre.text.trim(), materias: List<String>.of(_materias)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _nombre,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo',
                  hintText: 'Ej.: Grupo de estudio 2.º año',
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: widget.conMaterias ? TextInputAction.next : TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                autovalidateMode: validarAlCorregir,
                validator: Validar.texto(vacio: 'Ingresá un nombre para el grupo', max: 80),
                onFieldSubmitted: widget.conMaterias ? null : (_) => _ok(),
              ),
              if (widget.conMaterias) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _materia,
                  focusNode: _focoMateria,
                  decoration: InputDecoration(
                    labelText: 'Materias (opcional)',
                    hintText: 'Ej.: Física II',
                    helperText: 'Escribí una y apretá Enter para sumar otra',
                    errorText: _errorMateria,
                    suffixIcon: IconButton(
                      tooltip: 'Agregar materia',
                      icon: const Icon(Icons.add),
                      onPressed: _agregarMateria,
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(120)],
                  onChanged: (_) {
                    if (_errorMateria != null) setState(() => _errorMateria = null);
                  },
                  onSubmitted: (_) => _materia.text.trim().isEmpty ? _ok() : _agregarMateria(),
                ),
                if (_materias.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (i, m) in _materias.indexed)
                      InputChip(
                        avatar: Icon(Icons.folder_special_rounded, color: colorMateria(context, i % 8)),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(m, overflow: TextOverflow.ellipsis),
                        ),
                        deleteButtonTooltipMessage: 'Quitar $m',
                        onDeleted: () => setState(() => _materias.removeAt(i)),
                      ),
                  ]),
                ],
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _ok,
          child: Text(widget.accion),
        ),
      ],
    );
  }
}

class _UnirseDialog extends StatefulWidget {
  const _UnirseDialog();

  @override
  State<_UnirseDialog> createState() => _UnirseDialogState();
}

class _UnirseDialogState extends State<_UnirseDialog> {
  final _codigo = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, Invite.extraerCodigo(_codigo.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unirme a un grupo'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _codigo,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Código o link de invitación',
              hintText: 'Ej.: ABCD-2345',
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            autovalidateMode: validarAlCorregir,
            onFieldSubmitted: (_) => _ok(),
            validator: (v) {
              if ((v ?? '').trim().isEmpty) return 'Ingresá el código o pegá el link';
              return Invite.extraerCodigo(v ?? '') == null
                  ? 'Ingresá un código válido: 8 letras y números, como ABCD-2345'
                  : null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _ok,
          child: const Text('Unirme'),
        ),
      ],
    );
  }
}
