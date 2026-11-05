import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/forms/validar.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/auth_layout.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../../files/domain/file_item.dart';
import '../../files/domain/files_repository.dart';
import '../../files/presentation/files_providers.dart';
import '../domain/delta.dart';
import '../domain/documento.dart';

/// "Nuevo › Documento": lo crea vacío, lo deja en modo edición y lo abre.
Future<void> nuevoDocumento(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  required String? folderId,
  required List<FileItem> existentes,
}) async {
  final usados = existentes.map((f) => f.nombre.toLowerCase()).toSet();
  final nombre = await pedirTexto(
    context,
    titulo: 'Documento nuevo',
    etiqueta: 'Nombre',
    accion: 'Crear',
    inicial: 'Documento sin título',
    ejemplo: 'Ej.: Informe final',
    maximo: 120,
    validator: (v) {
      final t = v?.trim() ?? '';
      final error = Validar.nombreArchivo(vacio: 'Ingresá un nombre para el documento')(t);
      if (error != null) return error;
      if (usados.contains('$t.$extensionDocumento'.toLowerCase())) return 'Ya hay un documento con ese nombre acá';
      return null;
    },
  );
  if (nombre == null || !context.mounted) return;
  final repo = ref.read(filesRepositoryProvider);
  try {
    final v = await repo.upload(
      groupId: groupId,
      folderId: folderId,
      nombre: '$nombre.$extensionDocumento',
      bytes: bytesDeOps(deltaVacio),
    );
    // Queda en edición para quien lo creó.
    await repo.lock(v.fileId, 120);
    if (context.mounted) context.push(Routes.documento(groupId, v.fileId));
  } on FilesFailure catch (e) {
    if (context.mounted) mostrarMensaje(context, e.mensaje, error: true);
  }
}
