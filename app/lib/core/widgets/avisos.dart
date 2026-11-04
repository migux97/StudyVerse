import 'dart:math';

import 'package:flutter/material.dart';

/// El ScaffoldMessenger de toda la app: para avisar aunque la pantalla que
/// disparó la acción ya se haya cerrado.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Muestra un aviso con el messenger de la app (sin contexto de pantalla).
void avisarEnLaApp(String mensaje, {Duration? duracion}) {
  final ctx = scaffoldMessengerKey.currentContext;
  final messenger = scaffoldMessengerKey.currentState;
  if (ctx == null || messenger == null) return;
  messenger.showSnackBar(aviso(ctx, mensaje, duracion: duracion));
}

/// Aviso al pie, como los de Drive: oscuro, compacto y sin colores de alarma.
/// En pantallas anchas va abajo a la izquierda; en el celular ocupa el ancho.
SnackBar aviso(
  BuildContext context,
  String mensaje, {
  String? accion,
  VoidCallback? alTocar,
  Duration? duracion,
  bool cerrable = false,
}) {
  final ancho = MediaQuery.sizeOf(context).width;
  final margen = ancho < 600
      ? const EdgeInsets.fromLTRB(12, 0, 12, 12)
      : EdgeInsets.only(left: 24, bottom: 24, right: max(24, ancho - 24 - 440));
  return SnackBar(
    content: Text(mensaje),
    margin: margen,
    // Lo suficiente para leerlo con calma, sin quedar colgado.
    duration: duracion ?? Duration(milliseconds: (3500 + mensaje.length * 45).clamp(3500, 10000)),
    showCloseIcon: cerrable,
    action: accion == null ? null : SnackBarAction(label: accion, onPressed: alTocar ?? () {}),
  );
}

/// Muestra un aviso reemplazando el anterior. `error` no cambia el aspecto
/// (Drive tampoco lo hace): solo lo deja un poco más de tiempo.
void mostrarMensaje(
  BuildContext context,
  String mensaje, {
  bool error = false,
  String? accion,
  VoidCallback? alTocar,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(aviso(
      context,
      mensaje,
      accion: accion,
      alTocar: alTocar,
      duracion: error ? const Duration(seconds: 7) : null,
    ));
}
