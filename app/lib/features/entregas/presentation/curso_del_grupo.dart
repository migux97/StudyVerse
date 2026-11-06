import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../groups/domain/group.dart';
import '../domain/trabajo.dart';
import 'entregas_providers.dart';

/// Arriba del grupo (si está en un curso): el próximo trabajo a entregar y los
/// accesos a los trabajos y al material del docente.
class CursoDelGrupo extends ConsumerWidget {
  const CursoDelGrupo({super.key, required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (grupo.cursoId == null || grupo.soloLectura) return const SizedBox.shrink();
    final trabajos = ref.watch(trabajosDelGrupoProvider(grupo.id)).value ?? const <Trabajo>[];
    final entregas = ref.watch(entregasDelGrupoProvider(grupo.id)).value ?? const <String, Entrega>{};
    final ahora = DateTime.now();
    final pendientes = trabajos.where((t) => entregas[t.id] == null && !t.vencido(ahora)).toList();
    final aRehacer = entregas.values.where((e) => e.estado == EstadoEntrega.aRehacer).length;
    final theme = Theme.of(context);
    final proximo = pendientes.firstOrNull;
    final texto = proximo != null
        ? 'Próxima entrega: ${proximo.titulo} · ${formatearVencimiento(proximo.venceAt)}'
        : aRehacer > 0
            ? aRehacer == 1 ? 'Tienen 1 trabajo para rehacer' : 'Tienen $aRehacer trabajos para rehacer'
            : trabajos.isEmpty
                ? 'Del curso ${grupo.cursoNombre ?? ''}'.trim()
                : 'Están al día con las entregas';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.school_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(texto, style: theme.textTheme.bodyMedium)),
              ]),
              Wrap(spacing: 4, children: [
                TextButton.icon(
                  icon: Badge(
                    isLabelVisible: pendientes.isNotEmpty || aRehacer > 0,
                    label: Text('${pendientes.length + aRehacer}'),
                    child: const Icon(Icons.assignment_outlined, size: 18),
                  ),
                  label: const Text('Trabajos'),
                  onPressed: () => context.push(Routes.entregas(grupo.id)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_special_outlined, size: 18),
                  label: const Text('Material'),
                  onPressed: () => context.push(Routes.material(grupo.id)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
