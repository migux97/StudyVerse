import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../domain/group.dart';
import '../domain/groups_repository.dart';
import 'groups_providers.dart';

Future<void> salirDelGrupo(BuildContext context, WidgetRef ref, Group grupo) async {
  final esUltimo = grupo.cantidadMiembros == 1;
  final ok = await confirmar(
    context,
    titulo: '¿Salir de "${grupo.nombre}"?',
    mensaje: esUltimo
        ? 'Sos el único integrante: el grupo y todo su contenido se van a eliminar.'
        : 'Vas a dejar de ver sus archivos. Para volver vas a necesitar un código de invitación.',
    accion: 'Salir',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  await _ejecutar(context, ref, () => ref.read(groupsRepositoryProvider).leave(grupo.id));
}

Future<void> eliminarGrupo(BuildContext context, WidgetRef ref, Group grupo) async {
  final ok = await confirmar(
    context,
    titulo: '¿Eliminar "${grupo.nombre}"?',
    mensaje: 'Se elimina para todos los integrantes, con sus carpetas y archivos. '
        'No se puede deshacer.',
    accion: 'Eliminar',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;
  await _ejecutar(context, ref, () => ref.read(groupsRepositoryProvider).delete(grupo.id));
}

Future<void> _ejecutar(BuildContext context, WidgetRef ref, Future<void> Function() accion) async {
  try {
    await accion();
    ref.invalidate(myGroupsProvider);
    if (context.mounted) context.go(Routes.grupos);
  } on GroupFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}
