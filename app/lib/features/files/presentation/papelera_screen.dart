import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/pagina.dart';
import '../domain/file_item.dart';
import 'file_actions.dart';
import 'file_icon.dart';
import 'files_providers.dart';

/// Papelera del grupo: lo que se eliminó en los últimos 30 días.
class PapeleraScreen extends ConsumerWidget {
  const PapeleraScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(papeleraProvider(groupId));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.grupo(groupId))),
        title: const Text('Papelera'),
      ),
      body: lista.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => SinVista(
          motivo: 'No pudimos cargar la papelera. Revisá tu conexión.',
          accion: TextButton(onPressed: () => ref.invalidate(papeleraProvider(groupId)), child: const Text('Reintentar')),
        ),
        data: (archivos) => archivos.isEmpty
            ? const SinVista(icono: Icons.delete_outline, motivo: 'La papelera está vacía.')
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: Text(
                          'Lo que está acá se borra solo a los $diasPapelera días.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Card(
                        child: Column(children: [
                          for (final (i, a) in archivos.indexed) ...[
                            if (i > 0) const Divider(height: 1, indent: 56),
                            _Fila(archivo: a),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.archivo});
  final FileItem archivo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = DateTime.now();
    final dias = archivo.diasEnPapelera(ahora);
    final quien = archivo.deletedByNombre ?? 'Alguien';
    final detalle = '$quien lo eliminó ${formatearFecha(archivo.deletedAt!, ahora)} · '
        '${dias <= 1 ? 'se borra mañana' : 'se borra en $dias días'}';
    final angosto = MediaQuery.sizeOf(context).width < 600;

    return ListTile(
      leading: FileIcon(kind: archivo.kind),
      title: Text(archivo.visible, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detalle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: angosto
          ? PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (op) => op == 'restaurar'
                  ? restaurarArchivo(context, ref, archivo)
                  : eliminarParaSiempre(context, ref, archivo),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'restaurar', child: ListTile(leading: Icon(Icons.restore), title: Text('Restaurar'))),
                PopupMenuItem(
                    value: 'eliminar',
                    child: ListTile(leading: Icon(Icons.delete_forever_outlined), title: Text('Eliminar para siempre'))),
              ],
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar'),
                onPressed: () => restaurarArchivo(context, ref, archivo),
              ),
              IconButton(
                tooltip: 'Eliminar para siempre',
                icon: const Icon(Icons.delete_forever_outlined),
                onPressed: () => eliminarParaSiempre(context, ref, archivo),
              ),
            ]),
    );
  }
}
