import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import '../domain/invite.dart';
import 'groups_providers.dart';

/// Crea un grupo y abre su carpeta.
Future<void> crearGrupo(BuildContext context, WidgetRef ref) async {
  final datos = await showDialog<({String nombre, String materia})>(
    context: context,
    builder: (_) => const _GrupoFormDialog(titulo: 'Nuevo grupo', accion: 'Crear'),
  );
  if (datos == null || !context.mounted) return;
  try {
    final g = await ref
        .read(groupsRepositoryProvider)
        .create(nombre: datos.nombre, materia: datos.materia);
    ref.invalidate(myGroupsProvider);
    if (context.mounted) context.push(Routes.grupo(g.id));
  } on GroupFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

/// Edita nombre y materia (solo admin).
Future<void> editarGrupo(BuildContext context, WidgetRef ref, Group grupo) async {
  final datos = await showDialog<({String nombre, String materia})>(
    context: context,
    builder: (_) => _GrupoFormDialog(
      titulo: 'Editar grupo',
      accion: 'Guardar',
      nombre: grupo.nombre,
      materia: grupo.materia,
    ),
  );
  if (datos == null || !context.mounted) return;
  try {
    await ref
        .read(groupsRepositoryProvider)
        .update(grupo.id, nombre: datos.nombre, materia: datos.materia);
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
  const _GrupoFormDialog({required this.titulo, required this.accion, this.nombre, this.materia});
  final String titulo;
  final String accion;
  final String? nombre;
  final String? materia;

  @override
  State<_GrupoFormDialog> createState() => _GrupoFormDialogState();
}

class _GrupoFormDialogState extends State<_GrupoFormDialog> {
  late final _nombre = TextEditingController(text: widget.nombre);
  late final _materia = TextEditingController(text: widget.materia);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nombre.dispose();
    _materia.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (nombre: _nombre.text.trim(), materia: _materia.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nombre,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre del grupo',
                hintText: 'Ej.: TP 2 - Grupo 4',
              ),
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Poné un nombre';
                if (t.length > 80) return 'Máximo 80 caracteres';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _materia,
              decoration: const InputDecoration(labelText: 'Materia (opcional)'),
              textCapitalization: TextCapitalization.sentences,
              onFieldSubmitted: (_) => _ok(),
              validator: (v) => (v?.trim().length ?? 0) > 80 ? 'Máximo 80 caracteres' : null,
            ),
          ]),
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
            onFieldSubmitted: (_) => _ok(),
            validator: (v) => Invite.extraerCodigo(v ?? '') == null
                ? 'El código tiene 8 letras y números, como ABCD-2345'
                : null,
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
