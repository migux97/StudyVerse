import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/groups_providers.dart';
import '../domain/curso.dart';
import 'cursos_providers.dart';

/// Admin del grupo: lo suma al curso de un docente con su código.
Future<void> sumarACurso(BuildContext context, WidgetRef ref, Group grupo) async {
  final codigo = await pedirTexto(
    context,
    titulo: 'Sumar a un curso',
    etiqueta: 'Código del curso',
    ejemplo: 'Ej.: ABCDE-23456',
    ayuda: 'Te lo pasa tu docente. Va a poder ver los archivos, las tareas y los aportes del grupo, y comentar.',
    accion: 'Sumar',
    maximo: 20,
    validator: (v) {
      final limpio = (v ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (limpio.isEmpty) return 'Ingresá el código del curso';
      if (limpio.length != 10) return 'El código tiene 10 letras y números, como ABCDE-23456';
      return null;
    },
  );
  if (codigo == null || !context.mounted) return;
  try {
    final c = await ref.read(cursosRepositoryProvider).sumarGrupo(grupo.id, codigo);
    ref.invalidate(groupProvider(grupo.id));
    ref.invalidate(myGroupsProvider);
    if (context.mounted) mostrarMensaje(context, 'Sumaste el grupo a ${c.nombre}');
  } on CursosFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}

/// Lo saca del curso (admin del grupo o el docente).
Future<void> quitarDelCurso(BuildContext context, WidgetRef ref, Group grupo) async {
  final esDocente = grupo.soloLectura;
  final ok = await confirmar(
    context,
    titulo: esDocente ? '¿Quitar "${grupo.nombre}" del curso?' : '¿Quitar el grupo de ${grupo.cursoNombre ?? 'su curso'}?',
    mensaje: esDocente
        ? 'Vas a dejar de verlo. Para volver, el grupo tiene que sumarse de nuevo con el código.'
        : 'El docente deja de ver el grupo. No se borra nada.',
    accion: 'Quitar',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(cursosRepositoryProvider).quitarGrupo(grupo.id);
    ref.invalidate(misCursosProvider);
    if (esDocente) {
      // Primero se sale de la pantalla del grupo (ya no lo puede ver).
      if (context.mounted) context.go(Routes.grupos);
      return;
    }
    ref.invalidate(groupProvider(grupo.id));
    ref.invalidate(myGroupsProvider);
    if (context.mounted) mostrarMensaje(context, 'El grupo ya no está en el curso');
  } on CursosFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}
