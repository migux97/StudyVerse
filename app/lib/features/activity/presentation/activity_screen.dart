import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../groups/domain/group.dart';
import '../../groups/presentation/group_shell.dart';
import '../domain/activity_item.dart';
import 'activity_providers.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) =>
      GroupLoader(groupId: groupId, builder: (g) => _Actividad(grupo: g));
}

class _Actividad extends ConsumerWidget {
  const _Actividad({required this.grupo});
  final Group grupo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(activityProvider(grupo.id));
    final miId = ref.watch(authStateProvider).value?.id;

    return GroupShell(
      grupo: grupo,
      seccion: SeccionGrupo.actividad,
      body: feed.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Aviso(icono: Icons.error_outline, texto: e.toString()),
        data: (eventos) {
          if (eventos.isEmpty) {
            return const Aviso(
              icono: Icons.history_outlined,
              texto: 'Todavía no pasó nada',
              detalle: 'Acá vas a ver quién subió qué, quién está editando y qué tareas se completaron.',
            );
          }
          final ahora = DateTime.now();
          final filas = <Widget>[];
          String? dia;
          for (final e in eventos) {
            final encabezado = encabezadoDia(e.createdAt, ahora);
            if (encabezado != dia) {
              dia = encabezado;
              filas.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(encabezado, style: Theme.of(context).textTheme.titleSmall),
              ));
            }
            filas.add(_EventoTile(evento: e, miId: miId, grupoId: grupo.id));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: RefreshIndicator(
                onRefresh: () => ref.refresh(activityProvider(grupo.id).future),
                child: ListView(padding: const EdgeInsets.only(bottom: 32), children: filas),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EventoTile extends StatelessWidget {
  const _EventoTile({required this.evento, required this.miId, required this.grupoId});
  final ActivityItem evento;
  final String? miId;
  final String grupoId;

  static IconData _icono(String tipo) => switch (tipo) {
        'version_subida' => Icons.upload_file_rounded,
        'version_restaurada' => Icons.restore_rounded,
        'archivo_bloqueado' => Icons.lock_outline,
        'archivo_desbloqueado' || 'desbloqueo_forzado' => Icons.lock_open_outlined,
        'archivo_renombrado' => Icons.drive_file_rename_outline,
        'archivo_eliminado' => Icons.delete_outline,
        'carpeta_creada' => Icons.create_new_folder_outlined,
        'miembro_unido' => Icons.person_add_alt_outlined,
        'miembro_salio' => Icons.person_remove_outlined,
        'tarea_creada' || 'tarea_asignada' => Icons.add_task,
        'tarea_completada' || 'tarea_aprobada' => Icons.task_alt,
        'tarea_entregada' => Icons.outbox_outlined,
        'aviso_docente' => Icons.campaign_outlined,
        'devolucion' => Icons.rate_review_outlined,
        'tarea_cambios_pedidos' => Icons.rate_review_outlined,
        'liberacion_pedida' => Icons.front_hand_outlined,
        'telegram_vinculado' => Icons.send_outlined,
        _ => Icons.circle_outlined,
      };

  /// A dónde lleva tocar el evento (null = a ningún lado).
  String? _destino() {
    if (evento.tipo.startsWith('tarea_')) return Routes.tareas(grupoId);
    if (evento.tipo == 'archivo_eliminado') return null;
    if (evento.esDeArchivo || evento.tipo == 'carpeta_creada') {
      final carpeta = evento.tipo == 'carpeta_creada' ? evento.payload['folder_id'] as String? : evento.folderId;
      return carpeta == null ? Routes.grupo(grupoId) : Routes.carpeta(grupoId, carpeta);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (:actor, :accion) = describirActividad(evento, miId: miId);
    final hora = TimeOfDay.fromDateTime(evento.createdAt.toLocal()).format(context);
    final destino = _destino();
    final nota = evento.payload['nota'] as String?;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(_icono(evento.tipo), size: 20, color: theme.colorScheme.onSecondaryContainer),
      ),
      title: Text.rich(TextSpan(children: [
        TextSpan(text: actor, style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: ' $accion'),
      ])),
      subtitle: Text(nota == null || evento.tipo != 'version_subida' ? hora : '$hora · "$nota"'),
      onTap: destino == null ? null : () => context.go(destino),
    );
  }
}
